# syntax=docker/dockerfile:1

# astravault — thin runtime overlay on the upstream infisical/infisical image.
#
# No upstream source is rebuilt. The backend ships as a per-module transpile (tsup,
# not minified), so a tiny build-time patch rewrites the self-hosted feature set in
# dist/ee/services/license/license-fns.mjs (getDefaultOnPremFeatures) — the single
# chokepoint the license service reads when no license key is set. A wrapper
# entrypoint additionally resolves <VAR>_FILE secrets before the stock launch.

# Global build arg — visible to the FROM line.
ARG VERSION

FROM docker.io/infisical/infisical:v${VERSION}

ARG VERSION

# Patch + install as root (dist is root-owned), then drop back to the runtime user.
USER root
WORKDIR /backend

# Entitle the full self-hosted feature set in the built bundle. The script fails the
# build if the upstream shape changed, so a locked image is never shipped silently.
COPY patch-entitlements.mjs /tmp/astravault-patch-entitlements.mjs
RUN node /tmp/astravault-patch-entitlements.mjs && rm /tmp/astravault-patch-entitlements.mjs

# File-secret support: the upstream image reads config only from plain env vars. Wrap
# its standalone-entrypoint.sh to resolve <VAR>_FILE (Docker/Swarm secrets in
# /run/secrets) into the environment first; the wrapper ends with
# `exec /backend/standalone-entrypoint.sh`, so the upstream launch is preserved.
COPY --chmod=555 file-secrets.sh /backend/astravault-file-secrets.sh
COPY --chmod=555 entrypoint.sh /backend/astravault-entrypoint.sh

USER non-root-user

ENTRYPOINT ["/backend/astravault-entrypoint.sh"]

LABEL org.opencontainers.image.title="astravault" \
      org.opencontainers.image.description="Self-hosted secrets platform for AstraTeam" \
      org.opencontainers.image.vendor="astrateam-net" \
      org.opencontainers.image.version="${VERSION}"
