#!/bin/bash

set -euo pipefail

SCRIPT_PATH="$(dirname -- "${BASH_SOURCE[0]}")"
# Build the Docker image
docker build -t gbfs-validator-api $SCRIPT_PATH/../gbfs-validator/.

# Run the Docker container, mapping port 8080
docker run -d -p 8080:8080 --name gbfs-validator-api gbfs-validator-api

echo "Container started. Access the API at http://localhost:8080/"