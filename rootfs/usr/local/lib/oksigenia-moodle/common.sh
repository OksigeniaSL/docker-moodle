# shellcheck shell=bash
# Shared helpers for the oksigenia/moodle entrypoint.

OKS_LIB=/usr/local/lib/oksigenia-moodle
OKS_PHP="${OKS_LIB}/php"
OKS_RUNTIME_ENV=/tmp/oksigenia-moodle.env

log()  { printf '[moodle] %s\n' "$*"; }
warn() { printf '[moodle] WARNING: %s\n' "$*" >&2; }
die()  { printf '[moodle] ERROR: %s\n' "$*" >&2; OKS_DIED=yes; exit 1; }

# True for on/yes/true/1, false for off/no/false/0/empty.
is_on() {
    case "${1,,}" in
        on|yes|true|1) return 0 ;;
        off|no|false|0|'') return 1 ;;
        *) die "expected on/off, got '${1}'" ;;
    esac
}

is_root() { [ "$(id -u)" = 0 ]; }

# Run a command as www-data, whether we are root or already www-data.
as_www() {
    if is_root; then
        setpriv --reuid=www-data --regid=www-data --init-groups -- "$@"
    else
        "$@"
    fi
}

# Read VAR from the file named in VAR_FILE (Docker secrets).
file_env() {
    local var="$1" file_var="${1}_FILE"
    if [ -n "${!file_var:-}" ]; then
        [ -r "${!file_var}" ] || die "${file_var}: cannot read ${!file_var}"
        export "${var}=$(< "${!file_var}")"
        unset "${file_var}"
    fi
}

# Moodle CLI script, run from the code directory as www-data.
moodle_php() {
    local script="$1"; shift
    ( cd "${MOODLE_CODE_DIR}" && as_www php "${script}" "$@" )
}
