
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
}

variable "gcp_region" {
  type        = string
  description = "GCP region where the repository will be created"
}

variable "repository_id" {
  type        = string
  description = "Artifact Registry repository ID (e.g. gbfs-validator or gbfs-validator-staging)"
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev, qa, or prod) — used only in the repository description"
}

variable "deployer_service_account" {
  type        = string
  description = "Service account email used to deploy resources via impersonation"
}

variable "keep_tagged_count" {
  type        = number
  description = "Number of most-recent tagged images to retain for rollback purposes"
  default     = 10
}

variable "untagged_older_than" {
  type        = string
  description = "Delete untagged images older than this duration string (e.g. '604800s' = 7 days)"
  default     = "604800s"
}
