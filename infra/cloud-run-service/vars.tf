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

variable "gbfs_validator_app_name" {
  type = string
  description = "App name for better resource management and cost tracking"
  default = "gbfs_validator"
}

variable "gbfs_api_service" {
  type = string
  description = "GBFS API service name as defined in the artifact registry"
  default = "gbfs_validator_api"
}

variable "feed_api_image_version" {
  type = string
  description = "API image version"
  default = "latest"
}

variable "java_runtime" {
  type = string
  description = "Java function runtime"
  default = "java17"
}

# This is a temporary patch until the publising of the Java jar is defined
variable "jar_file_name" {
    type = string
    default = "gbfs-validator-java-api.jar"
}

# variable "deployer_service_account" {
#   type        = string
#   description = "Service account used to deploy resources using impersonation"
#   default = "gbfs_deployer_service_account"
# }

variable "gbfs_validator_service_account_email" {
    type = string
    description = "Service account use for runtime operations"
}