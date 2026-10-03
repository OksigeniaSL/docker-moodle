# shellcheck shell=bash
# Code volume: layout detection, permissions, and keeping the Moodle code in
# the volume in step with the code shipped in the image.

IMAGE_CODE=/usr/src/moodle
IMAGE_ACCESS=/usr/src/oksigenia-access

# Native layout: /var/www/moodle (code) and /var/www/moodledata.
# Bitnami layout: volumes mounted at /bitnami/moodle and /bitnami/moodledata,
# either with an existing bitnami/moodle installation or empty.
detect_layout() {
    if [ -d /bitnami/moodle ]; then
        OKS_LAYOUT=bitnami
        MOODLE_CODE_DIR=/bitnami/moodle
        : "${MOODLE_DATA_DIR:=/bitnami/moodledata}"
    else
        OKS_LAYOUT=native
        MOODLE_CODE_DIR=/var/www/moodle
        : "${MOODLE_DATA_DIR:=/var/www/moodledata}"
    fi
    OKS_STATE="${MOODLE_CODE_DIR}/.oksigenia"
    OKS_DATA_STATE="${MOODLE_DATA_DIR}/oksigenia"
    export OKS_LAYOUT MOODLE_CODE_DIR MOODLE_DATA_DIR
}

# When started as root, make sure www-data can write both volumes.
# The code volume is handed to www-data entirely: its core files are
# replaced on every upgrade, and the previous tree, with its original
# ownership, is kept in the backup. The data volume is only chowned when
# www-data cannot write to it at all; volumes from bitnami/moodle are
# writable through the root and daemon groups and keep their ownership.
fix_permissions() {
    mkdir -p "${MOODLE_CODE_DIR}" "${MOODLE_DATA_DIR}"
    if ! as_www test -w "${MOODLE_CODE_DIR}" -a -x "${MOODLE_CODE_DIR}" \
        || [ -n "$(find "${MOODLE_CODE_DIR}" -mindepth 1 ! -user www-data -print -quit)" ]; then
        log "Giving www-data ownership of the code in ${MOODLE_CODE_DIR}"
        chown -R www-data:www-data "${MOODLE_CODE_DIR}"
    fi
    if ! as_www test -w "${MOODLE_DATA_DIR}" -a -x "${MOODLE_DATA_DIR}"; then
        log "Giving www-data ownership of ${MOODLE_DATA_DIR} (this can take a while on large volumes)"
        chown -R www-data:www-data "${MOODLE_DATA_DIR}"
    fi
}

check_permissions() {
    local dir blocked
    for dir in "${MOODLE_CODE_DIR}" "${MOODLE_DATA_DIR}"; do
        [ -d "${dir}" ] || mkdir -p "${dir}" 2>/dev/null \
            || die "${dir} does not exist and cannot be created"
        if [ ! -w "${dir}" ] || [ ! -x "${dir}" ]; then
            blocked="${dir}"
        fi
    done
    # Every directory of the code must be writable to replace it on upgrades.
    : "${blocked:=$(find "${MOODLE_CODE_DIR}" -mindepth 1 -type d ! -writable -print -quit)}"
    if [ -n "${blocked}" ]; then
        die "$(id -un) cannot write to ${blocked}. Either start the container as root once
        (it fixes ownership and then drops to www-data), or run on the host:
        sudo chown -R 33:33 <host directories mounted at ${MOODLE_CODE_DIR} and ${MOODLE_DATA_DIR}>"
    fi
}

# Paths that depend on the Moodle layout of the code in the image.
code_paths() {
    if [ -d "${IMAGE_CODE}/public" ]; then
        MOODLE_DOCROOT="${MOODLE_CODE_DIR}/public"
        OKS_ACCESS_DIR="${MOODLE_CODE_DIR}/public/local/oksigeniaaccess"
    else
        MOODLE_DOCROOT="${MOODLE_CODE_DIR}"
        OKS_ACCESS_DIR="${MOODLE_CODE_DIR}/local/oksigeniaaccess"
    fi
    export MOODLE_DOCROOT
}

