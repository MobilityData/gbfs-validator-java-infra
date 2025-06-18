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
  gbfs_validator_config = jsondecode(file("${path.module}/../../gbfs-validator/function_config.json"))
  artifact_registry_repo = "gbfs-validator-${var.environment}"
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
  name        = "${var.environment}-${local.gbfs_validator_config.name_suffix}"
  location = var.gcp_region
  ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  template {
    service_account = var.gbfs_validator_service_account_email
    containers {
      image = "${var.gcp_region}-docker.pkg.dev/${var.project_id}/${local.artifact_registry_repo}/${var.gbfs_api_service}:${var.feed_api_image_version}"
      resources {
        limits = {
          cpu    = local.gbfs_validator_config.available_cpu
          memory = local.gbfs_validator_config.available_memory
        }
      }
    }
  }

  labels = {
    environment = var.environment
    app         = var.gbfs_validator_app_name
  }
}
