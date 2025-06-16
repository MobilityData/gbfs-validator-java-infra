output "function_url" {
  description = "The HTTPS trigger URL for the Cloud Function."
  value       = google_cloudfunctions_function.function.https_trigger_url
}

output "source_bucket_url" {
  description = "The URL of the GCS bucket used for storing the function source."
  value       = google_storage_bucket.source_bucket.url
}
