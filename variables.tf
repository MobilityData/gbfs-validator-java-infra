variable "gcp_project_id" {
  description = "The GCP project ID."
  type        = string
}

variable "gcp_region" {
  description = "The GCP region for the Cloud Function."
  type        = string
  default     = "us-central1"
}

variable "function_name" {
  description = "The name of the Cloud Function."
  type        = string
  default     = "gbfs-validator-function"
}

variable "function_entry_point" {
  description = "The entry point of the function in the JAR file (e.g., com.example.MyFunction)."
  type        = string
}

variable "jar_file_path" {
  description = "The path to the JAR file within the repository."
  type        = string
}

variable "environment" {
  description = "The deployment environment (e.g., dev, qa, prod)."
  type        = string
}

variable "source_bucket_name" {
  description = "The name of the GCS bucket to store the function's source code."
  type        = string
}

variable "function_runtime" {
  description = "The runtime for the Cloud Function."
  type        = string
  default     = "java11" # Or java17, java21 depending on the JAR
}

variable "function_memory_mb" {
  description = "The memory allocated to the Cloud Function in MB."
  type        = number
  default     = 256
}

variable "function_timeout_s" {
  description = "The timeout for the Cloud Function in seconds."
  type        = number
  default     = 60
}
