# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

# CouchDB tuned for Obsidian Self-hosted LiveSync, with declarative
# user / shared-vault provisioning at boot and a one-shot CLI for
# generating obsidian://setuplivesync setup URIs.
ARG VERSION
FROM docker.io/couchdb:${VERSION}

ARG DENO_VERSION
ARG TARGETARCH

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl jq unzip xxd \
    && update-ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Deno (static binary) — needed only by the setup-uri command. Pre-cache
# the encryption npm dep so runtime never needs network access. Pick the
# binary matching the build platform (amd64 → x86_64-…, arm64 → aarch64-…).
RUN case "${TARGETARCH}" in \
        amd64) deno_arch=x86_64-unknown-linux-gnu ;; \
        arm64) deno_arch=aarch64-unknown-linux-gnu ;; \
        *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL "https://github.com/denoland/deno/releases/download/v${DENO_VERSION}/deno-${deno_arch}.zip" -o /tmp/deno.zip \
    && unzip /tmp/deno.zip -d /usr/local/bin \
    && chmod +x /usr/local/bin/deno \
    && rm /tmp/deno.zip \
    && deno --version

RUN mkdir -p /opt/obsync

# Bake LiveSync-tuned CouchDB config into the image.
COPY local.ini /opt/couchdb/etc/local.ini

# Image scripts. Custom generate_setupuri.ts (extends upstream with JWT mode)
# is shipped from this repo rather than fetched at build time, so the URI
# format stays under our control and reproducible.
COPY entrypoint.sh                  /usr/local/bin/obsync-entrypoint.sh
COPY scripts/provision.sh           /opt/obsync/provision.sh
COPY scripts/obsync                 /usr/local/bin/obsync
COPY scripts/generate_setupuri.ts   /opt/obsync/generate_setupuri.ts
RUN chmod +x \
        /usr/local/bin/obsync-entrypoint.sh \
        /opt/obsync/provision.sh \
        /usr/local/bin/obsync \
    && deno cache --allow-import /opt/obsync/generate_setupuri.ts

# Run as the existing couchdb user (uid 5984) so the image's chown-on-start
# block is skipped and read-only mounts work.
USER 5984:5984

# tini is already present in the upstream image and on PATH.
ENTRYPOINT ["tini", "--", "/usr/local/bin/obsync-entrypoint.sh"]
CMD ["/opt/couchdb/bin/couchdb"]
