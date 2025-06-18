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

# -----------------------------------------------------------------------------
# scripts/docker-build-start.sh
#
# Purpose:
#   Automates Docker image build and container startup for gbfs-validator-api.
#
# What it does:
#   - Builds the Docker image from the gbfs-validator directory.
#   - Tags the image as gbfs-validator-api.
#   - Runs the container in detached mode, mapping port 8080 to the host.
#   - Prints the URL to access the running API.
#
# Usage:
#   ./scripts/docker-build-start.sh
#
# Requirements:
#   - Docker installed and running
#   - gbfs-validator directory present relative to this script
#
# Notes:
#   - Will stop on any error (set -euo pipefail).
#   - The container is named gbfs-validator-api.
#   - To stop/remove: docker stop gbfs-validator-api && docker rm gbfs-validator-api
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_PATH="$(dirname -- "${BASH_SOURCE[0]}")"
# Build the Docker image
docker build -t gbfs-validator-api $SCRIPT_PATH/../gbfs-validator/.

# Run the Docker container, mapping port 8080
docker run -d -p 8080:8080 --name gbfs-validator-api gbfs-validator-api

echo "Container started. Access the API at http://localhost:8080/"