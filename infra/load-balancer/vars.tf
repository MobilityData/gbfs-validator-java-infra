variable "project_id" {
  type        = string
  description = "GCP project ID"
  default = "gbfs-validator-staging"
}

variable "gcp_region" {
  type        = string
  description = "GCP region"
  default = "northamerica-northeast1"
}

variable "environment" {
  type        = string
  description = "API environment. Possible values: prod, qa and dev"
}

variable "cloud_run_service_name" {
  description = "Cloud Run service name to attach to the NEG"
  type        = string
}

variable "rate_limit_count" {
  description = "Requests per interval before limiting"
  type        = number
  default     = 100
}

variable "rate_limit_interval_sec" {
  description = "Time window for rate limit threshold (in seconds)"
  type        = number
  default     = 60
}

variable "ban_count" {
  description = "Number of requests before banning"
  type        = number
  default     = 200
}

variable "ban_interval_sec" {
  description = "Time window for ban threshold (in seconds)"
  type        = number
  default     = 300
}

variable "ban_duration_sec" {
  description = "Duration to ban the client (in seconds)"
  type        = number
  default     = 300
}
