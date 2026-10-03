#!/bin/bash
# Prints the docker build arguments for one branch of versions.json, in the
# multi-line "args<<EOF" format expected by $GITHUB_OUTPUT.
#
# Usage: .github/scripts/build-args.sh 5.2

set -euo pipefail

branch="${1:?branch}"
v=versions.json
jq -e --arg b "${branch}" '.branches[$b]' "${v}" > /dev/null || { echo "unknown branch ${branch}" >&2; exit 1; }

echo 'args<<EOF'
jq -r --arg b "${branch}" '
  "PHP_VERSION=\(.branches[$b].php)",
  "MOODLE_VERSION=\(.branches[$b].moodle)",
  "MOODLE_SHA256=\(.branches[$b].sha256)",
  "ACCESS_VERSION=\(.access.version)",
  "ACCESS_SHA256=\(.access.sha256)"' "${v}"
echo 'EOF'
echo "moodle=$(jq -r --arg b "${branch}" '.branches[$b].moodle' "${v}")"
