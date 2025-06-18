output "function_url" {
  description = "The HTTPS trigger URL for the Cloud Function."
  value       = google_cloud_run_v2_service.gbfs_validator_api.uri
}

output "cloud_run_service_name" {
  description = "Name of the cloud run resource"
  value = google_cloud_run_v2_service.gbfs_validator_api.name
}