# A stable path for the code, whatever the layout, so that `moodle-cli`,
# /opt/bitnami/moodle and habits like `cd /var/www/moodle` all work.
link_code_dir() {
    if [ "${MOODLE_CODE_DIR}" != /var/www/moodle ] && [ ! -L /var/www/moodle ] \
        && ! mountpoint -q /var/www/moodle; then
        rmdir /var/www/moodle 2>/dev/null && ln -s "${MOODLE_CODE_DIR}" /var/www/moodle || true
    fi
}

backup_dir_new() {
    OKS_BACKUP_DIR="${OKS_DATA_STATE}/backups/$(date -u +%Y%m%dT%H%M%SZ)"
    mkdir -p "${OKS_BACKUP_DIR}"
    chmod 0700 "${OKS_DATA_STATE}/backups"
}

# Keep the newest MOODLE_BACKUP_KEEP backups.
backup_rotate() {
    local keep="${MOODLE_BACKUP_KEEP}" dir
    [ -d "${OKS_DATA_STATE}/backups" ] || return 0
    find "${OKS_DATA_STATE}/backups" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
        | sort -r | tail -n +"$((keep + 1))" | while read -r dir; do
            rm -rf "${OKS_DATA_STATE}/backups/${dir}"
            log "Removed old backup ${dir}"
        done
}

backup_code() {
    log "Backing up the current code to ${OKS_BACKUP_DIR}/code.tar.gz"
    tar -C "${MOODLE_CODE_DIR}" --exclude=./.oksigenia -czf "${OKS_BACKUP_DIR}/code.tar.gz" . \
        || die "code backup failed; nothing was changed"
}

# Replace the core code in the volume with the image's, keeping config.php
# and the add-on plugins. Interrupted swaps resume on the next start.
replace_code() {
    local next="${OKS_STATE}/next" addons component from to removed
    rm -rf "${next}"
    mkdir -p "${next}"
    cp -a "${IMAGE_CODE}/." "${next}/"

    addons="$(php "${OKS_PHP}/addons.php" "${MOODLE_CODE_DIR}" "${IMAGE_CODE}" 2>"${OKS_STATE}/removed.txt")" \
        || die "could not list the add-on plugins; nothing was changed"
    while IFS=$'\t' read -r component from to; do
        [ -n "${component}" ] || continue
        log "Keeping add-on ${component} (${from} -> ${to})"
        mkdir -p "$(dirname "${next}/${to}")"
        cp -a "${MOODLE_CODE_DIR}/${from}" "${next}/${to}"
    done <<< "${addons}"
    removed="$(tr '\n' ' ' < "${OKS_STATE}/removed.txt")"
    rm -f "${OKS_STATE}/removed.txt"
    if [ -n "${removed// /}" ]; then
        log "Not carried over, Moodle removed them from core: ${removed}"
    fi

    local keep
    for keep in config.php .user_scripts_initialized; do
        if [ -e "${MOODLE_CODE_DIR}/${keep}" ]; then
            cp -a "${MOODLE_CODE_DIR}/${keep}" "${next}/${keep}"
        fi
    done

    touch "${OKS_STATE}/swap-in-progress"
    finish_swap
}

