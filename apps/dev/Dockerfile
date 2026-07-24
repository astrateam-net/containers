# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

# Custom Coder build that grants cap_net_bind_service on the server binary, so
# the non-root (uid 1000) process can bind privileged ports (e.g. 80/443)
# directly, without root or an external port-forwarder.
#
# The server is rebuilt from the pinned upstream tag with the local patch series
# in patches/ applied. The build mirrors upstream's own pipeline
# (scripts/build_go.sh + the Makefile build-slim packaging), so the result
# matches the published image:
#   - the React frontend is built from the pinned tag,
#   - the slim agent/CLI binaries are compiled and packed into
#     site/out/bin/{coder.tar.zst,coder.sha1} (this is what the /bin/ endpoint
#     and the `coder` CLI/agent downloads serve; site/bin.go reads them),
#   - the server binary embeds all of that via `//go:embed all:out`.
# Only amd64 agents are built (no ARM), matching the deployment target.
#
# Assembled onto the upstream runtime base image (FROM ghcr.io/coder/coder),
# which supplies terraform, the entrypoint, and the non-root uid 1000 user, so
# everything outside /opt/coder matches upstream.
#
# The frontend builder is pinned to $BUILDPLATFORM (the SPA is arch-independent)
# and the Go binary is built for $TARGETARCH, so the (amd64-only) build never
# falls back to QEMU.

ARG VERSION

# Go build flags kept in sync with upstream scripts/build_go.sh. ts_omit_* trims
# unused Tailscale features (notably the AWS SDK), matching upstream binary size.
ARG GO_TAGS_COMMON="ts_omit_aws,ts_omit_bird,ts_omit_tap,ts_omit_kube"

# Slim CLI platforms to embed and serve at /bin/. Coder Desktop and `coder`
# download the binary matching the CLIENT's os/arch from the server, so we must
# host every platform a client connects from — notably darwin/arm64 (Apple
# Silicon). Missing a client's arch leaves it on its bundled older binary and it
# fails the server version check. Mirrors upstream's matrix except linux/armv7,
# which needs GOARM handling and a coder-linux-armv7 name this os:arch loop can't
# emit. Space-separated os:arch entries.
ARG SLIM_OSARCHES="linux:amd64 linux:arm64 darwin:amd64 darwin:arm64 windows:amd64 windows:arm64"

# --- Stage 1: build the React frontend from pristine upstream ---------------
FROM --platform=$BUILDPLATFORM docker.io/library/node:22.19.0-bookworm AS site
ARG VERSION
RUN corepack enable && corepack prepare pnpm@10.33.2 --activate
WORKDIR /src
RUN git init -q . \
    && git remote add origin https://github.com/coder/coder.git \
    && git fetch --depth 1 origin "refs/tags/${VERSION}" \
    && git checkout -q FETCH_HEAD

