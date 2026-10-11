#!/bin/bash
# Prints the pinned image of a CI tool, from ci/Dockerfile.
#
# Usage: .github/scripts/tool-image.sh trivy

set -euo pipefail

tool="${1:?tool}"
image="$(sed -n "s/^FROM \([^ ]*\) AS ${tool}\$/\1/p" "$(dirname "$0")/../../ci/Dockerfile")"
[ -n "${image}" ] || { echo "unknown tool: ${tool}" >&2; exit 1; }
echo "${image}"
