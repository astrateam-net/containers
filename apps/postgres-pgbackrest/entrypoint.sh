#!/bin/sh
set -eu

setup_pgbackrest_cron() {
    full_cron="${PG_SCHEDULE_FULL_BACKUP_CRON:-}"
    incr_cron="${PG_SCHEDULE_INCR_BACKUP_CRON:-}"

    if [ -z "$full_cron" ] && [ -z "$incr_cron" ]; then
        echo "pgbackrest scheduler disabled: no backup schedules configured"
        return
    fi

    stanza="${PG_SCHEDULE_BACKUP_STANZA:-nas}"
    backup_opts="${PG_SCHEDULE_BACKUP_OPTIONS:-}"

    # cron runs jobs with a sanitized environment, so the PGBACKREST_* variables
    # injected into the container — notably repo1-s3-key / repo1-s3-key-secret,
    # which live ONLY in the env, not in pgbackrest.conf — are invisible to the
    # scheduled jobs and every run dies with "backup command requires option:
    # repo1-s3-key". Snapshot that runtime env to a 0600 file the cron wrappers
    # source before invoking pgbackrest.
    env_file=/etc/pgbackrest/pgbackrest.env
    ( umask 077; export -p | grep -E '(^| )PGBACKREST_' > "$env_file" ) || true
    chown postgres:postgres "$env_file" 2>/dev/null || true

    cat > /usr/local/bin/pgbackrest-backup-full <<EOF
#!/bin/sh
set -eu
[ -f ${env_file} ] && . ${env_file}
exec gosu postgres pgbackrest --stanza=${stanza} backup --type=full ${backup_opts}
EOF

    cat > /usr/local/bin/pgbackrest-backup-incr <<EOF
#!/bin/sh
set -eu
[ -f ${env_file} ] && . ${env_file}
exec gosu postgres pgbackrest --stanza=${stanza} backup --type=incr ${backup_opts}
EOF

    chmod +x /usr/local/bin/pgbackrest-backup-full /usr/local/bin/pgbackrest-backup-incr

    {
        echo "SHELL=/bin/sh"
        echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/lib/postgresql/${PG_MAJOR}/bin"
        if [ -n "$full_cron" ]; then
            echo "${full_cron} root /usr/local/bin/pgbackrest-backup-full >>/proc/1/fd/1 2>>/proc/1/fd/2"
        fi
        if [ -n "$incr_cron" ]; then
            echo "${incr_cron} root /usr/local/bin/pgbackrest-backup-incr >>/proc/1/fd/1 2>>/proc/1/fd/2"
        fi
    } > /etc/cron.d/pgbackrest

    chmod 0644 /etc/cron.d/pgbackrest
    cron
    echo "pgbackrest scheduler enabled: stanza=${stanza}"
    [ -n "$full_cron" ] && echo "  full: ${full_cron}"
    [ -n "$incr_cron" ] && echo "  incr: ${incr_cron}"
}

setup_pgbackrest_cron
exec docker-entrypoint.sh "$@"
