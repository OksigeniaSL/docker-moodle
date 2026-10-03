# shellcheck shell=bash
# Resolves the configuration from environment variables.
#
# The image has its own variable names (MOODLE_DB_HOST, MOODLE_URL...).
# Variables from bitnami/moodle are accepted too, so an existing Compose
# file keeps working when only the image changes; a warning suggests the
# native name for each one in use.

BITNAMI_VARS_USED=()

# from_bitnami NATIVE BITNAMI...: use the first Bitnami variable that is set
# when the native one is not.
from_bitnami() {
    local native="$1"; shift
    local legacy
    [ -n "${!native:-}" ] && return 0
    for legacy in "$@"; do
        if [ -n "${!legacy:-}" ]; then
            export "${native}=${!legacy}"
            BITNAMI_VARS_USED+=("${legacy} -> ${native}")
            return 0
        fi
    done
}

any_set() {
    local v
    for v in "$@"; do [ -n "${!v:-}" ] && return 0; done
    return 1
}

resolve_env() {
    local v
    # Any of our variables can come from a file: MOODLE_DB_PASSWORD_FILE=...
    for v in $(compgen -e); do
        case "${v}" in
            MOODLE_*_FILE|SMTP_*_FILE|MARIADB_*_FILE|OKSIGENIA_*_FILE) file_env "${v%_FILE}" ;;
        esac
    done

    # A Compose file written for Bitnami: keep its defaults as well.
    BITNAMI_STYLE=no
    if [ "${OKS_LAYOUT}" = bitnami ] || any_set MOODLE_DATABASE_HOST MOODLE_DATABASE_NAME \
        MOODLE_DATABASE_USER MOODLE_DATABASE_PASSWORD MOODLE_DATABASE_TYPE MOODLE_USERNAME \
        MOODLE_PASSWORD MOODLE_HOST MOODLE_SKIP_BOOTSTRAP MOODLE_SKIP_INSTALL; then
        BITNAMI_STYLE=yes
    fi

    from_bitnami MOODLE_DB_TYPE MOODLE_DATABASE_TYPE
    from_bitnami MOODLE_DB_HOST MOODLE_DATABASE_HOST MARIADB_HOST
    from_bitnami MOODLE_DB_PORT MOODLE_DATABASE_PORT_NUMBER MARIADB_PORT_NUMBER
    from_bitnami MOODLE_DB_NAME MOODLE_DATABASE_NAME
    from_bitnami MOODLE_DB_USER MOODLE_DATABASE_USER
    from_bitnami MOODLE_DB_PASSWORD MOODLE_DATABASE_PASSWORD
    from_bitnami MOODLE_ADMIN_USER MOODLE_USERNAME
    from_bitnami MOODLE_ADMIN_PASSWORD MOODLE_PASSWORD
    from_bitnami MOODLE_ADMIN_EMAIL MOODLE_EMAIL
    from_bitnami MOODLE_SMTP_HOST SMTP_HOST
    from_bitnami MOODLE_SMTP_PORT MOODLE_SMTP_PORT_NUMBER SMTP_PORT
    from_bitnami MOODLE_SMTP_USER SMTP_USER
    from_bitnami MOODLE_SMTP_PASSWORD SMTP_PASSWORD
    from_bitnami MOODLE_SMTP_SECURITY MOODLE_SMTP_PROTOCOL SMTP_PROTOCOL
    from_bitnami MOODLE_REVERSE_PROXY MOODLE_REVERSEPROXY
    from_bitnami MOODLE_SSL_PROXY MOODLE_SSLPROXY
    from_bitnami APACHE_HTTP_PORT APACHE_HTTP_PORT_NUMBER
    from_bitnami APACHE_HTTPS_PORT APACHE_HTTPS_PORT_NUMBER
    from_bitnami PHP_ENABLE_OPCACHE PHP_OPCACHE_ENABLED
    if [ -z "${MOODLE_CRON_INTERVAL:-}" ] && [ -n "${MOODLE_CRON_MINUTES:-}" ]; then
        export MOODLE_CRON_INTERVAL=$(( MOODLE_CRON_MINUTES * 60 ))
        BITNAMI_VARS_USED+=("MOODLE_CRON_MINUTES -> MOODLE_CRON_INTERVAL (seconds)")
    fi
    if [ -z "${MOODLE_URL:-}" ] && [ -n "${MOODLE_HOST:-}" ]; then
        if is_on "${MOODLE_SSL_PROXY:-no}"; then
            export MOODLE_URL="https://${MOODLE_HOST}"
        else
            export MOODLE_URL="http://${MOODLE_HOST}"
        fi
        BITNAMI_VARS_USED+=("MOODLE_HOST -> MOODLE_URL")
    fi
    if [ -n "${MOODLE_INSTALL_EXTRA_ARGS:-}" ]; then
        local arg
        for arg in ${MOODLE_INSTALL_EXTRA_ARGS}; do
            case "${arg}" in
                --prefix=*) : "${MOODLE_DB_PREFIX:=${arg#--prefix=}}"; export MOODLE_DB_PREFIX ;;
                *) warn "MOODLE_INSTALL_EXTRA_ARGS: '${arg}' is not supported and is ignored" ;;
            esac
        done
    fi
    if any_set MOODLE_SKIP_BOOTSTRAP MOODLE_SKIP_INSTALL; then
        log "MOODLE_SKIP_BOOTSTRAP is not needed: an existing database is detected automatically"
    fi
    if any_set MYSQL_CLIENT_CREATE_DATABASE_NAME POSTGRESQL_CLIENT_CREATE_DATABASE_NAMES \
               POSTGRESQL_CLIENT_CREATE_DATABASE_NAME; then
        warn "*_CLIENT_CREATE_DATABASE_* variables are ignored: create the database in the database container"
    fi

    # Defaults. Bitnami-style setups keep Bitnami's defaults.
    : "${MOODLE_DB_TYPE:=mariadb}"
    case "${MOODLE_DB_TYPE}" in
        mariadb|mysqli|auroramysql) : "${MOODLE_DB_PORT:=3306}" ;;
        pgsql) : "${MOODLE_DB_PORT:=5432}" ;;
        *) die "MOODLE_DB_TYPE must be mariadb, mysqli, pgsql or auroramysql (got '${MOODLE_DB_TYPE}')" ;;
    esac
    if [ "${BITNAMI_STYLE}" = yes ]; then
        : "${MOODLE_DB_HOST:=mariadb}" "${MOODLE_DB_NAME:=bitnami_moodle}" "${MOODLE_DB_USER:=bn_moodle}"
        : "${MOODLE_ADMIN_USER:=user}" "${MOODLE_ADMIN_EMAIL:=user@example.com}" "${MOODLE_SITE_NAME:=New Site}"
    fi
    : "${MOODLE_DB_HOST:=db}" "${MOODLE_DB_NAME:=moodle}" "${MOODLE_DB_USER:=moodle}"
    : "${MOODLE_DB_PASSWORD:=}" "${MOODLE_DB_PREFIX:=mdl_}"
    : "${MOODLE_ADMIN_USER:=admin}" "${MOODLE_SITE_NAME:=Moodle}" "${MOODLE_LANG:=en}"
    : "${MOODLE_REVERSE_PROXY:=no}" "${MOODLE_SSL_PROXY:=auto}"
    : "${MOODLE_CRON:=on}" "${MOODLE_CRON_INTERVAL:=60}" "${MOODLE_CRON_LOG:=errors}"
    : "${MOODLE_AUTO_UPGRADE:=on}" "${MOODLE_BACKUP_BEFORE_UPGRADE:=on}" "${MOODLE_BACKUP_KEEP:=2}"
    : "${MOODLE_DB_WAIT_TIMEOUT:=300}" "${OKSIGENIA_ACCESS:=off}"
    : "${APACHE_HTTP_PORT:=8080}" "${APACHE_HTTPS_PORT:=8443}"

    if [ -z "${MOODLE_URL:-}" ]; then
        if [ "${OKS_LAYOUT}" = bitnami ]; then
            : # Bitnami's config.php builds wwwroot from the Host header; keep it.
        else
            MOODLE_URL="http://localhost:${APACHE_HTTP_PORT}"
            warn "MOODLE_URL is not set; using ${MOODLE_URL}. Set it to the address your users open."
        fi
    fi
    MOODLE_URL="${MOODLE_URL%/}"
    case "${MOODLE_URL}" in
        ''|http://*|https://*) ;;
        *) die "MOODLE_URL must start with http:// or https:// (got '${MOODLE_URL}')" ;;
    esac
    if [ -n "${MOODLE_URL}" ]; then
        local host="${MOODLE_URL#*://}"; host="${host%%/*}"; host="${host%%:*}"
        : "${APACHE_SERVER_NAME:=${host}}"
        # Moodle rejects addresses like admin@localhost.
        if [[ "${host}" == *.* && ! "${host}" =~ ^[0-9.]+$ ]]; then
            : "${MOODLE_ADMIN_EMAIL:=admin@${host}}"
        fi
    fi
    : "${APACHE_SERVER_NAME:=localhost}" "${MOODLE_ADMIN_EMAIL:=admin@example.com}"
    [ -z "${MOODLE_DB_PASSWORD}" ] && warn "MOODLE_DB_PASSWORD is empty; use this only for local testing"

    # Moodle's timezone also sets PHP's, unless PHP_DATE_TIMEZONE was given.
    if [ -n "${MOODLE_TIMEZONE:-}" ] && [ "${PHP_DATE_TIMEZONE:-UTC}" = UTC ]; then
        PHP_DATE_TIMEZONE="${MOODLE_TIMEZONE}"
    fi

    export MOODLE_DB_TYPE MOODLE_DB_HOST MOODLE_DB_PORT MOODLE_DB_NAME MOODLE_DB_USER \
        MOODLE_DB_PASSWORD MOODLE_DB_PREFIX MOODLE_ADMIN_USER MOODLE_ADMIN_EMAIL MOODLE_SITE_NAME \
        MOODLE_LANG MOODLE_REVERSE_PROXY MOODLE_SSL_PROXY MOODLE_CRON MOODLE_CRON_INTERVAL \
        MOODLE_CRON_LOG MOODLE_AUTO_UPGRADE MOODLE_BACKUP_BEFORE_UPGRADE MOODLE_BACKUP_KEEP \
        MOODLE_DB_WAIT_TIMEOUT OKSIGENIA_ACCESS APACHE_HTTP_PORT APACHE_HTTPS_PORT \
        APACHE_SERVER_NAME MOODLE_URL PHP_DATE_TIMEZONE

    if [ "${#BITNAMI_VARS_USED[@]}" -gt 0 ]; then
        warn "bitnami/moodle variables detected. They work, but consider renaming them:"
        for v in "${BITNAMI_VARS_USED[@]}"; do warn "  ${v}"; done
    fi
}
