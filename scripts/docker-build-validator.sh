#!/bin/bash

#
# MobilityData 2025 - GBFS Validator Container Builder
#

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
IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME_PREFIX}-${ENVIRONMENT}/${SERVICE}:${VERSION}"
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
