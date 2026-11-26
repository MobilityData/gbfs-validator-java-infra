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

# Values the Cloudflare Worker needs as secrets (see docs/edge-cutover.md).
output "cloud_run_url" {
  description = "run.app URL the Cloudflare Worker forwards validation requests to"
  value       = module.cloud_run.function_url
}

output "edge_service_account_email" {
  description = "Service account whose key the Cloudflare Worker uses to invoke Cloud Run"
  value       = google_service_account.gbfs_edge_service_account.email
}
