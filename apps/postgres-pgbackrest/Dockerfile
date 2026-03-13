# syntax=docker/dockerfile:1

ARG PG_VERSION=17.8
FROM postgres:${PG_VERSION}

ARG PGBACKREST_VERSION=2.58.0

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates pgbackrest \
    && update-ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && pgbackrest version

LABEL org.opencontainers.image.description="PostgreSQL with pgBackRest ${PGBACKREST_VERSION}"
