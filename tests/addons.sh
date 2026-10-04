#!/bin/bash
# Which plugins addons.php carries over to a new Moodle tree, on small
# synthetic trees. Runs inside the image: tests/run.sh addons.

# shellcheck disable=SC2016 # PHP code in single quotes, written as is
set -euo pipefail

ADDONS=/usr/local/lib/oksigenia-moodle/php/addons.php
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
failed=0

plugin() { mkdir -p "$1"; printf '<?php\n$plugin->version = %s;\n' "$2" > "$1/version.php"; }

# New tree, laid out like Moodle 5.1+: Chat and Survey removed from core.
new="${work}/new"
mkdir -p "${new}/lib" "${new}/public"
echo '{"plugintypes": {"mod": "public/mod", "local": "public/local"}}' > "${new}/lib/components.json"
echo '{"standard": {"mod": ["forum"]}, "deleted": {"mod": ["chat", "survey"]}}' > "${new}/lib/plugins.json"
printf '<?php\n$version = 2026042003.00;\n' > "${new}/public/version.php"
plugin "${new}/public/mod/forum" 2026042000

check() {
    local name="$1" old="$2" want_out="$3" want_err="$4" out err
    out="$(php "${ADDONS}" "${old}" "${new}" 2>"${work}/err" | cut -f1 | sort | tr '\n' ' ')"
    err="$(sort "${work}/err" | tr '\n' ' ')"
    if [ "${out}" = "${want_out}" ] && [ "${err}" = "${want_err}" ]; then
        echo "ok: ${name}"
    else
        echo "FAIL: ${name}: carried [${out}] (want [${want_out}]), removed [${err}] (want [${want_err}])"
        failed=1
    fi
}

# Moodle 4.5 tree: core Chat is left behind, a separate Survey release
# (newer than that core) is carried over, like any other add-on.
old="${work}/old45"
mkdir -p "${old}/lib"
echo '{"standard": {"mod": ["forum", "chat", "survey"]}}' > "${old}/lib/plugins.json"
printf '<?php\n$version = 2024100714.00;\n' > "${old}/version.php"
plugin "${old}/mod/forum" 2024100700
plugin "${old}/mod/chat" 2024100700
plugin "${old}/mod/survey" 2024110500
plugin "${old}/local/extra" 2025010100
check "4.5 tree: core module removed, separate release kept" "${old}" "local_extra mod_survey " "mod_chat "

# Moodle 5.2 tree with the separate releases installed: that Moodle did not
# ship them, so they are add-ons.
old="${work}/old52"
mkdir -p "${old}/lib" "${old}/public"
echo '{"standard": {"mod": ["forum"]}, "deleted": {"mod": ["chat", "survey"]}}' > "${old}/lib/plugins.json"
printf '<?php\n$version = 2026042000.00;\n' > "${old}/public/version.php"
plugin "${old}/public/mod/forum" 2026042000
plugin "${old}/public/mod/chat" 2024110500
plugin "${old}/public/mod/survey" 2024110500
check "5.2 tree: separate releases kept on a point update" "${old}" "mod_chat mod_survey " ""

# An image built on this one ships Chat: its copy is used, unless the old
# tree has a newer one.
plugin "${new}/public/mod/chat" 2024110500
check "image ships the same version: image copy used" "${work}/old45" "local_extra mod_survey " ""
plugin "${new}/public/mod/survey" 2024110400
check "old tree newer than the image's copy: old copy kept" "${work}/old52" "mod_survey " ""

exit "${failed}"
