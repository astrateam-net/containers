# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

# Coder server built from pristine upstream with a small local patch that
# removes the license entitlement gate (patches/0001-entitle-all-features.patch,
# touching enterprise/coderd/coderd.go: updateEntitlements).
#
# No fork: upstream coder/coder is fetched by tag (${VERSION}) at build time and
# the patch is applied on top. The frontend is built unchanged from upstream,
# because the UI shows/hides features purely from what the API reports as
# entitled, which the patch flips on. The result is assembled onto the upstream
# pre-built base image, which supplies terraform, the entrypoint, and the
# non-root uid 1000 user.
#
# The frontend builder is pinned to $BUILDPLATFORM (built natively; the SPA is
# arch-independent) and the Go binary is cross-compiled to $TARGETARCH, so
# multi-arch (amd64 + arm64) builds never fall back to QEMU.

ARG VERSION

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
# vite empties out/ on build; recreate out/bin so the Go embed (all:out/bin/*)
# has at least one file to match.
RUN mkdir -p /src/site/out/bin && touch /src/site/out/bin/.gitkeep

# --- Stage 2: patch + cross-compile the server binary -----------------------
FROM --platform=$BUILDPLATFORM docker.io/library/golang:1.26.4-bookworm AS build
ARG VERSION
ARG TARGETOS
ARG TARGETARCH
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
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
COPY --from=site /src/site/out ./site/out
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    version="${VERSION#v}" \
    && CGO_ENABLED=0 GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" \
       go build -tags embed -trimpath \
       -ldflags "-s -w -X github.com/coder/coder/v2/buildinfo.tag=${version}" \
       -o /opt/coder ./enterprise/cmd/coder

# --- Stage 3: assemble onto the upstream runtime base -----------------------
# Also grant cap_net_bind_service on the binary so the non-root (uid 1000)
# process can bind privileged ports (e.g. 80/443) directly, without running as
# root or relying on an external port-forwarder. libcap is kept in the final
# image so getcap can verify the capability (the Alpine base ships no
# python3/xattr reader for the test).
FROM ghcr.io/coder/coder:${VERSION}

USER root
COPY --from=build --chown=1000:1000 --chmod=755 /opt/coder /opt/coder
RUN apk add --no-cache libcap \
 && setcap cap_net_bind_service=+ep /opt/coder
USER 1000:1000

ENTRYPOINT [ "/opt/coder", "server" ]
