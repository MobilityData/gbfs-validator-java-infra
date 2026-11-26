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

#
# -----------------------------------------------------------------------------
# GBFS Validator: GCP Project Bootstrap Script
# -----------------------------------------------------------------------------
#
# This script provisions a GCP environment for the GBFS Validator deployment.
#
# Features:
# - Creates a deployer service account (`gbfs-deployer-service-account`)
# - Grants necessary IAM roles for Terraform and Cloud Functions
# - Allows impersonation by the local user running the script
# - Enables the Artifact Registry API
# - Creates a Docker-format Artifact Registry repository per environment
# - Applies a cleanup policy:
#     - KEEP the latest 5 image versions (any tag state)
#     - DELETE any untagged images older than 30 days
#
# Resources created or configured:
# - Service Account: gbfs-deployer-service-account@<PROJECT_ID>.iam.gserviceaccount.com
# - IAM Roles: cloudfunctions.developer, storage.admin, iam.serviceAccountAdmin,
#   iam.serviceAccountTokenCreator, iam.serviceAccountUser
# - IAM Policy Bindings for service account impersonation
# - Artifact Registry API enabled
# - Artifact Registry repository: gbfs-validator-<ENVIRONMENT>
# - Artifact Registry cleanup policies (keep latest 5 images, delete untagged >30d)
# - Google APIs enabled: artifactregistry, cloudfunctions, cloudbuild, run,
#   cloudresourcemanager
# - No load balancer, static IPs or SSL certificates: the public hostname is served by a
#   Cloudflare Worker (see docs/edge-cutover.md)
# - IAM Policy Binding for deployer to impersonate gbfs-validator-service-account
#
# Usage:
#   ./setup-environment.sh <GCP_PROJECT_ID> <ENVIRONMENT> [<REGION>] [<ARTIFACT_REGISTRY_REPO>]
#
#   GCP_PROJECT_ID          - Required. Your Google Cloud project ID.
#   ENVIRONMENT             - Required. Deployment environment (e.g., dev, qa, prod).
#   REGION                  - Optional. GCP region (default: northamerica-northeast1).
#   ARTIFACT_REGISTRY_REPO  - Optional. Shared AR repo name (default: gbfs-validator-staging).
#                             Use "gbfs-validator" for prod.
#
# Example (staging):
#   ./setup-environment.sh gbfs-validator-staging qa
#
# Example (prod):
#   ./setup-environment.sh gbfs-validator prod northamerica-northeast1 gbfs-validator
#
# Notes:
# - Requires `gcloud` CLI installed and authenticated.
# - Run this once per environment before deploying Terraform-managed resources.
#
# -----------------------------------------------------------------------------


set -euo pipefail

PROJECT_ID="${1:?Usage: $0 <GCP_PROJECT_ID>}"
ENVIRONMENT="${2:?Usage: $0 <ENVIRONMENT>}"
REGION="${3:-northamerica-northeast1}"  # Default to Montréal
REPO_NAME="${4:-gbfs-validator-staging}"  # Shared repo; use "gbfs-validator" for prod
LOCAL_USER_EMAIL=$(gcloud config get-value account)
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")

DEPLOYER_SA_NAME="gbfs-deployer-service-account"
DEPLOYER_SA="${DEPLOYER_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

PROJECT_ROLES=(
  "roles/cloudfunctions.developer"
  "roles/storage.admin"
  "roles/iam.serviceAccountAdmin"
  "roles/iam.serviceAccountTokenCreator"
  "roles/iam.serviceAccountUser"
)

# === Service Account ===
echo "🔍 Checking if service account ${DEPLOYER_SA_NAME} exists..."
if ! gcloud iam service-accounts describe "$DEPLOYER_SA" --project="$PROJECT_ID" &>/dev/null; then
  echo "➕ Creating service account: ${DEPLOYER_SA_NAME}"
  gcloud iam service-accounts create "$DEPLOYER_SA_NAME" \
    --project="$PROJECT_ID" \
    --display-name="GBFS Terraform Deployer"
else
  echo "✅ Service account already exists: ${DEPLOYER_SA_NAME}"
fi

# === IAM Roles ===
for ROLE in "${PROJECT_ROLES[@]}"; do
  echo "🔐 Ensuring role $ROLE is granted to $DEPLOYER_SA"
  if ! gcloud projects get-iam-policy "$PROJECT_ID" \
    --flatten="bindings[].members" \
    --filter="bindings.role=$ROLE AND bindings.members=serviceAccount:$DEPLOYER_SA" \
    --format='value(bindings.members)' | grep -q .; then

    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
      --member="serviceAccount:$DEPLOYER_SA" \
      --role="$ROLE"
  else
    echo "✅ Role $ROLE already granted"
  fi
done

# === Impersonation for local user ===
echo "👤 Allowing local user $LOCAL_USER_EMAIL to impersonate $DEPLOYER_SA"
gcloud iam service-accounts add-iam-policy-binding "$DEPLOYER_SA" \
  --project="$PROJECT_ID" \
  --member="user:${LOCAL_USER_EMAIL}" \
  --role="roles/iam.serviceAccountTokenCreator" || echo "⚠️ Already allowed or failed"

