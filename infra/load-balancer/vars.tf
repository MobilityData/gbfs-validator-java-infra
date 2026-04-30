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

variable "project_id" {
  type        = string
  description = "GCP project ID"
  default     = "gbfs-validator-staging"
}

variable "gcp_region" {
  type        = string
  description = "GCP region"
  default     = "northamerica-northeast1"
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
