#!/bin/bash
# Looks for new Moodle point releases on the branches in versions.json and
# for a new Oksigenia Access release and for new PHP releases in the base
# images (and, weekly, for any new build of them), and updates versions.json with the
# version and the SHA-256: for Moodle, the one Moodle publishes (checked
# against our own download); for Access, that of the tag's archive. Prints, in $GITHUB_OUTPUT format:
#   changed=yes|no
#   summary=Moodle 5.2.4, 4.5.15
#   newbranch=5.3        (a new stable branch exists that is not in versions.json)

set -euo pipefail

v=versions.json
changes=()
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

sha256_of() { curl -fsSL --retry 3 "$1" | sha256sum | cut -d' ' -f1; }

# Download URL of a release. The first release of a branch is packaged
# without ".0": Moodle 5.3.0 is moodle-5.3.tgz.
package_url() {
    local version="$1" major rest minor file
    major="${version%%.*}"; rest="${version#*.}"; minor="${rest%%.*}"
    file="moodle-${version}"
    [[ "${version}" =~ ^[0-9]+\.[0-9]+\.0$ ]] && file="moodle-${version%.0}"
    echo "https://download.moodle.org/download.php/direct/stable${major}$(printf '%02d' "${minor}")/${file}.tgz"
}

# Moodle uploads packages a few days before it announces a release, and can
# still withdraw them. Only versions listed on the public download pages
# count as released.
announced="$(for page in latest supported security; do
    curl -fsSL --retry 3 -A "Mozilla/5.0" "https://download.moodle.org/releases/${page}/" || true
done | grep -oE 'moodle-[0-9]+\.[0-9]+(\.[0-9]+)?\.tgz' \
    | sed -E 's/^moodle-//; s/\.tgz$//; s/^([0-9]+\.[0-9]+)$/\1.0/' | sort -uV)"
is_announced() { grep -qxF "$1" <<< "${announced}"; }

moodle_tags="$(git ls-remote --tags --refs https://github.com/moodle/moodle.git 'v*' \
    | sed -n 's#.*refs/tags/v\([0-9]*\.[0-9]*\.[0-9]*\)$#\1#p' | sort -V)"

# A branch marked "pending" is published as soon as Moodle publishes its
# package (Moodle tags a release in git a few days before it ships it).
for branch in $(jq -r '.branches | to_entries[] | select(.value.pending == true) | .key' "${v}"); do
    version="$(jq -r --arg b "${branch}" '.branches[$b].moodle' "${v}")"
    if ! is_announced "${version}"; then
        echo "Moodle ${version} is not announced yet; trying again later" >&2
        continue
    fi
    url="$(package_url "${version}")"
    published="$(curl -fsSL "${url}.sha256" 2>/dev/null | awk '{print $NF}' || true)"
    if ! [[ "${published}" =~ ^[0-9a-f]{64}$ ]]; then
        echo "Moodle ${version} is not packaged yet; trying again later" >&2
        continue
    fi
    actual="$(sha256_of "${url}")"
    if [ "${published}" != "${actual}" ]; then
        echo "Moodle ${version}: published SHA-256 ${published} does not match the download ${actual}" >&2
        exit 1
    fi
    jq --arg b "${branch}" --arg s "${actual}" '
        (if .branches[$b].promote_latest then .latest = $b else . end)
        | .branches[$b].sha256 = $s
        | .branches[$b] |= del(.pending, .promote_latest)' "${v}" > "${tmp}/v.json"
    mv "${tmp}/v.json" "${v}"
    changes+=("Moodle ${version} (new branch ${branch})")
done

for branch in $(jq -r '.branches | to_entries[] | select(.value.pending != true) | .key' "${v}"); do
    current="$(jq -r --arg b "${branch}" '.branches[$b].moodle' "${v}")"
    latest="$(grep -E "^${branch//./\\.}\.[0-9]+$" <<< "${moodle_tags}" | tail -1 || true)"
    [ -n "${latest}" ] || continue
    [ "$(printf '%s\n%s\n' "${current}" "${latest}" | sort -V | tail -1)" = "${current}" ] && continue
    if ! is_announced "${latest}"; then
        echo "Moodle ${latest} is tagged but not announced yet; trying again later" >&2
        continue
    fi

    url="$(package_url "${latest}")"
    published="$(curl -fsSL "${url}.sha256" 2>/dev/null | awk '{print $NF}' || true)"
    if ! [[ "${published}" =~ ^[0-9a-f]{64}$ ]]; then
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

# PHP base images, pinned by digest in php_images. A new PHP release (a new
# PHP_VERSION in the official image) is picked up the day the image carries
# it, as security fixes come that way. Other rebuilds of the same PHP, for
# Debian's fixes, are picked up once a week (Mondays, UTC), or on request
# (BASE_UPDATE=yes).
php_version_of() { # php_version_of <digest>: PHP_VERSION of its amd64 image
    local m c
    m="$(curl -fsSL -H "Authorization: Bearer ${token}" \
        -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' \
        "https://registry-1.docker.io/v2/library/php/manifests/$1" \
        | jq -r '[.manifests[] | select(.platform.os == "linux" and .platform.architecture == "amd64")][0].digest // empty')" || return 1
    [ -n "${m}" ] || return 1
    c="$(curl -fsSL -H "Authorization: Bearer ${token}" \
        -H 'Accept: application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' \
        "https://registry-1.docker.io/v2/library/php/manifests/${m}" | jq -r .config.digest)" || return 1
    curl -fsSL -H "Authorization: Bearer ${token}" "https://registry-1.docker.io/v2/library/php/blobs/${c}" \
        | jq -er '.config.Env[] | select(startswith("PHP_VERSION=")) | sub("PHP_VERSION="; "")'
}
weekly=no
if [ "$(date -u +%u)" = 1 ] || [ "${BASE_UPDATE:-no}" = yes ]; then weekly=yes; fi
token="$(curl -fsSL "https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/php:pull" | jq -r .token)"
for php in $(jq -r '[.branches[].php] | unique | .[]' "${v}"); do
    current="$(jq -r --arg p "${php}" '.php_images[$p] // empty' "${v}")"
    latest="$(curl -fsSI -H "Authorization: Bearer ${token}" \
        -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' \
        "https://registry-1.docker.io/v2/library/php/manifests/${php}-apache-trixie" \
        | tr -d '\r' | awk -F': ' 'tolower($1) == "docker-content-digest" { print $2 }')" || latest=""
    if ! [[ "${latest}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
        echo "cannot read the digest of php:${php}-apache-trixie; trying again later" >&2
        continue
    fi
    [ "${latest}" = "${current}" ] && continue
    if [ "${weekly}" = no ]; then
        # Between Mondays, only a new PHP release moves the pin.
        now="$(php_version_of "${current}")" || now=""
        new="$(php_version_of "${latest}")" || new=""
        if [ -z "${new}" ] || [ "${new}" = "${now}" ] \
            || [ "$(printf '%s\n%s\n' "${now}" "${new}" | sort -V | tail -1)" != "${new}" ]; then
            continue
        fi
        changes+=("PHP ${new}")
    else
        changes+=("PHP ${php} base image")
    fi
    jq --arg p "${php}" --arg d "${latest}" '.php_images[$p] = $d' "${v}" > "${tmp}/v.json"
    mv "${tmp}/v.json" "${v}"
done

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
