#
# MobilityData 2025
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# This make the google project information accessible only keeping the project_id as a parameter in the previous provider resource
data "google_project" "project" {
}

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

locals {
  gbfs_validator_config  = jsondecode(file("${path.module}/../../gbfs-validator/function_config.json"))
  artifact_registry_repo = "${var.artifact_registry_repo}/${var.environment}"
  # The instance cap is the hard cost ceiling: with request-based billing an instance costs
  # nothing while idle, and at most max_instance_count instances can ever be billed at once.
  max_instance_count = var.environment == "prod" ? local.gbfs_validator_config.max_instance_count : local.gbfs_validator_config.max_instance_count_non_prod
}

provider "google" {
  project = var.project_id
  region  = var.gcp_region
}

# This is a temporary patch until the publising of the Java jar is defined
data "archive_file" "source_zip" {
  type        = "zip"
  source_file = "${path.module}/../../gbfs-validator/${var.jar_file_name}"
  output_path = "/tmp/function-source.zip" # Temporary path for the zipped JAR
}

resource "google_cloud_run_v2_service" "gbfs_validator_api" {
  name     = "${var.environment}-${local.gbfs_validator_config.name_suffix}"
  location = var.gcp_region
  # Public traffic reaches the service through the Cloudflare Worker (mobilitydata-sites in
  # MobilityData/org-cloudflare-workers), which calls the run.app URL with an ID token of the
  # edge service account. Ingress is open, but only that service account may invoke (see below).
  # The legacy load balancer also works with this ingress during the cutover.
  ingress = "INGRESS_TRAFFIC_ALL"

  template {
    service_account                  = var.gbfs_validator_service_account_email
    timeout                          = "${local.gbfs_validator_config.timeout}s"
    max_instance_request_concurrency = local.gbfs_validator_config.max_instance_request_concurrency

    scaling {
      min_instance_count = local.gbfs_validator_config.min_instance_count
      max_instance_count = local.max_instance_count
    }

    containers {
      image = "${var.gcp_region}-docker.pkg.dev/${var.project_id}/${local.artifact_registry_repo}/${var.gbfs_api_service}:${var.gbfs_api_image_version}"
      resources {
        limits = {
          cpu    = local.gbfs_validator_config.available_cpu
          memory = local.gbfs_validator_config.available_memory
        }
        # Request-based billing: CPU is billed only while a request is processed (and during
        # startup). Instance-based billing kept an idle instance billed after every bot hit.
        cpu_idle = true
      }
      # Without it the JVM caps its heap at 25% of the container memory, and large feeds fail with
      # OutOfMemoryError while most of the memory is unused (load test in docs/edge-cutover.md).
      env {
        name  = "JAVA_TOOL_OPTIONS"
        value = local.gbfs_validator_config.java_tool_options
      }
      # The validator ships Swagger UI (springdoc) for whoever runs it. Our deployment serves
      # only POST /validate; the public API docs are on GitHub Pages (MobilityData/gbfs-validator-java).
      env {
        name  = "SPRINGDOC_SWAGGERUI_ENABLED"
        value = "false"
      }
      env {
        name  = "SPRINGDOC_APIDOCS_ENABLED"
        value = "false"
      }
    }
  }

  labels = {
    environment = var.environment
    app         = var.gbfs_validator_app_name
  }
}


# Public invoker for the legacy load balancer, only during the Cloudflare edge cutover
# (var.allow_unauthenticated). Removed with it in the follow-up change.
resource "google_cloud_run_service_iam_member" "gbfs_validator_invoker" {
  count    = var.allow_unauthenticated ? 1 : 0
  project  = var.project_id
  location = var.gcp_region
  service  = google_cloud_run_v2_service.gbfs_validator_api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

moved {
  from = google_cloud_run_service_iam_member.gbfs_validator_invoker
  to   = google_cloud_run_service_iam_member.gbfs_validator_invoker[0]
}

# Once the cutover is done, only the edge service account may invoke the service. Requests to
# the run.app URL without its ID token are rejected by Cloud Run IAM before reaching the container.
resource "google_cloud_run_service_iam_member" "gbfs_validator_edge_invoker" {
  project  = var.project_id
  location = var.gcp_region
  service  = google_cloud_run_v2_service.gbfs_validator_api.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${var.edge_service_account_email}"
}