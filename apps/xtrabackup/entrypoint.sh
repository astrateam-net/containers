#!/bin/bash
set -eu

# ── Docker secrets support ─────────────────────────────────────────
# All sensitive vars support _FILE suffix for Docker Swarm secrets.
# Example: MYSQL_PASSWORD_FILE=/run/secrets/mysql_password
file_env() {
    local var="$1"
    local file_var="${var}_FILE"
    local default="${2:-}"

    if [ -n "${!var:-}" ] && [ -n "${!file_var:-}" ]; then
        echo >&2 "Error: both ${var} and ${file_var} are set (use one or the other)"
        exit 1
    fi
    if [ -n "${!file_var:-}" ]; then
        if [ ! -r "${!file_var}" ]; then
            echo >&2 "Error: ${file_var} points to '${!file_var}' but it is not readable"
            exit 1
        fi
        export "$var"="$(< "${!file_var}")"
    elif [ -z "${!var:-}" ] && [ -n "${default}" ]; then
        export "$var"="${default}"
    fi
    unset "$file_var" 2>/dev/null || true
}

# ── Resolve secrets ────────────────────────────────────────────────
file_env MYSQL_HOST
file_env MYSQL_USER
file_env MYSQL_PASSWORD
file_env S3_ENDPOINT
file_env S3_ACCESS_KEY
file_env S3_SECRET_KEY
file_env S3_BUCKET

: "${MYSQL_HOST:?MYSQL_HOST or MYSQL_HOST_FILE is required}"
: "${MYSQL_USER:?MYSQL_USER or MYSQL_USER_FILE is required}"
: "${MYSQL_PASSWORD:?MYSQL_PASSWORD or MYSQL_PASSWORD_FILE is required}"
: "${S3_ENDPOINT:?S3_ENDPOINT or S3_ENDPOINT_FILE is required}"
: "${S3_ACCESS_KEY:?S3_ACCESS_KEY or S3_ACCESS_KEY_FILE is required}"
: "${S3_SECRET_KEY:?S3_SECRET_KEY or S3_SECRET_KEY_FILE is required}"
: "${S3_BUCKET:?S3_BUCKET or S3_BUCKET_FILE is required}"

# ── Defaults ───────────────────────────────────────────────────────
export MYSQL_PORT="${MYSQL_PORT:-3306}"
export BACKUP_PARALLEL="${BACKUP_PARALLEL:-4}"
export BACKUP_PREFIX="${BACKUP_PREFIX:-xtrabackup}"
export BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-0}"
export BACKUP_EXTRA_OPTS="${BACKUP_EXTRA_OPTS:-}"
export S3_BUCKET_LOOKUP="${S3_BUCKET_LOOKUP:-path}"
export LSN_DIR=/var/lib/xtrabackup/lsn

# ── Command dispatch ──────────────────────────────────────────────
case "${1:-scheduler}" in
    backup-full|backup-incr|backup-cleanup)
        exec /usr/local/bin/"$1"
        ;;
    restore)
        shift
        exec /usr/local/bin/backup-restore "$@"
        ;;
    scheduler)
        ;; # fall through to cron setup
    *)
        exec "$@"
        ;;
esac

# ── Cron scheduler ────────────────────────────────────────────────
FULL_CRON="${BACKUP_SCHEDULE_FULL:-}"
INCR_CRON="${BACKUP_SCHEDULE_INCR:-}"

if [ -z "${FULL_CRON}" ] && [ -z "${INCR_CRON}" ]; then
    echo "No backup schedules configured (BACKUP_SCHEDULE_FULL / BACKUP_SCHEDULE_INCR)"
    echo "Container available for manual backup-full / backup-incr / restore commands"
    exec sleep infinity
fi

# Export resolved env so cron jobs inherit it
env | grep -E '^(MYSQL_|S3_|BACKUP_|LSN_DIR=)' | sort > /etc/environment.backup

{
    echo "SHELL=/bin/bash"
    echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    [ -n "${FULL_CRON}" ] && \
        echo "${FULL_CRON} root . /etc/environment.backup; /usr/local/bin/backup-full >>/proc/1/fd/1 2>>/proc/1/fd/2"
    [ -n "${INCR_CRON}" ] && \
        echo "${INCR_CRON} root . /etc/environment.backup; /usr/local/bin/backup-incr >>/proc/1/fd/1 2>>/proc/1/fd/2"
    [ "${BACKUP_RETENTION_DAYS}" -gt 0 ] && \
        echo "15 0 * * * root . /etc/environment.backup; /usr/local/bin/backup-cleanup >>/proc/1/fd/1 2>>/proc/1/fd/2"
} > /etc/cron.d/xtrabackup

chmod 0644 /etc/cron.d/xtrabackup

echo "XtraBackup scheduler started"
[ -n "${FULL_CRON}" ] && echo "  Full:    ${FULL_CRON}"
[ -n "${INCR_CRON}" ] && echo "  Incr:    ${INCR_CRON}"
[ "${BACKUP_RETENTION_DAYS}" -gt 0 ] && echo "  Cleanup: daily 00:15 (retain ${BACKUP_RETENTION_DAYS} days)"

exec crond -n
