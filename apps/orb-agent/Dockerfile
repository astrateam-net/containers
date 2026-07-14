# syntax=docker/dockerfile:1

# orb-agent overlay: netboxlabs/orb-agent with two AstraTeam patches on top of the
# stock image; everything else is inherited untouched.
#   1. snmp-discovery (Go): a RouterOS-tolerant SNMP walk. The stock backend aborts
#      a device crawl on "OID not increasing" (RouterOS emits BRIDGE-MIB tables
#      unsorted); the patch tolerates that, like `snmpwalk -Cc`. We compile only the
#      patched backend from the pinned upstream tag and COPY it over the stock binary.
#   2. device-discovery (Python): LLDP-neighbour -> NetBox Cable discovery. RouterOS
#      `/ip neighbor` is parsed into point-to-point LLDP links and emitted as Diode
#      Cable entities. Additive modules + count-verified in-place patches applied to
#      the installed packages (see patch/apply_cables.py).

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

# --- device-discovery cable overlay: LLDP neighbours -> NetBox Cable ----------
# Additive modules (cable.py, _neighbors.py) + count-verified in-place patches to
# the INSTALLED device_discovery / custom_napalm packages. apply_cables.py fails
# the build on anchor drift, exactly like patch/apply.py does for the SNMP fix.
# Package dirs are resolved by importing them (no site-packages path assumption);
# the trailing import is a build-time smoke test of the whole wiring.
COPY overlay/device_discovery/cable.py /tmp/cable/device_discovery/cable.py
COPY overlay/custom_napalm/_neighbors.py /tmp/cable/custom_napalm/_neighbors.py
COPY patch/apply_cables.py /tmp/cable/apply_cables.py
RUN set -eux; \
    dd="$(python3 -c 'import device_discovery, os; print(os.path.dirname(device_discovery.__file__))')"; \
    cn="$(python3 -c 'import custom_napalm, os; print(os.path.dirname(custom_napalm.__file__))')"; \
    cp /tmp/cable/device_discovery/cable.py "$dd/cable.py"; \
    cp /tmp/cable/custom_napalm/_neighbors.py "$cn/_neighbors.py"; \
    python3 /tmp/cable/apply_cables.py "$dd" "$cn"; \
    python3 -c "import custom_napalm.mikrotik_routeros, device_discovery.cable, device_discovery.translate, device_discovery.policy.runner, device_discovery.policy.models"; \
    rm -rf /tmp/cable "$dd/__pycache__" "$dd/policy/__pycache__" "$cn/__pycache__"

LABEL org.opencontainers.image.title="orb-agent" \
      org.opencontainers.image.description="netboxlabs/orb-agent with a RouterOS-tolerant SNMP walk (snmp-discovery, snmpwalk -Cc) + LLDP-neighbour NetBox Cable discovery (device-discovery)" \
      org.opencontainers.image.vendor="astrateam-net" \
      org.opencontainers.image.version="${VERSION}"

# Entrypoint, user, and all other backends inherited from the base image.
