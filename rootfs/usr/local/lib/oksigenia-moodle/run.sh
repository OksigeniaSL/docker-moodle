#!/bin/bash
# Runs Apache and/or the cron loop and exits as soon as one of them stops,
# so that Docker restarts the container. tini (PID 1, with -g) forwards
# stop signals to every process.

set -uo pipefail

# shellcheck source=common.sh
. /usr/local/lib/oksigenia-moodle/common.sh

ROLE="$1"
CRON_LOG="${MOODLE_DATA_DIR}/oksigenia/cron-last.log"

# Moodle expects cron to start every minute (it warns when two starts are
# more than two minutes apart), and by default keeps each run alive for
# three minutes to pick up ad hoc tasks as they arrive. Runs here never
# overlap, so each one stays alive for most of the interval instead.
cron_loop() {
    local interval="${MOODLE_CRON_INTERVAL}" start elapsed rc
    local keepalive="${MOODLE_CRON_KEEPALIVE:-$(( interval > 15 ? interval - 10 : 0 ))}"
    sleep 5
    while :; do
        start=$(date +%s)
        rc=0
        ( cd "${MOODLE_CODE_DIR}" && php admin/cli/cron.php --keep-alive="${keepalive}" ) > "${CRON_LOG}.tmp" 2>&1 || rc=$?
        mv -f "${CRON_LOG}.tmp" "${CRON_LOG}"
        if [ "${rc}" != 0 ]; then
            warn "cron exited with code ${rc}; last lines:"
            tail -n 20 "${CRON_LOG}" | sed 's/^/[cron] /' >&2
        elif [ "${MOODLE_CRON_LOG}" = full ]; then
            sed 's/^/[cron] /' "${CRON_LOG}"
        fi
        elapsed=$(( $(date +%s) - start ))
        [ "${elapsed}" -lt "${interval}" ] && sleep $(( interval - elapsed ))
    done
}

pids=()
if [ "${ROLE}" != web ] && is_on "${MOODLE_CRON}"; then
    cron_loop &
    pids+=($!)
    log "Cron runs every ${MOODLE_CRON_INTERVAL}s (full output: ${CRON_LOG})"
elif [ "${ROLE}" = cron ]; then
    die "role 'cron' with MOODLE_CRON=off has nothing to do"
fi

if [ "${ROLE}" != cron ]; then
    apache_args=()
    [ "${OKS_TLS:-off}" = on ] && apache_args+=(-DMOODLE_HTTPS)
    apache2-foreground "${apache_args[@]}" &
    pids+=($!)
fi

wait -n "${pids[@]}"
rc=$?
warn "a service stopped (exit code ${rc}); stopping the container"
kill "${pids[@]}" 2>/dev/null
exit "${rc}"
