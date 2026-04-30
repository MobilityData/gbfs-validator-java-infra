#!/bin/bash

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

###############################################################################
# Deployer SA Permissions Script
#
# Grants the deployer service account all IAM roles needed to run
# Terraform apply for the GBFS Validator infrastructure.
#
# This is a one-time setup per GCP project. Run it manually before
# the first CI/CD deployment.
#
# USAGE:
#   ./setup-deployer-sa-permissions.sh <PROJECT_ID>
#
# EXAMPLE:
#   ./setup-deployer-sa-permissions.sh gbfs-validator-staging
#
###############################################################################

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <PROJECT_ID>"
  exit 1
fi

PROJECT_ID="$1"
SA="gbfs-deployer-service-account@${PROJECT_ID}.iam.gserviceaccount.com"

echo "Granting deployer SA permissions on project: ${PROJECT_ID}"
echo "Service account: ${SA}"
echo ""

ROLES=(
  # Artifact Registry — push/manage Docker images
  roles/artifactregistry.admin

  # Cloud Run — create/update/delete services
  roles/run.admin

  # Compute — load balancer, NEG, URL maps, forwarding rules
  roles/compute.loadBalancerAdmin

  # Compute — Cloud Armor security policies
  roles/compute.securityAdmin

  # IAM — create service accounts (for Cloud Run runtime SA)
  roles/iam.serviceAccountAdmin

  # IAM — impersonate service accounts
  roles/iam.serviceAccountTokenCreator

  # IAM — attach SAs to Cloud Run services
  roles/iam.serviceAccountUser

  # IAM — set IAM policies (e.g. allUsers invoker on Cloud Run)
  roles/resourcemanager.projectIamAdmin

  # Storage — read/write Terraform state bucket
  roles/storage.admin
)

for ROLE in "${ROLES[@]}"; do
  echo "  Granting ${ROLE}..."
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA}" \
    --role="$ROLE" \
    --quiet --no-user-output-enabled
done

echo ""
echo "✅ All roles granted to ${SA}"