# Frontend source patches, applied to the pristine tag BEFORE the SPA is built.
# These must live in stage 1: stage 2 embeds the already-built site/out, so a
# stage-2 patch (patches/) never reaches the bundle. Applied unconditionally,
# independent of the I18N gate, so the stock English build gets them too. git
# apply fails the build loudly on version drift, same as the Go patch series.
COPY site-patches/ /site-patches/
RUN for p in /site-patches/*.patch; do echo "applying $p"; git apply --verbose "$p"; done

WORKDIR /src/site
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    pnpm install --frozen-lockfile

# --- i18n (optional): Russian localization via the dev-kit coder-i18n factory -
# Pulls the published factory and runs its DETERMINISTIC steps against this
# checkout: the codemod wraps UI literals into Tolgee shapes, then bake injects
# the provider + a language switcher + the pre-translated catalogs the factory
# ships in dist/. Translation (Tolgee/OpenAI) is NOT run here — it happens
# offline when strings change. Build the stock English frontend with
# `--set image-local.args.I18N=` (empty).
ARG DEV_KIT_VERSION=v0.3.0
ARG I18N=ru
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    if [ -n "$I18N" ]; then \
      git clone --depth 1 --branch "${DEV_KIT_VERSION}" \
        https://github.com/astrateam-net/dev-kit.git /factory \
      && ( cd /factory/coder-i18n \
           && mkdir -p .upstream && ln -s /src .upstream/coder \
           && pnpm install --frozen-lockfile \
           && pnpm exec tsx codemod/wrap.ts \
           && pnpm exec tsx codemod/inject-runtime.ts ) \
      && pnpm add @tolgee/react@latest @tolgee/format-icu@latest ; \
    fi

# README embeds: the site-patches/0002 README iframe support needs rehype-raw +
# rehype-sanitize (not in upstream's lockfile). Pinned to the unified-11 line
# that react-markdown 9 uses. Which iframe hosts may actually load is enforced
# at runtime by Coder's frame-src CSP (CODER_ADDITIONAL_CSP_POLICY), so there is
# no build-time host allowlist here.
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    pnpm add rehype-raw@7.0.0 rehype-sanitize@6.0.0
RUN NODE_ENV=production pnpm build

# --- Stage 2: patch + build slim agents + cross-compile the server ----------
FROM --platform=$BUILDPLATFORM docker.io/library/golang:1.26.4-bookworm AS build
ARG VERSION
ARG TARGETOS
ARG TARGETARCH
ARG GO_TAGS_COMMON
ARG SLIM_OSARCHES
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates zstd curl unzip \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
RUN git init -q . \
    && git remote add origin https://github.com/coder/coder.git \
    && git fetch --depth 1 origin "refs/tags/${VERSION}" \
    && git checkout -q FETCH_HEAD
# Apply the local patch series on top of the pristine tag. git apply fails the
# build loudly if a patch does not match the pinned VERSION.
COPY patches/ /patches/
RUN for p in /patches/*.patch; do echo "applying $p"; git apply --verbose "$p"; done

# Browser-RDP authority: the coderd adapters + launch endpoint (package coderd,
# version-robust new files) backing the dev-kit jetbroker core, plus the module
# dependency. The route registration itself rides in patches/ (version-coupled).
ARG DEV_KIT_VERSION=v0.3.0
COPY overlay/coderd/ ./coderd/
# Browser-RDP gateway direct-proxy helper (package workspaceapps; called by the
# proxy branch in patches/0003). Version-robust, no new module deps.
COPY overlay/workspaceapps/ ./coderd/workspaceapps/
RUN --mount=type=cache,target=/go/pkg/mod \
    go get "github.com/astrateam-net/dev-kit@${DEV_KIT_VERSION}" \
    && go mod tidy

COPY --from=site /src/site/out ./site/out

# Build the slim agent/CLI binaries the server serves at /bin/, then pack them
# into site/out/bin exactly as upstream's `make build-slim` does:
#   coder.sha1     "<sha1> *<file>" manifest (sha1sum -b), parsed by site/bin.go
#   coder.tar.zst  zstd-compressed tar of the coder-<os>-<arch> binaries
# The raw binaries are then removed, so only the archive + manifest get embedded.
#
# Exception: coder-darwin-arm64 is REPLACED with Coder's official release binary.
# Coder Desktop (macOS) downloads the client-arch binary from /bin/ and rejects
# it unless it carries Coder's Apple Developer ID signature (team 4399GN35BJ),
# which only Coder can produce. Our self-built binary is unsigned → "signature is
# invalid". The release zip binary is the fat (full) build, hence larger, but it
# is the only signed darwin/arm64 Coder publishes as a standalone file. Other
# arches need no signature check (Linux: none; the org has no Intel Macs).
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    version="${VERSION#v}"; \
    for osarch in ${SLIM_OSARCHES}; do \
      os="${osarch%%:*}"; arch="${osarch##*:}"; ext=""; \
      [ "$os" = windows ] && ext=".exe"; \
      echo ">> building slim coder-$os-$arch$ext"; \
      CGO_ENABLED=0 GOOS="$os" GOARCH="$arch" \
        go build -tags "slim,${GO_TAGS_COMMON}" \
        -ldflags "-s -w -X github.com/coder/coder/v2/buildinfo.tag=${version}" \
        -o "site/out/bin/coder-$os-$arch$ext" ./enterprise/cmd/coder || exit 1; \
    done; \
    echo ">> replacing coder-darwin-arm64 with Coder's official signed release binary"; \
    curl -fsSL -o /tmp/darwin-arm64.zip \
      "https://github.com/coder/coder/releases/download/${VERSION}/coder_${version}_darwin_arm64.zip"; \
    mkdir -p /tmp/darwin-arm64 && unzip -oq /tmp/darwin-arm64.zip -d /tmp/darwin-arm64; \
    signed="$(find /tmp/darwin-arm64 -type f -name coder | head -1)"; \
    [ -n "$signed" ] || { echo "ERROR: no coder binary in darwin_arm64 release zip"; exit 1; }; \
    head -c4 "$signed" | od -An -tx1 | tr -d ' \n' | grep -qi '^cffaedfe$' \
      || { echo "ERROR: darwin_arm64 release binary is not a Mach-O 64 executable"; exit 1; }; \
    cp "$signed" site/out/bin/coder-darwin-arm64; \
    rm -rf /tmp/darwin-arm64 /tmp/darwin-arm64.zip; \
    cd site/out/bin \
    && sha1sum -b coder-* | tee coder.sha1 \
    && tar cf coder.tar coder-* \
    && zstd -19 --long -T0 --no-progress --force --rm -o coder.tar.zst coder.tar \
    && rm -f coder-*

# Build the server ("fat") binary. -tags embed pulls site/out (frontend +
# coder.tar.zst + coder.sha1) into the binary via //go:embed all:out.
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    version="${VERSION#v}" \
    && CGO_ENABLED=0 GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" \
       go build -tags "embed,${GO_TAGS_COMMON}" \
       -ldflags "-s -w -X github.com/coder/coder/v2/buildinfo.tag=${version}" \
       -o /opt/coder ./enterprise/cmd/coder

# --- Stage 3: assemble onto the upstream runtime base -----------------------
FROM ghcr.io/coder/coder:${VERSION}

USER root
COPY --from=build --chown=1000:1000 --chmod=755 /opt/coder /opt/coder
RUN apk add --no-cache libcap \
 && setcap cap_net_bind_service=+ep /opt/coder
USER 1000:1000

ENTRYPOINT [ "/opt/coder", "server" ]
