# syntax=docker/dockerfile:1

# orb-agent overlay: netboxlabs/orb-agent with a RouterOS-tolerant SNMP walk.
# We compile only the patched snmp-discovery backend from the pinned upstream tag
# and COPY it over the stock binary; everything else is inherited untouched.
# The stock backend aborts a device crawl on "OID not increasing" (RouterOS emits
# BRIDGE-MIB tables unsorted); the patch tolerates that, like `snmpwalk -Cc`.

# VERSION == base image tag == upstream source tag. Renovate bumps VERSION;
# docker-bake derives ORB_REF="v${VERSION}".
ARG VERSION=2.11.0
ARG ORB_REF=v2.11.0
ARG GO_VERSION=1.26
ARG BASE_IMAGE=docker.io/netboxlabs/orb-agent

# ---- builder: patched snmp-discovery from pinned upstream --------------------
FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-trixie AS snmp-build

RUN apt-get update \
 && apt-get install --yes --no-install-recommends git python3 ca-certificates \
 && rm -rf /var/lib/apt/lists/*

ARG ORB_REPO=https://github.com/netboxlabs/orb-agent.git
ARG ORB_REF
WORKDIR /src
RUN git init -q . \
 && git remote add origin "${ORB_REPO}" \
 && git fetch --depth 1 origin "refs/tags/${ORB_REF}" \
 && git checkout -q FETCH_HEAD

WORKDIR /src/orb-discovery/snmp-discovery

# Set gosnmp's AppOpts["c"] before the stock WalkAll (== snmpwalk -Cc). apply.py
# fails the build if the upstream anchor drifted (no silent no-op patch).
COPY patch/apply.py /tmp/apply.py
RUN python3 /tmp/apply.py

ARG TARGETOS TARGETARCH
ARG VERSION
ARG BUILD_COMMIT=astra
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg \
    printf '%s+astra-routeros-tolerant\n' "${VERSION}" > version/BUILD_VERSION.txt \
 && printf '%s\n' "${BUILD_COMMIT}" > version/BUILD_COMMIT.txt \
 && CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -ldflags="-s -w" -trimpath -o /out/snmp-discovery ./cmd/main.go

# ---- final: stock agent image, our snmp-discovery swapped in ----------------
FROM ${BASE_IMAGE}:${VERSION}

ARG VERSION
COPY --from=snmp-build /out/snmp-discovery /usr/local/bin/snmp-discovery

LABEL org.opencontainers.image.title="orb-agent" \
      org.opencontainers.image.description="netboxlabs/orb-agent with a RouterOS-tolerant SNMP walk (snmp-discovery ignores non-increasing OIDs, à la snmpwalk -Cc)" \
      org.opencontainers.image.vendor="astrateam-net" \
      org.opencontainers.image.version="${VERSION}"

# Entrypoint, user, and all other backends inherited from the base image.
