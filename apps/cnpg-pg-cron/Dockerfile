# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG PG_MAJOR
ARG DISTRO
FROM ghcr.io/cloudnative-pg/postgresql:${PG_MAJOR}-minimal-${DISTRO} AS builder

ARG PG_MAJOR
ARG EXT_VERSION

USER 0

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        "postgresql-${PG_MAJOR}-cron=${EXT_VERSION}" \
    && rm -rf /var/lib/apt/lists/*

# CloudNativePG mounts this image read-only at /extensions/<name> and points
# extension_control_path at ./share and dynamic_library_path at ./lib, so the
# layout below is the contract — not a convention we chose.
# https://cloudnative-pg.io/docs/current/imagevolume_extensions#image-specifications
FROM scratch
ARG PG_MAJOR
ARG EXT_VERSION

COPY --from=builder /usr/share/doc/postgresql-${PG_MAJOR}-cron/copyright /licenses/postgresql-${PG_MAJOR}-cron/
COPY --from=builder /usr/lib/postgresql/${PG_MAJOR}/lib/pg_cron* /lib/
COPY --from=builder /usr/share/postgresql/${PG_MAJOR}/extension/pg_cron* /share/extension/

USER 65532:65532

LABEL org.opencontainers.image.description="pg_cron ${EXT_VERSION} as a CloudNativePG image volume extension for PostgreSQL ${PG_MAJOR}"
LABEL org.opencontainers.image.licenses="PostgreSQL"
