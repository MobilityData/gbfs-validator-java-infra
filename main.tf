terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

resource "google_storage_bucket" "source_bucket" {
  name                        = var.source_bucket_name
  location                    = var.gcp_region
  uniform_bucket_level_access = true
  # Adding labels for better resource management and cost tracking
  labels = {
    environment = var.environment
    app         = var.function_name
  }
}

data "archive_file" "source_zip" {
  type        = "zip"
  source_file = var.jar_file_path # Path to the JAR file provided by the user
  output_path = "/tmp/function-source.zip" # Temporary path for the zipped JAR
}

resource "google_storage_bucket_object" "source_archive" {
  name   = "function-source-${data.archive_file.source_zip.output_md5}.zip"
  bucket = google_storage_bucket.source_bucket.name
  source = data.archive_file.source_zip.output_path # Path to the zipped JAR
}

resource "google_cloudfunctions_function" "function" {
  name        = var.function_name
  description = "GBFS Validator Cloud Function"
  runtime     = var.function_runtime
  region      = var.gcp_region
  project     = var.gcp_project_id

  available_memory_mb   = var.function_memory_mb
  timeout_seconds       = var.function_timeout_s
  entry_point           = var.function_entry_point
  trigger_http          = true
  source_archive_bucket = google_storage_bucket.source_bucket.name
  source_archive_object = google_storage_bucket_object.source_archive.name

  labels = {
    environment = var.environment
    app         = var.function_name
  }

  # Depending on the function's needs, you might need to configure environment variables
  # environment_variables = {
  #   FOO = "bar"
  # }
}
