# syntax=docker/dockerfile:1
# AstraIDE — Orca runtime server (`orca serve`) with the trusted-proxy web-session
# patch, for running behind Coder / a reverse proxy that already enforces auth.
#
# Patch-file build (openclaw pattern): clone the pristine upstream release
# (stablyai/orca @ vVERSION) and `git am` the patches under patches/. The change
# lives in this repo, reviewable next to the Dockerfile; the build depends only
# on upstream, not on our fork. The fork (mrkhachaturov/orcaide) is the authoring
# polygon — regenerate patches from its `patch/*` branches, never a build input.

# ── builder ────────────────────────────────────────────────────────────────
# Mirrors upstream's own build environment (config/docker/headless-pairing/
# Dockerfile.build): node 24 + the toolchain electron-builder and the single
# native dep (node-pty) need.
FROM node:24-bookworm AS builder

ARG VERSION
ARG ORCA_REPO=https://github.com/stablyai/orca.git

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    libasound2 \
    libatk-bridge2.0-0 \
    libatspi2.0-0 \
    libdrm2 \
    libgbm1 \
    libgtk-3-0 \
    libnss3 \
    libsecret-1-dev \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxkbcommon0 \
    libxrandr2 \
    libxss1 \
    pkg-config \
    python3 \
  && rm -rf /var/lib/apt/lists/*

RUN corepack enable && corepack prepare pnpm@10.24.0 --activate

WORKDIR /src
# Fetch only the pinned upstream release tag (shallow) — no fork dependency.
RUN git init -q . \
  && git remote add origin "${ORCA_REPO}" \
  && git fetch --depth 1 origin "refs/tags/${VERSION}" \
  && git checkout -q FETCH_HEAD

# Apply the local patch series on top of the pristine tag. git apply fails the
# build loudly if a patch no longer matches the pinned VERSION.
COPY patches/ /patches/
RUN for p in /patches/*.patch; do echo "applying $p"; git apply --verbose "$p"; done

# Why: electron's postinstall downloads the matching Electron runtime; frozen
# lockfile keeps the build reproducible against upstream's committed lockfile.
RUN pnpm install --frozen-lockfile

# build:desktop = typecheck (validates our patch) + relay + cli + electron-vite
# + web (produces out/web, which `serve` streams to the browser). Then rebuild
# node-pty against Electron's ABI and package an unpacked Linux app (no AppImage
# — a container needs neither FUSE nor appimagetool).
RUN pnpm build:desktop \
  && pnpm ensure:electron-runtime \
  && pnpm exec electron-builder --config config/electron-builder.config.cjs --linux dir

# Stage the unpacked app at a stable path. Linux executableName is `orca-ide`.
RUN mkdir -p /out && cp -a dist/linux-unpacked/. /out/ \
  && test -x /out/orca-ide

# ── runtime ────────────────────────────────────────────────────────────────
# Mirrors upstream's headless runtime deps (config/docker/headless-pairing/
# Dockerfile): the Electron/Chromium shared libs + Xvfb, which `serve` starts
# automatically on :99 when no DISPLAY is set.
FROM ubuntu:24.04 AS runner

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    dbus-x11 \
    jq \
    libatk-bridge2.0-0 \
    libatspi2.0-0 \
    libasound2t64 \
    libdrm2 \
    libgbm1 \
    libgtk-3-0 \
    libnss3 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxkbcommon0 \
    libxrandr2 \
    libxss1 \
    procps \
    util-linux \
    xauth \
    xvfb \
    zlib1g-dev \
    wget \
  && rm -rf /var/lib/apt/lists/*

# Non-root service user (keeps parity with the headless doc's dedicated user).
RUN useradd --create-home --shell /bin/bash orca

# Root-owned, world-readable app tree (electron-builder output is 644/755). Per
# the headless doc, runtime state lives in /home/orca/.config, never next to the
# binary — orca only needs read+execute, so no chown layer is required.
COPY --from=builder /out /opt/astraide
COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint

USER orca
WORKDIR /home/orca

# Why: software GL avoids GPU probing in headless containers (per headless doc).
ENV LIBGL_ALWAYS_SOFTWARE=1 \
    ORCA_PORT=6768 \
    ORCA_TRUSTED_PROXY=true \
    ORCA_NO_SANDBOX=true

EXPOSE 6768

# Readiness: the server prints one `orca_server_ready` JSON line on stdout.
HEALTHCHECK --interval=15s --timeout=5s --start-period=90s --retries=10 \
  CMD wget -q -O- "http://127.0.0.1:${ORCA_PORT}/web-index.html" >/dev/null 2>&1 || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint"]
