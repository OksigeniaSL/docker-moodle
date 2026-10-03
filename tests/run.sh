#!/bin/bash
# End-to-end tests for the image. Used by CI and locally.
#
#   tests/run.sh install-mariadb   IMAGE=oksigenia/moodle:5.2
#   tests/run.sh install-pgsql     IMAGE=...
#   tests/run.sh access            IMAGE=...
#   tests/run.sh upgrade           IMAGE_OLD=... IMAGE=...
#   tests/run.sh bitnami           IMAGE=... BITNAMI_IMAGE=bitnamilegacy/moodle:5.0.2
#
# Each scenario runs in its own Compose project and removes it, volumes
# included, when it finishes. KEEP=1 leaves it running for debugging.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCENARIO="${1:?scenario}"
export IMAGE="${IMAGE:-}"
export MOODLE_IMAGE="${IMAGE}"
PROJECT="moodletest-${SCENARIO}-$$"
WAIT_INSTALL="${WAIT_INSTALL:-1200}"

log()  { printf '\n==> %s\n' "$*"; }
fail() { printf '\nFAIL: %s\n' "$*" >&2; dump_logs; exit 1; }

compose() { docker compose -p "${PROJECT}" -f "${COMPOSE_FILE}" "$@"; }

dump_logs() {
    [ -n "${COMPOSE_FILE:-}" ] || return 0
    printf '\n--- container logs (last 150 lines) ---\n' >&2
    compose logs --no-color --tail=150 >&2 || true
}

cleanup() {
    if [ -n "${KEEP:-}" ]; then
        log "KEEP set: project ${PROJECT} left running"
        return
    fi
    [ -n "${COMPOSE_FILE:-}" ] && compose down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Wait until the moodle service reports healthy.
wait_healthy() {
    local id state health status deadline=$(( $(date +%s) + WAIT_INSTALL ))
    while :; do
        id="$(compose ps -a -q moodle)"
        [ -n "${id}" ] || fail "no moodle container"
        state="$(docker inspect -f '{{.State.Status}}' "${id}")"
        health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "${id}")"
        case "${state}" in
            exited|dead) fail "moodle container stopped (exit code $(docker inspect -f '{{.State.ExitCode}}' "${id}"))" ;;
        esac
        [ "${health}" = healthy ] && return 0
        status="${state}/${health}"
        [ "$(date +%s)" -lt "${deadline}" ] || fail "moodle not healthy after ${WAIT_INSTALL}s (status: ${status})"
        sleep 10
    done
}

# HTTP status of a path, requested from inside the container.
http_status() {
    compose exec -T moodle curl -s -o /dev/null -w '%{http_code}' "http://localhost:8080$1"
}

http_body() {
    compose exec -T moodle curl -s "http://localhost:8080$1"
}

expect_status() {
    local got
    got="$(http_status "$1")"
    [ "${got}" = "$2" ] || fail "GET $1 returned ${got}, expected $2"
    echo "GET $1 -> ${got}"
}

cli() { compose exec -T moodle moodle-cli "$@"; }

# PHP evaluated inside Moodle, as www-data (never as root: Moodle would
# leave root-owned cache files behind).
moodle_eval() {
    compose exec -T -u www-data -w /var/www/moodle moodle \
        php -r "define('CLI_SCRIPT', true); require 'config.php'; $1"
}

# shellcheck disable=SC2016  # PHP code, expanded by PHP
moodle_release() { moodle_eval 'echo $CFG->release;'; }

plugin_version() { moodle_eval "echo get_config('$1', 'version');"; }

# The cron loop ran: Moodle records the start of each run.
expect_cron() {
    local deadline=$(( $(date +%s) + 240 )) last
    while :; do
        last="$(moodle_eval "echo (int) get_config('tool_task', 'lastcronstart');" || echo 0)"
        [ "${last}" -gt 0 ] && { echo "cron ran at ${last}"; return 0; }
        [ "$(date +%s)" -lt "${deadline}" ] || fail "cron has not run"
        sleep 10
    done
}

expect_nonroot() {
    local users
    users="$(compose exec -T moodle ps -eo user=,comm= | awk '$2 ~ /apache2|php/ {print $1}' | sort -u | tr '\n' ' ')"
    [ "${users}" = "www-data " ] || fail "Apache/PHP processes run as: ${users}"
    echo "Apache and PHP run as www-data"
}

basic_checks() {
    wait_healthy
    expect_status /login/index.php 200
    # New sites have forcelogin on, so the front page may send guests to the login page.
    local front
    front="$(http_status /)"
    case "${front}" in 200|303) echo "GET / -> ${front}" ;; *) fail "GET / returned ${front}" ;; esac
    [ "$(http_body /_oksigenia/health)" = OK ] || fail "health endpoint is not OK"
    expect_nonroot
    expect_cron
    echo "Moodle $(moodle_release)"
}

