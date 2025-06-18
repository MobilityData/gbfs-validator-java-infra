
# Service account to execute the cloud functions
resource "google_service_account" "gbfs_validator_service_account" {
  project    = var.project_id
  account_id   = "gbfs-validator-service-account"
  display_name = "GBFS Validator Service Account"
}

data "google_service_account" "gbfs_deployer_service_account" {
  project    = var.project_id
  account_id = "gbfs-deployer-service-account"
}

module "cloud_run" {
  source                = "./cloud-run-service"
  environment           = var.environment
  gbfs_validator_service_account_email = google_service_account.gbfs_validator_service_account.email
}

module "load_balancer" {
  source            = "./load-balancer"
  environment           = var.environment
  cloud_run_service_name = module.cloud_run.cloud_run_service_name
}
