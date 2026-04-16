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
# Download gbfs-validator-java-api fat JAR using Maven dependency:copy.
#
# Uses the pom.xml in gbfs-validator/ which declares the Maven Central and
# Maven Central Snapshots repositories. Maven handles version resolution,
# checksum verification, and snapshot timestamp mapping natively.
#
# USAGE:
#   ./download-validator-jar.sh [-version <VERSION>]
#
# OPTIONS:
#   -version <VERSION>  Version to download (e.g. 2.0.68 or 2.0.68-SNAPSHOT).
#                        Omit for latest release (RELEASE).
#   -h | --help         Show this help message
#
# EXAMPLES:
#   Download latest release:
#     ./download-validator-jar.sh
#
#   Download specific release:
#     ./download-validator-jar.sh -version 2.0.68
#
#   Download snapshot:
#     ./download-validator-jar.sh -version 2.0.68-SNAPSHOT
#
###############################################################################

set -euo pipefail

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POM_PATH="${SCRIPT_PATH}/../gbfs-validator/pom.xml"
OUTPUT_DIR="${SCRIPT_PATH}/../gbfs-validator"
VERSION=""

display_usage() {
  echo "Usage: $0 [-version <VERSION>]"
  echo "Options:"
  echo "  -version <VERSION>  Specific version (omit for latest release)"
  echo "  -h|--help           Show this help"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -version) VERSION="$2"; shift 2 ;;
    -h|--help) display_usage ;;
    *) echo "Unknown option: $1"; display_usage ;;
  esac
done

# Use RELEASE keyword if no version specified (Maven resolves to latest release)
RESOLVED_VERSION="${VERSION:-RELEASE}"

echo "⬇️  Downloading gbfs-validator-java-api ${RESOLVED_VERSION} via Maven..."

mvn -f "$POM_PATH" dependency:copy \
  -Dartifact.version="$RESOLVED_VERSION" \
  -Doutput.directory="$OUTPUT_DIR" \
  -B -ntp \
  || { echo "❌ Maven download failed for version ${RESOLVED_VERSION}"; exit 1; }

JAR_FILE="${OUTPUT_DIR}/gbfs-validator-java-api.jar"
if [[ ! -f "$JAR_FILE" ]]; then
  echo "❌ Expected JAR not found at ${JAR_FILE}"
  exit 1
fi

FILE_SIZE=$(wc -c < "$JAR_FILE" | tr -d ' ')
echo "✅ Downloaded gbfs-validator-java-api ${RESOLVED_VERSION} (${FILE_SIZE} bytes) → ${JAR_FILE}"

# Emit resolved version for CI to capture.
# For RELEASE, extract the actual version Maven downloaded.
if [[ "$RESOLVED_VERSION" == "RELEASE" ]]; then
  # Maven copies with stripVersion=true, so we parse the download log isn't reliable.
  # Instead, query what Maven actually resolved.
  ACTUAL_VERSION=$(mvn -f "$POM_PATH" dependency:copy \
    -Dartifact.version="RELEASE" \
    -Doutput.directory=/dev/null \
    -Dmdep.stripVersion=false \
    -B -ntp -q 2>&1 | grep -oP 'gbfs-validator-java-api-\K[0-9][^.]*\.[^.]*\.[^"]*(?=\.jar)' || echo "unknown")
  echo "RESOLVED_VERSION=${ACTUAL_VERSION}"
else
  echo "RESOLVED_VERSION=${RESOLVED_VERSION}"
fi