add_test_plugin() {
    local dir="$1"
    compose cp "${HERE}/fixtures/local_oksitest" "moodle:${dir}/local/oksitest"
    compose exec -T -u 0 moodle chown -R "$2" "${dir}/local/oksitest"
}

case "${SCENARIO}" in
    install-mariadb|install-pgsql)
        COMPOSE_FILE="${HERE}/compose/${SCENARIO#install-}.yaml"
        log "Clean install (${SCENARIO#install-}) with ${IMAGE:?}"
        compose up -d
        basic_checks
        log "Restart keeps the site"
        compose restart moodle
        wait_healthy
        expect_status /login/index.php 200
        ;;

    access)
        COMPOSE_FILE="${HERE}/compose/mariadb.yaml"
        log "Oksigenia Access off by default (${IMAGE:?})"
        compose up -d
        wait_healthy
        # A page guests can open (the site home is off by default from 5.2)
        # and that renders the footer, where the panel goes.
        cli cfg --name=forcelogin --set=0 >/dev/null
        page=/course/index.php
        expect_status "${page}" 200
        http_body "${page}" | grep -q '<oksigenia-access-panel' && fail "Access is active although OKSIGENIA_ACCESS is off"
        log "OKSIGENIA_ACCESS=on installs and enables it"
        OKSIGENIA_ACCESS=on compose up -d moodle
        wait_healthy
        [ -n "$(plugin_version local_oksigeniaaccess)" ] || fail "Access is not installed"
        http_body "${page}" | grep -q '<oksigenia-access-panel' || fail "Access panel not rendered"
        log "OKSIGENIA_ACCESS=off again disables it without uninstalling"
        OKSIGENIA_ACCESS=off compose up -d moodle
        wait_healthy
        http_body "${page}" | grep -q '<oksigenia-access-panel' && fail "Access still active after OKSIGENIA_ACCESS=off"
        echo "Access: off by default, on and off by variable"
        ;;

    upgrade)
        COMPOSE_FILE="${HERE}/compose/mariadb.yaml"
        log "Install with the previous image ${IMAGE_OLD:?}"
        IMAGE="${IMAGE_OLD}" compose up -d
        wait_healthy
        old="$(moodle_release)"
        dir="$(compose exec -T moodle sh -c 'test -d /var/www/moodle/public && echo /var/www/moodle/public || echo /var/www/moodle')"
        add_test_plugin "${dir}" www-data:www-data
        cli upgrade --non-interactive >/dev/null
        [ -n "$(plugin_version local_oksitest)" ] || fail "test plugin not installed"
        log "Switch to ${IMAGE:?}"
        compose up -d moodle
        basic_checks
        new="$(moodle_release)"
        [ "${old}" != "${new}" ] || fail "release did not change (${new})"
        [ -n "$(plugin_version local_oksitest)" ] || fail "test plugin lost in the upgrade"
        echo "Upgraded ${old} -> ${new}, add-on kept"
        ;;

    bitnami)
        COMPOSE_FILE="${HERE}/compose/bitnami.yaml"
        log "Install with ${BITNAMI_IMAGE:?}"
        export MOODLE_IMAGE="${BITNAMI_IMAGE}"
        compose up -d
        deadline=$(( $(date +%s) + WAIT_INSTALL ))
        until compose logs moodle 2>/dev/null | grep -q 'Moodle setup finished'; do
            [ "$(date +%s)" -lt "${deadline}" ] || fail "bitnami/moodle did not finish its setup"
            sleep 10
        done
        sleep 15
        # shellcheck disable=SC2016
        old="$(compose exec -T moodle sh -c 'cat /bitnami/moodle/public/version.php /bitnami/moodle/version.php 2>/dev/null | grep -m1 "^\$release"' || true)"
        echo "Bitnami site: ${old}"
        add_test_plugin /bitnami/moodle daemon:root
        compose exec -T -u daemon moodle \
            php /opt/bitnami/moodle/admin/cli/upgrade.php --non-interactive >/dev/null
        log "Swap the image for ${IMAGE:?}, nothing else"
        export MOODLE_IMAGE="${IMAGE}"
        compose up -d moodle
        basic_checks
        [ -n "$(plugin_version local_oksitest)" ] || fail "test plugin lost in the migration"
        compose exec -T moodle sh -c \
            'test -f /bitnami/moodle/public/local/oksitest/version.php || test -f /bitnami/moodle/local/oksitest/version.php' \
            || fail "test plugin code missing"
        echo "Migrated from ${BITNAMI_IMAGE} to $(moodle_release), add-on kept"
        ;;

    *)
        echo "unknown scenario: ${SCENARIO}" >&2
        exit 2
        ;;
esac

log "PASS: ${SCENARIO}"
