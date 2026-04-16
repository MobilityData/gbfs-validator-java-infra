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
# Download gbfs-validator-java-api fat JAR from Maven Central or Maven
# Central Snapshots.
#
# If a version is specified:
#   - SNAPSHOT versions (e.g. 2.0.68-SNAPSHOT) are downloaded from the
#     Maven Central Snapshots repository, resolving the timestamped JAR
#     automatically via maven-metadata.xml.
#   - Release versions are downloaded from Maven Central.
#
# If no version is specified, the latest release is resolved from Maven
# Central. Snapshots are never resolved automatically.
#
# USAGE:
#   ./download-validator-jar.sh [-version <VERSION>] [-output <PATH>]
#
# OPTIONS:
#   -version <VERSION>  Specific version to download (e.g. 2.0.68 or 2.0.68-SNAPSHOT)
#   -output <PATH>      Output file path. Default: gbfs-validator/gbfs-validator-java-api.jar
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

GROUP_ID="org.mobilitydata"
ARTIFACT_ID="gbfs-validator-java-api"
MAVEN_SEARCH_URL="https://search.maven.org/solrsearch/select"
MAVEN_RELEASE_URL="https://repo1.maven.org/maven2"
MAVEN_SNAPSHOT_URL="https://central.sonatype.com/repository/maven-snapshots"

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="${SCRIPT_PATH}/../gbfs-validator/gbfs-validator-java-api.jar"
VERSION=""

display_usage() {
  echo "Usage: $0 [-version <VERSION>] [-output <PATH>]"
  echo "Options:"
  echo "  -version <VERSION>  Specific version (omit for latest release)"
  echo "  -output <PATH>      Output path (default: gbfs-validator/gbfs-validator-java-api.jar)"
  echo "  -h|--help           Show this help"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -version) VERSION="$2"; shift 2 ;;
    -output)  OUTPUT="$2"; shift 2 ;;
    -h|--help) display_usage ;;
    *) echo "Unknown option: $1"; display_usage ;;
  esac
done

GROUP_PATH="${GROUP_ID//\.//}"

# Resolve latest version from Maven Central if not specified
if [[ -z "$VERSION" ]]; then
  echo "🔍 Resolving latest version of ${GROUP_ID}:${ARTIFACT_ID} from Maven Central..."
  VERSION=$(curl -sf "${MAVEN_SEARCH_URL}?q=g:${GROUP_ID}+AND+a:${ARTIFACT_ID}&rows=1&wt=json" \
    | python3 -c "import sys,json; docs=json.load(sys.stdin)['response']['docs']; print(docs[0]['latestVersion']) if docs else sys.exit(1)") \
    || { echo "❌ Could not resolve latest version. Artifact ${GROUP_ID}:${ARTIFACT_ID} not found on Maven Central."; exit 1; }
  echo "   Latest version: ${VERSION}"
fi

# Build download URL depending on whether it's a snapshot or release
if [[ "$VERSION" == *"-SNAPSHOT"* ]]; then
  echo "📦 Snapshot version detected — resolving from Maven Central Snapshots..."
  METADATA_URL="${MAVEN_SNAPSHOT_URL}/${GROUP_PATH}/${ARTIFACT_ID}/${VERSION}/maven-metadata.xml"
  METADATA=$(curl -sf "$METADATA_URL") \
    || { echo "❌ Snapshot metadata not found at ${METADATA_URL}"; exit 1; }

  # Extract the latest timestamped snapshot JAR filename from maven-metadata.xml
  TIMESTAMP=$(echo "$METADATA" | python3 -c "
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.stdin).getroot()
sv = root.find('.//snapshotVersion[extension=\"jar\"]')
if sv is None:
    sys.exit(1)
print(sv.find('value').text)
") || { echo "❌ Could not parse snapshot metadata for JAR"; exit 1; }

  JAR_URL="${MAVEN_SNAPSHOT_URL}/${GROUP_PATH}/${ARTIFACT_ID}/${VERSION}/${ARTIFACT_ID}-${TIMESTAMP}.jar"
else
  JAR_URL="${MAVEN_RELEASE_URL}/${GROUP_PATH}/${ARTIFACT_ID}/${VERSION}/${ARTIFACT_ID}-${VERSION}.jar"
fi

echo "⬇️  Downloading ${ARTIFACT_ID} ${VERSION} ..."
echo "   URL: ${JAR_URL}"

HTTP_CODE=$(curl -sL -w "%{http_code}" -o "$OUTPUT" "$JAR_URL")

if [[ "$HTTP_CODE" != "200" ]]; then
  rm -f "$OUTPUT"
  echo "❌ Download failed (HTTP ${HTTP_CODE}). Version ${VERSION} not found."
  if [[ "$VERSION" == *"-SNAPSHOT"* ]]; then
    echo "   Check snapshots: ${MAVEN_SNAPSHOT_URL}/${GROUP_PATH}/${ARTIFACT_ID}/"
  else
    echo "   Check releases: https://search.maven.org/artifact/${GROUP_ID}/${ARTIFACT_ID}"
  fi
  exit 1
fi

FILE_SIZE=$(wc -c < "$OUTPUT" | tr -d ' ')
echo "✅ Downloaded ${ARTIFACT_ID} ${VERSION} (${FILE_SIZE} bytes) → ${OUTPUT}"

# Write resolved version so callers can capture it
echo "RESOLVED_VERSION=${VERSION}"
