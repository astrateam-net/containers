# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

# astravaultnet — Infisical Networking (gateway OR relay) as a single,
# env-driven container. Thin wrapper over the official infisical/cli image,
# which is the leanest available building block: Alpine + tini (PID 1) + the
# statically linked `infisical` binary, published multi-arch (amd64/arm64) by
# Infisical themselves. We add nothing to the runtime except two POSIX shell
# scripts (all deps — sh, nc, pgrep — are already in busybox).
#
#   entrypoint.sh  — dispatch gateway|relay, resolve *_FILE secrets, env -> flags
#   healthcheck.sh — component-aware liveness (relay: TCP 2222; gateway: process)
#
# Default user is root (inherited from the base image). Relay ports 2222/8443
# are unprivileged, so no cap_net_bind_service / setcap is required.
# VERSION tracks infisical/cli via docker-bake.hcl (Renovate-managed).

ARG VERSION

FROM infisical/cli:${VERSION}

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh

# Relay inbound ports (informational). Gateway is outbound-only and needs none:
#   2222 — SSH reverse tunnel from gateways
#   8443 — platform-to-relay control channel
EXPOSE 2222 8443

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD ["/usr/local/bin/healthcheck.sh"]

# Base image already provides tini as PID 1 and /bin/infisical.
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]
