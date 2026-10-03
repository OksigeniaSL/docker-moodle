#!/bin/bash
# Computes the tags for one branch, in $GITHUB_OUTPUT format:
#   immutable=5.2.3-r4
#   tags=5.2.3-r4 5.2.3 5.2 5 latest
#
# 5.2.3-rN never moves: N grows with every rebuild of the same Moodle
# version, read from the tags already in GHCR. The others move to the
# newest build. "5" goes to the newest branch of each major version,
# "latest" to versions.json .latest and "lts" to versions.json .lts.
#
# Usage: .github/scripts/tags.sh 5.2   (GH_TOKEN must allow reading packages)

set -euo pipefail

branch="${1:?branch}"
v=versions.json
moodle="$(jq -r --arg b "${branch}" '.branches[$b].moodle' "${v}")"
major="${branch%%.*}"

# Highest existing revision of this Moodle version.
last=0
existing="$(gh api --paginate "/orgs/OksigeniaSL/packages/container/moodle/versions" \
    --jq '.[].metadata.container.tags[]' 2>/dev/null || true)"
while read -r tag; do
    case "${tag}" in
        "${moodle}"-r*)
            n="${tag##*-r}"
            [[ "${n}" =~ ^[0-9]+$ ]] && [ "${n}" -gt "${last}" ] && last="${n}"
            ;;
    esac
done <<< "${existing}"
immutable="${moodle}-r$((last + 1))"

tags=("${immutable}" "${moodle}" "${branch}")
newest_of_major="$(jq -r --arg m "${major}" '[.branches | keys[] | select(startswith($m + "."))] | sort_by(split(".") | map(tonumber)) | last' "${v}")"
[ "${branch}" = "${newest_of_major}" ] && tags+=("${major}")
[ "${branch}" = "$(jq -r '.latest' "${v}")" ] && tags+=(latest)
# "lts" is set explicitly in versions.json, so it never jumps to another
# major version just because a branch was added or removed.
[ "${branch}" = "$(jq -r '.lts // empty' "${v}")" ] && tags+=(lts)

echo "immutable=${immutable}"
echo "tags=${tags[*]}"