# === Allow deployer to impersonate the validator service account ===
# Note: gbfs-validator-service-account is created by Terraform on first deploy.
# This binding is applied only if that SA already exists.
VALIDATOR_SA="gbfs-validator-service-account@${PROJECT_ID}.iam.gserviceaccount.com"
if gcloud iam service-accounts describe "$VALIDATOR_SA" --project="$PROJECT_ID" &>/dev/null; then
  echo "🔐 Granting 'iam.serviceAccountUser' to $DEPLOYER_SA on $VALIDATOR_SA"
  gcloud iam service-accounts add-iam-policy-binding "$VALIDATOR_SA" \
    --member="serviceAccount:${DEPLOYER_SA}" \
    --role="roles/iam.serviceAccountUser" \
    --project="$PROJECT_ID"
else
  echo "⚠️  $VALIDATOR_SA does not exist yet — Terraform will create it on first deploy."
  echo "    Re-run this script after the first successful deployment to apply this binding."
fi

# === Enable Artifact Registry API ===
echo "🛰️  Enabling Artifact Registry API..."
if ! gcloud services list --project="$PROJECT_ID" --enabled \
  --filter="config.name:artifactregistry.googleapis.com" \
  --format="value(config.name)" | grep -q artifactregistry.googleapis.com; then

  gcloud services enable artifactregistry.googleapis.com \
    --project="$PROJECT_ID"
  echo "✅ Artifact Registry API enabled"
else
  echo "✅ Artifact Registry API already enabled"
fi

# === Create Artifact Registry repository ===
echo "📦 Checking if repository '$REPO_NAME' exists..."
if ! gcloud artifacts repositories describe "$REPO_NAME" \
  --project="$PROJECT_ID" \
  --location="$REGION" &>/dev/null; then
  echo "➕ Creating Artifact Registry repository: $REPO_NAME in $REGION"
  gcloud artifacts repositories create "$REPO_NAME" \
    --repository-format=docker \
    --location="$REGION" \
    --project="$PROJECT_ID" \
    --description="GBFS Validator container images"

else
  echo "✅ Artifact Registry '$REPO_NAME' already exists"
fi

# === Create cleanup policy: keep only latest 5 tagged images ===
POLICY_NAME="keep-latest-5"
POLICY_FILE="/tmp/cleanup-policy-${REPO_NAME}.json"

echo "🧹 Checking if cleanup policy '$POLICY_NAME' exists..."
if ! gcloud artifacts repositories list-cleanup-policies "$REPO_NAME" \
  --location="$REGION" \
  --project="$PROJECT_ID" \
  --format="value(id)" | grep -q "$POLICY_NAME"; then

  echo "➕ Creating cleanup policy '$POLICY_NAME' (keep only 5 tagged images)"
cat > "$POLICY_FILE" <<EOF
[
  {
    "name": "keep-latest-5",
    "action": {
      "type": "KEEP"
    },
    "mostRecentVersions": {
      "keepCount": 5
    }
  },
  {
    "name": "delete-untagged-older-than-30-days",
    "action": {
      "type": "DELETE"
    },
    "condition": {
      "olderThan": "2592000s",
      "tagState": "ANY"
    }
  }
]
EOF


  gcloud artifacts repositories set-cleanup-policies "$REPO_NAME" \
    --location="$REGION" \
    --project="$PROJECT_ID" \
    --policy="$POLICY_FILE"

  echo "✅ Cleanup policy '$POLICY_NAME' applied"
else
  echo "✅ Cleanup policy '$POLICY_NAME' already exists"
fi

# === Enable Required Google APIs ===
REQUIRED_SERVICES=(
  artifactregistry.googleapis.com
  cloudfunctions.googleapis.com
  cloudbuild.googleapis.com
  run.googleapis.com
  cloudresourcemanager.googleapis.com
)

echo "🛰️  Enabling required Google APIs..."
for SERVICE in "${REQUIRED_SERVICES[@]}"; do
  echo "🔍 Checking if $SERVICE is enabled..."
  if ! gcloud services list --project="$PROJECT_ID" --enabled \
    --filter="config.name:$SERVICE" \
    --format="value(config.name)" | grep -q "$SERVICE"; then

    echo "➕ Enabling $SERVICE..."
    gcloud services enable "$SERVICE" --project="$PROJECT_ID"
    echo "✅ $SERVICE enabled"
  else
    echo "✅ $SERVICE already enabled"
  fi
done

echo "🎉 Setup complete for project $PROJECT_ID"

# === Next steps ===
if [[ "${ENVIRONMENT}" == "prod" ]]; then
  DOMAIN="gbfs.api.mobilitydatabase.org"
else
  DOMAIN="${ENVIRONMENT}.gbfs.api.mobilitydatabase.org"
fi

echo ""
echo "=========================================="
echo "  Bootstrap complete for: ${ENVIRONMENT}"
echo ""
echo "  Public traffic for ${DOMAIN} goes through the Cloudflare Worker"
echo "  (mobilitydata-sites in MobilityData/org-cloudflare-workers), not a GCP load balancer."
echo "  After the first Terraform deploy, follow docs/edge-cutover.md to connect it."
echo "=========================================="