finish_swap() {
    local next="${OKS_STATE}/next" entry
    [ -d "${next}" ] || { rm -f "${OKS_STATE}/swap-in-progress"; return 0; }
    shopt -s dotglob nullglob
    for entry in "${MOODLE_CODE_DIR}"/*; do
        case "${entry##*/}" in .oksigenia|lost+found) continue ;; esac
        rm -rf "${entry}"
    done
    for entry in "${next}"/*; do
        mv "${entry}" "${MOODLE_CODE_DIR}/"
    done
    shopt -u dotglob nullglob
    rmdir "${next}"
    rm -f "${OKS_STATE}/swap-in-progress"
}

# Bring the code volume in line with the image.
sync_code() {
    local state details
    mkdir -p "${OKS_STATE}" "${OKS_DATA_STATE}"
    if [ -f "${OKS_STATE}/swap-in-progress" ]; then
        log "Resuming an interrupted code update"
        finish_swap
    fi

    read -r state details < <(php "${OKS_PHP}/code-state.php" "${MOODLE_CODE_DIR}" "${IMAGE_CODE}")
    case "${state}" in
        fresh)
            if [ -n "$(find "${MOODLE_CODE_DIR}" -mindepth 1 -maxdepth 1 ! -name .oksigenia ! -name lost+found -print -quit)" ]; then
                die "${MOODLE_CODE_DIR} is not empty but has no Moodle code; refusing to overwrite it"
            fi
            log "Installing Moodle ${details} code into ${MOODLE_CODE_DIR}"
            cp -a "${IMAGE_CODE}/." "${MOODLE_CODE_DIR}/"
            ;;
        same)
            ;;
        upgrade)
            is_on "${MOODLE_AUTO_UPGRADE}" \
                || die "the image has a newer Moodle (${details}) and MOODLE_AUTO_UPGRADE is off"
            log "Updating Moodle code: ${details}"
            OKS_CODE_CHANGED=yes
            ;;
        downgrade)
            die "the code volume has a newer Moodle than this image (${details}).
        Use an image with the same or a newer version; downgrades are not possible.
        If that code never ran against this database (for example a development tree
        copied in by hand), move it out of ${MOODLE_CODE_DIR} and start again: the image
        then installs its own code and upgrades the database from its current version."
            ;;
        unsupported)
            die "cannot upgrade directly: ${details}"
            ;;
        *)
            die "cannot compare the code versions: ${state} ${details}"
            ;;
    esac
}

# Activity modules that Moodle removed from core (Chat and Survey in 5.0,
# for example) are uninstalled by Moodle's upgrade, with their activities.
# Refuse to do that silently when the site has such activities.
check_removed_modules() {
    [ "${OKS_DB_STATE}" = installed ] || return 0
    local removed component count blocked=()
    removed="$(php "${OKS_PHP}/addons.php" "${MOODLE_CODE_DIR}" "${IMAGE_CODE}" 2>&1 >/dev/null)" || return 0
    for component in ${removed}; do
        case "${component}" in
            mod_*)
                count="$(php "${OKS_PHP}/db.php" activities "${component#mod_}")"
                [ "${count}" -gt 0 ] && blocked+=("${component} (${count} activities)")
                ;;
        esac
    done
    [ "${#blocked[@]}" -gt 0 ] || return 0
    if is_on "${MOODLE_ALLOW_REMOVED_PLUGINS:-no}"; then
        warn "Moodle will uninstall these modules and delete their activities: ${blocked[*]}"
        return 0
    fi
    die "this upgrade removes modules that Moodle no longer ships, and this site uses them:
        ${blocked[*]}
        Moodle's upgrade would delete those activities. Either keep the current image tag,
        or set MOODLE_ALLOW_REMOVED_PLUGINS=yes to go ahead (a database backup is taken first).
        Versions of these modules for newer Moodle may exist at https://moodle.org/plugins"
}

# Runs after the database is reachable, so the backup can include it.
apply_code_update() {
    [ "${OKS_CODE_CHANGED:-no}" = yes ] || return 0
    check_removed_modules
    backup_dir_new
    backup_code
    if is_on "${MOODLE_BACKUP_BEFORE_UPGRADE}" && [ "${OKS_DB_STATE}" = installed ]; then
        backup_database
        OKS_DB_BACKED_UP=yes
    fi
    replace_code
    backup_rotate
    log "Moodle code updated; the database upgrade follows"
}

# The Access plugin is copied into the code tree only when enabled.
sync_access() {
    OKS_ACCESS_PRESENT=no
    if is_on "${OKSIGENIA_ACCESS}"; then
        local have want
        want="$(cat "${IMAGE_ACCESS}/.oksigenia-image-version")"
        have="$(sed -n "s/.*->release *= *'\([^']*\)'.*/\1/p" "${OKS_ACCESS_DIR}/version.php" 2>/dev/null || true)"
        if [ "${have}" != "${want}" ]; then
            log "Installing Oksigenia Access ${want}"
            rm -rf "${OKS_ACCESS_DIR}"
            mkdir -p "$(dirname "${OKS_ACCESS_DIR}")"
            cp -a "${IMAGE_ACCESS}" "${OKS_ACCESS_DIR}"
            rm -f "${OKS_ACCESS_DIR}/.oksigenia-image-version"
        fi
    fi
    [ -f "${OKS_ACCESS_DIR}/version.php" ] && OKS_ACCESS_PRESENT=yes
    export OKS_ACCESS_PRESENT
}
