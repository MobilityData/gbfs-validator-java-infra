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
# GBFS Validator Container Builder Script
# MobilityData 2025
#
# This script automates building, testing, running, and pushing the Docker image
# for the GBFS Validator API. It is intended for use in local development,
# testing, and CI/CD pipelines targeting Artifact Registry on Google Cloud.
#
# USAGE:
#   ./docker-build-validator.sh [options]
#
# OPTIONS:

#   -project_id <PROJECT_ID>      GCP project ID (default: gbfs-validator-staging)
#   -region <REGION>              GCP region (default: northamerica-northeast1)
#   -repo_name <REPO_NAME>        Artifact Registry Docker repo name (default: gbfs-validator)
#   -environment <ENVIRONMENT>    Deployment environment (default: dev)
#   -service <SERVICE>            Service name (default: gbfs_validator_api)
#   -version <VERSION>            Image version tag (default: latest)
#   --test                        Build and run the container locally
#   --push                        Push the container to Artifact Registry
#   --run                         Run the local image (no rebuild, no push)
#   -h | --help                   Show this help message
#
# EXAMPLES:
#   Build only (no push/run):
#     ./docker-build-validator.sh
#
#   Build and run locally for testing:
#     ./docker-build-validator.sh --test
#
#   Build and push to GCP Artifact Registry:
#     ./docker-build-validator.sh --push -project_id my-project -region us-central1
#
#   Run previously built local image:
#     ./docker-build-validator.sh --run
#
###############################################################################

set -euo pipefail

# === Default values ===
PROJECT_ID="gbfs-validator-staging"
ENVIRONMENT="dev"
SERVICE="gbfs_validator_api"
REGION="northamerica-northeast1"
VERSION="latest"
REPO_NAME_PREFIX="gbfs-validator"
TEST_MODE="false"
RUN_MODE="false"
PUSH_MODE="false"
PORT=8080

# === Help ===
display_usage() {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  -project_id <PROJECT_ID>      GCP project ID (default: $PROJECT_ID)"
  echo "  -region <REGION>              GCP region (default: $REGION)"
  echo "  -repo_name <REPO_NAME>        Artifact Registry Docker repo name (default: $REPO_NAME_PREFIX)"
  echo "  -environment <ENVIRONMENT>    Deployment environment (default: $ENVIRONMENT)"
  echo "  -service <SERVICE>            Service name (default: $SERVICE)"
  echo "  -version <VERSION>            Image version tag (default: $VERSION)"
  echo "  --test                        Build and run the container locally"
  echo "  --push                        Push the container to Artifact Registry"
  echo "  --run                         Run the local image (no rebuild, no push)"
  echo "  -h|--help                     Show this help message"
  exit 1
}

# === Parse args ===
while [[ $# -gt 0 ]]; do
  case "$1" in
    -project_id) PROJECT_ID="$2"; shift 2 ;;
    -service) SERVICE="$2"; shift 2 ;;
    -repo_name) REPO_NAME_PREFIX="$2"; shift 2 ;;
    # CI/CD: -environment is used as a subdirectory within the shared Artifact Registry repo
    # (e.g. gbfs-validator-staging/dev/). Must match the environment Terraform will deploy to,
    # otherwise the image ref in Cloud Run won't resolve.
    -environment) ENVIRONMENT="$2"; shift 2 ;;
    -region) REGION="$2"; shift 2 ;;
    -version) VERSION="$2"; shift 2 ;;
    --test) TEST_MODE="true"; shift ;;
    --push) PUSH_MODE="true"; shift ;;
    --run) RUN_MODE="true"; shift ;;
    -h|--help) display_usage ;;
    *) echo "Unknown option: $1"; display_usage ;;
  esac
done

# === Derived values ===
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JAR_PATH="$SCRIPT_PATH/../gbfs-validator/gbfs-validator-java-api.jar"
DOCKERFILE="$SCRIPT_PATH/../gbfs-validator/Dockerfile"
IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME_PREFIX}/${ENVIRONMENT}/${SERVICE}:${VERSION}"
LOCAL_TAG="${SERVICE}:local"

# === Validation ===
[[ -f "$JAR_PATH" ]] || { echo "❌ Fat JAR not found: $JAR_PATH"; exit 1; }
[[ -f "$DOCKERFILE" ]] || { echo "❌ Dockerfile not found: $DOCKERFILE"; exit 1; }

# === Always build ===
echo "🚧 Building Docker image with tags:"
echo "  - Remote: $IMAGE"
echo "  - Local : $LOCAL_TAG"

if [[ "$PUSH_MODE" == "true" ]]; then
  docker buildx build \
    --platform linux/amd64 \
    --no-cache \
    --push \
    -t "$IMAGE" \
    "$SCRIPT_PATH/../gbfs-validator"
else
  docker buildx build \
    --platform linux/amd64 \
    --no-cache \
    --load \
    -t "$IMAGE" \
    -t "$LOCAL_TAG" \
    "$SCRIPT_PATH/../gbfs-validator"
fi

# === Run-only mode ===
if [[ "$RUN_MODE" == "true" ]]; then
  echo "🚀 Running previously built local image: $LOCAL_TAG on http://localhost:$PORT ..."
  docker run --rm -e PORT=$PORT -p "$PORT:$PORT" "$LOCAL_TAG"
  exit 0
fi

echo "✅ Image built successfully and available locally"

# === Optional test ===
if [[ "$TEST_MODE" == "true" ]]; then
  echo "🧪 Running local container ($LOCAL_TAG) on http://localhost:$PORT ..."
  docker run --rm -e PORT=$PORT -p "$PORT:$PORT" "$LOCAL_TAG"
fi
