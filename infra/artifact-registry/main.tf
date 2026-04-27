
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

terraform {
  backend "gcs" {
  }
}

locals {
  services = [
    "cloudresourcemanager.googleapis.com",
    "artifactregistry.googleapis.com",
  ]
}

data "google_project" "project" {
}

# Ensure the required APIs are enabled before creating the repository.
resource "google_project_service" "services" {
  for_each                   = toset(local.services)
  service                    = each.value
  project                    = var.project_id
  disable_dependent_services = true
}

# Manages the Artifact Registry Docker repository for GBFS Validator images,
# including cleanup policies to limit storage growth per environment.
resource "google_artifact_registry_repository" "gbfs_validator_repo" {
  depends_on = [google_project_service.services]
  repository_id          = var.repository_id
  location               = var.gcp_region
  project                = var.project_id
  format                 = "DOCKER"
  description            = "GBFS Validator Docker images (${var.environment})"
  cleanup_policy_dry_run = false

  # Keep the N most recent tagged versions to allow rollbacks.
  cleanup_policies {
    id     = "keep-minimum-versions"
    action = "KEEP"
    most_recent_versions {
      keep_count = var.keep_tagged_count
    }
  }

  # Delete untagged (intermediate build) images after a short retention window.
  cleanup_policies {
    id     = "delete-old-untagged"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = var.untagged_older_than
    }
  }
}

output "repository_name" {
  value       = google_artifact_registry_repository.gbfs_validator_repo.name
  description = "Full resource name of the Artifact Registry repository."
}
