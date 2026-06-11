# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

# devget — Devolutions Gateway edition. Built the same way as apps/dev (Coder):
# the gateway-ui SPA is rebuilt from pristine upstream + our overlay/patches, then
# swapped into the STOCK Devolutions Gateway image. The Rust binary, recording
# player, PowerShell module and entrypoint are upstream-untouched; only the webapp
# (webapp/client) and the entrypoint are ours.
#
# Our logical change is small — one route + one Angular component (the programmatic
# token "launch" the coderd authority redirects to, no login form) + a pnpm-overrides
# patch that stubs five private Devolutions packages so the webapp builds at all
# outside Devolutions' Artifactory. Everything else in gateway-ui is reused as-is.
#
# Two upstream inputs, two layers:
#   - SOURCE repo  github.com/Devolutions/devolutions-gateway @ v$VERSION  -> webapp build
#   - DEFAULT image devolutions/devolutions-gateway:$VERSION               -> runtime base
#                                                                            + real icon assets
# amd64 only, matching apps/dev and the deployment target.

ARG VERSION

# --- Stage 1: the stock image (runtime base + the real @devolutions/icons) -----
# Pinned to the SAME version we build the webapp from, so repo and image are
# byte-locked. We pull the icon font/glyphs out of it in the webapp stage below.
FROM devolutions/devolutions-gateway:${VERSION} AS stock

# --- Stage 2: build the patched gateway-ui SPA from pristine upstream -----------
# The SPA is arch-independent, so pin the builder to $BUILDPLATFORM (no QEMU).
FROM --platform=$BUILDPLATFORM docker.io/library/node:24-bookworm AS webapp
ARG VERSION
RUN corepack enable && corepack prepare pnpm@10.33.2 --activate
WORKDIR /src
# Pristine upstream at the pinned release tag (tags carry a "v" prefix: v2026.2.2).
RUN git init -q . \
    && git remote add origin https://github.com/Devolutions/devolutions-gateway.git \
    && git fetch --depth 1 origin "refs/tags/v${VERSION}" \
    && git checkout -q FETCH_HEAD

# Our layer over upstream: overlay = pure additions (the launch component + the build
# stubs), patches = unified diffs (the launch route + the pnpm overrides). git apply
# fails the build loudly if a patch no longer matches the pinned VERSION.
COPY overlay/. ./
COPY patches/ /patches/
RUN for p in /patches/*.patch; do echo "applying $p"; git apply --verbose "$p"; done

# Repopulate the @devolutions/icons stub with the REAL assets from the stock image
# (font + glyph map) BEFORE install — pnpm hardlinks file: deps at install time, so the
# stub must be real by then. Replaces mise's docker-cp harvest with a plain COPY --from.
COPY --from=stock /opt/devolutions/gateway/webapp/client /tmp/stock-client
COPY tools/harvest-icons.sh /tmp/harvest-icons.sh
RUN bash /tmp/harvest-icons.sh /tmp/stock-client webapp/stubs/icons

# Build the SPA. --no-frozen-lockfile: patch 0002's pnpm overrides (private packages ->
# local stubs) diverge from the committed lockfile; everything else still resolves from it.
WORKDIR /src/webapp
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    pnpm install --no-frozen-lockfile
RUN pnpm --filter gateway-ui build

# --- Stage 3: assemble onto the stock gateway image ----------------------------
FROM devolutions/devolutions-gateway:${VERSION}

# Our patched standalone webapp over the stock one. DGATEWAY_WEBAPP_PATH=
# /opt/devolutions/gateway/webapp is set by the base image; the gateway serves
# client/ from there (with an index-fallback for the /launch deep link).
COPY --from=webapp /src/webapp/dist/gateway-ui/ /opt/devolutions/gateway/webapp/client/

# Our entrypoint = stock logic + the knobs it doesn't expose as env (a fixed GATEWAY_ID
# so the authority's jet_gw_id matches; credential-injection Kerberos later). Same path
# the base image invokes, so no ENTRYPOINT override is needed.
COPY overlay-image/entrypoint.ps1 /usr/local/bin/entrypoint.ps1
