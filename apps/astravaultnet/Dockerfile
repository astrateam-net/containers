# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

# astravaultnet — Infisical Networking as a single, env-driven container:
# gateway, relay and agent proxy, in any combination.
#
# WHY S6
# All three roles are subcommands of the same `infisical` binary, but each is
# its own long-running foreground process, so running more than one in a
# container needs a supervisor. That is the whole reason s6-overlay is here:
# ASTRAVAULT_NET is a LIST, each role is an s6 longrun, and a role that is not
# in the list takes itself down at start instead of flapping. The agent proxy is
# the only role that pairs: it only listens (17322) while a gateway only dials
# out, so gateway,agent-proxy and relay,agent-proxy are valid — e.g. a
# node-pinned gateway that also serves as one of the agent proxy replicas. A
# gateway dials a relay, so that pairing is rejected at startup.
#
# Base is the official infisical/cli image: Alpine + the statically linked
# `infisical` binary, published multi-arch (amd64/arm64) by Infisical.
#
#   rootfs/etc/s6-overlay/...     — one longrun per role + a validating oneshot
#   usr/local/lib/.../common.sh   — role list, *_FILE secrets, role-scoped env
#   usr/local/bin/healthcheck.sh  — every selected role up (and listening)
#
# Default user is root (inherited from the base). Every listening port is
# unprivileged, so no cap_net_bind_service / setcap is required.
# VERSION tracks infisical/cli via docker-bake.hcl (Renovate-managed).

ARG VERSION

FROM infisical/cli:${VERSION}

ARG TARGETARCH
ARG S6_OVERLAY_VERSION

# xz: busybox tar needs it to unpack the s6-overlay tarballs.
RUN apk add --no-cache xz

# s6-overlay v3 (arch-mapped from Docker's TARGETARCH so image-all can build
# both linux/amd64 and linux/arm64).
RUN set -eu; \
    case "${TARGETARCH}" in \
      amd64) S6_ARCH=x86_64 ;; \
      arm64) S6_ARCH=aarch64 ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    wget -qO /tmp/s6-noarch.tar.xz "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz"; \
    wget -qO /tmp/s6-arch.tar.xz   "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz"; \
    tar -C / -Jxpf /tmp/s6-noarch.tar.xz; \
    tar -C / -Jxpf /tmp/s6-arch.tar.xz; \
    rm /tmp/s6-*.tar.xz

COPY rootfs /
RUN chmod +x \
      /etc/s6-overlay/s6-rc.d/gateway/run \
      /etc/s6-overlay/s6-rc.d/relay/run \
      /etc/s6-overlay/s6-rc.d/agent-proxy/run \
      /usr/local/bin/astravault-init.sh \
      /usr/local/bin/healthcheck.sh

# A typo in ASTRAVAULT_NET must kill the container, not leave it idling with
# every role silently disabled — the init oneshot rejects unknown roles.
ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2

# Inbound ports (informational). Gateway is outbound-only and needs none:
#   2222  — relay: SSH reverse tunnel from gateways
#   8443  — relay: platform-to-relay control channel
#  17322  — agent proxy: HTTP(S) forward proxy for agents
EXPOSE 2222 8443 17322

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD ["/usr/local/bin/healthcheck.sh"]

ENTRYPOINT ["/init"]
