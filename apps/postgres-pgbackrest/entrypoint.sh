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

    cat > /usr/local/bin/pgbackrest-backup-full <<EOF
#!/bin/sh
set -eu
exec gosu postgres pgbackrest --stanza=${stanza} backup --type=full ${backup_opts}
EOF

    cat > /usr/local/bin/pgbackrest-backup-incr <<EOF
#!/bin/sh
set -eu
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
