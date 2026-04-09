# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG VERSION
FROM percona/percona-xtrabackup:${VERSION}

USER root

RUN microdnf -y install cronie && \
    microdnf clean all && \
    rm -rf /var/cache/dnf /var/cache/yum && \
    install -d -o 1001 -g 0 -m 0775 /var/lib/xtrabackup/lsn

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/ /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh \
             /usr/local/bin/backup-full \
             /usr/local/bin/backup-incr \
             /usr/local/bin/backup-cleanup \
             /usr/local/bin/backup-restore

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

LABEL org.opencontainers.image.description="Percona XtraBackup sidecar with scheduled S3/MinIO backups"
