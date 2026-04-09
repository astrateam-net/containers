# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG PG_VERSION
FROM postgres:${PG_VERSION}

ARG PGBACKREST_VERSION

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates cron pgbackrest \
    && update-ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && pgbackrest version

COPY entrypoint.sh /usr/local/bin/pgbackrest-entrypoint.sh
RUN chmod +x /usr/local/bin/pgbackrest-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/pgbackrest-entrypoint.sh"]

LABEL org.opencontainers.image.description="PostgreSQL with pgBackRest ${PGBACKREST_VERSION}"
