#!/bin/bash
# Looks for new Moodle point releases on the branches in versions.json and
# for a new Oksigenia Access release, and updates versions.json with the
# version and the SHA-256 published by Moodle (checked against our own
# download). Prints, in $GITHUB_OUTPUT format:
#   changed=yes|no
#   summary=Moodle 5.2.4, 4.5.15
#   newbranch=5.3        (a new stable branch exists that is not in versions.json)

set -euo pipefail

v=versions.json
changes=()
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

sha256_of() { curl -fsSL --retry 3 "$1" | sha256sum | cut -d' ' -f1; }

moodle_tags="$(git ls-remote --tags --refs https://github.com/moodle/moodle.git 'v*' \
    | sed -n 's#.*refs/tags/v\([0-9]*\.[0-9]*\.[0-9]*\)$#\1#p' | sort -V)"

for branch in $(jq -r '.branches | keys[]' "${v}"); do
    current="$(jq -r --arg b "${branch}" '.branches[$b].moodle' "${v}")"
    latest="$(grep -E "^${branch//./\\.}\.[0-9]+$" <<< "${moodle_tags}" | tail -1 || true)"
    [ -n "${latest}" ] || continue
    [ "$(printf '%s\n%s\n' "${current}" "${latest}" | sort -V | tail -1)" = "${current}" ] && continue

    major="${branch%%.*}"; minor="${branch#*.}"
    url="https://download.moodle.org/download.php/direct/stable${major}$(printf '%02d' "${minor}")/moodle-${latest}.tgz"
    published="$(curl -fsSL "${url}.sha256" 2>/dev/null | awk '{print $NF}' || true)"
    if [ -z "${published}" ]; then
        echo "Moodle ${latest} is tagged but not packaged yet; trying again later" >&2
        continue
    fi
    actual="$(sha256_of "${url}")"
    if [ "${published}" != "${actual}" ]; then
        echo "Moodle ${latest}: published SHA-256 ${published} does not match the download ${actual}" >&2
        exit 1
    fi
    jq --arg b "${branch}" --arg m "${latest}" --arg s "${actual}" \
        '.branches[$b].moodle = $m | .branches[$b].sha256 = $s' "${v}" > "${tmp}/v.json"
    mv "${tmp}/v.json" "${v}"
    changes+=("Moodle ${latest}")
done

# Oksigenia Access: newest vX.Y.Z tag.
access_current="$(jq -r '.access.version' "${v}")"
access_latest="$(git ls-remote --tags --refs https://github.com/OksigeniaSL/moodle-local_oksigeniaaccess.git 'v*' \
    | sed -n 's#.*refs/tags/v\([0-9]*\.[0-9]*\.[0-9]*\)$#\1#p' | sort -V | tail -1)"
if [ -n "${access_latest}" ] && [ "${access_latest}" != "${access_current}" ] \
    && [ "$(printf '%s\n%s\n' "${access_current}" "${access_latest}" | sort -V | tail -1)" = "${access_latest}" ]; then
    sha="$(sha256_of "https://github.com/OksigeniaSL/moodle-local_oksigeniaaccess/archive/refs/tags/v${access_latest}.tar.gz")"
    jq --arg a "${access_latest}" --arg s "${sha}" '.access.version = $a | .access.sha256 = $s' "${v}" > "${tmp}/v.json"
    mv "${tmp}/v.json" "${v}"
    changes+=("Oksigenia Access ${access_latest}")
fi

# A new stable branch (X.Y.0 released) newer than every branch we ship.
newest="$(jq -r '.branches | keys | sort_by(split(".") | map(tonumber)) | last' "${v}")"
newbranch=""
while read -r tag; do
    b="${tag%.0}"
    if [ "$(printf '%s\n%s\n' "${newest}" "${b}" | sort -V | tail -1)" = "${b}" ] && [ "${b}" != "${newest}" ]; then
        newbranch="${b}"
    fi
done < <(grep -E '^[0-9]+\.[0-9]+\.0$' <<< "${moodle_tags}")

if [ "${#changes[@]}" -gt 0 ]; then
    echo "changed=yes"
    (IFS=,; echo "summary=${changes[*]}" | sed 's/,/, /g')
else
    echo "changed=no"
fi
echo "newbranch=${newbranch}"
