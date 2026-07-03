# syntax=docker/dockerfile:1
# Gerbil + Traefik in a single s6-supervised image.
#
# WHY THIS EXISTS
# Pangolin's reference topology runs Traefik with `network_mode: service:gerbil`
# so Traefik shares Gerbil's network namespace and can reach the WireGuard `wg0`
# interface Gerbil creates (Traefik's upstreams for tunnelled resources are IPs
# that only exist on wg0). Docker Swarm has no `network_mode: service:`
# equivalent, so the only way to preserve that shared namespace is to run both
# processes inside ONE container. s6-overlay supervises the two longruns.
#
# Pangolin itself stays a SEPARATE service: it talks over the network by DNS
# name (http://pangolin:3001) and never needed the shared namespace. Keep this
# image's Swarm service named `gerbil` so `gerbil:3004` / `gerbil:8080` and
# Gerbil's `--reachableAt` keep resolving for the rest of the stack.

ARG VERSION=1.4.2
ARG TRAEFIK_VERSION=v3.6.22

# Traefik ships a static, CGO-free binary — lift it straight out of the
# official image.
FROM traefik:${TRAEFIK_VERSION} AS traefik

# Base = Gerbil's own image (Alpine + iptables/iproute2 already present, which
# the Traefik binary has no problem running on). No Node here — Pangolin is
# external.
FROM ghcr.io/fosrl/gerbil:${VERSION} AS runner

ARG TARGETARCH
ARG S6_OVERLAY_VERSION=3.2.3.0

# ca-certificates: Traefik ACME + badger plugin fetch over HTTPS.
# xz: busybox tar needs it to unpack the s6-overlay tarballs.
RUN apk add --no-cache ca-certificates xz

# Traefik binary from the stage above.
COPY --from=traefik /usr/local/bin/traefik /usr/local/bin/traefik

# s6-overlay v3 (arch-mapped from Docker's TARGETARCH so image-all can build
# both linux/amd64 and linux/arm64).
RUN set -eu; \
    case "${TARGETARCH}" in \
      amd64) S6_ARCH=x86_64 ;; \
      arm64) S6_ARCH=aarch64 ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    wget -qO /tmp/s6-noarch.tar.xz "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz"; \
    wget -qO /tmp/s6-arch.tar.xz  "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz"; \
    tar -C / -Jxpf /tmp/s6-noarch.tar.xz; \
    tar -C / -Jxpf /tmp/s6-arch.tar.xz; \
    rm /tmp/s6-*.tar.xz; \
    ln -s /run /var/run

COPY rootfs /
RUN chmod +x \
      /etc/s6-overlay/s6-rc.d/gerbil/run \
      /etc/s6-overlay/s6-rc.d/traefik/run \
      /usr/bin/healthcheck.sh

# Gerbil is configured by its native env vars (precedence: env > flag > default).
# These three are the only essentials; they match the reference stack's compose
# command. Override any Gerbil option — MTU, LOG_LEVEL, SNI_PORT, PROXY_PROTOCOL,
# INTERFACE, ... — by setting its documented env var on the service. Traefik keeps
# its own env (e.g. CLOUDFLARE_DNS_API_TOKEN) plus its mounted config /etc/traefik.
ENV REMOTE_CONFIG=http://pangolin:3001/api/v1/ \
    REACHABLE_AT=http://gerbil:3004 \
    GENERATE_AND_SAVE_KEY_TO=/var/config/key

# Ports that land on this container's netns:
#   80/443     -> Traefik (HTTP/HTTPS ingress)
#   3004       -> Gerbil HTTP API (Pangolin pushes peers here via --reachableAt)
#   8080       -> Traefik API (referenced as gerbil:8080 by middleware-manager)
#   51820/udp  -> Gerbil WireGuard
#   21820/udp  -> Gerbil relay / NAT hole-punch
EXPOSE 80 443 3004 8080 51820/udp 21820/udp

# Gerbil persists its generated WireGuard private key here (matches the
# reference stack's /var/config mount).
VOLUME /var/config

HEALTHCHECK --interval=10s --timeout=5s CMD /usr/bin/healthcheck.sh

ENTRYPOINT ["/init"]
