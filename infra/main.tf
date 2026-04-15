
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

# GCS remote state backend. Configuration is supplied via -backend-config=backend.conf at init time.
terraform {
  backend "gcs" {}
}

# Service account to execute the cloud functions.
# CI/CD: account_id is suffixed with the environment (e.g. gbfs-validator-dev-service-account)
# because dev and qa share the same GCP project (gbfs-validator-staging). Without the suffix
# both TF states would attempt to manage the same SA resource, causing conflicts on apply.
resource "google_service_account" "gbfs_validator_service_account" {
  project      = var.project_id
  account_id   = "gbfs-validator-service-account-${var.environment}"
  display_name = "GBFS Validator Service Account (${var.environment})"
}

# CI/CD: The deployer service account data source was removed. The deployer SA email
# is now passed in via var.deployer_service_account (populated from vars.tfvars at
# runtime), which allows each environment to use its own project's SA without
# changing Terraform code. provider.tf references the variable directly for impersonation.
module "cloud_run" {
  source                = "./cloud-run-service"
  environment           = var.environment
  gbfs_validator_service_account_email = google_service_account.gbfs_validator_service_account.email
  gbfs_api_image_version = var.gbfs_api_image_version
}

module "load_balancer" {
  source            = "./load-balancer"
  environment           = var.environment
  cloud_run_service_name = module.cloud_run.cloud_run_service_name
}
