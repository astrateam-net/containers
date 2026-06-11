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

# Slim agent/CLI platforms to embed, amd64 only (upstream also ships the arm64
# and armv7 variants). Space-separated os:arch entries.
ARG SLIM_OSARCHES="linux:amd64 darwin:amd64 windows:amd64"

# --- Stage 1: build the React frontend from pristine upstream ---------------
FROM --platform=$BUILDPLATFORM docker.io/library/node:22.19.0-bookworm AS site
ARG VERSION
RUN corepack enable && corepack prepare pnpm@10.33.2 --activate
WORKDIR /src
RUN git init -q . \
    && git remote add origin https://github.com/coder/coder.git \
    && git fetch --depth 1 origin "refs/tags/${VERSION}" \
    && git checkout -q FETCH_HEAD
WORKDIR /src/site
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    pnpm install --frozen-lockfile
RUN NODE_ENV=production pnpm build

# --- Stage 2: patch + build slim agents + cross-compile the server ----------
FROM --platform=$BUILDPLATFORM docker.io/library/golang:1.26.4-bookworm AS build
ARG VERSION
ARG TARGETOS
ARG TARGETARCH
ARG GO_TAGS_COMMON
ARG SLIM_OSARCHES
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates zstd \
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
ARG DEV_KIT_VERSION=v0.2.0
COPY overlay/coderd/ ./coderd/
RUN --mount=type=cache,target=/go/pkg/mod \
    go get "github.com/astrateam-net/dev-kit@${DEV_KIT_VERSION}" \
    && go mod tidy

COPY --from=site /src/site/out ./site/out

# Build the slim agent/CLI binaries the server serves at /bin/, then pack them
# into site/out/bin exactly as upstream's `make build-slim` does:
#   coder.sha1     "<sha1> *<file>" manifest (sha1sum -b), parsed by site/bin.go
#   coder.tar.zst  zstd-compressed tar of the coder-<os>-<arch> binaries
# The raw binaries are then removed, so only the archive + manifest get embedded.
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
