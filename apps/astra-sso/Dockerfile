# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

# authentik server with two overlays on the stock upstream image:
#   1. cap_net_bind_service on the binary, so uid 1000 can bind 80/443 directly.
#   2. Enterprise fix (agent), opening all Enterprise features.
# Named astra-sso, not authentik, because it patches licensing. VERSION from docker-bake.hcl.
# ee fix asserts on its anchors, so the build fails if upstream moves the license gate.

ARG VERSION

FROM ghcr.io/goauthentik/server:${VERSION}

USER root

# 1. privileged-port bind capability
RUN apt-get update && apt-get install -y --no-install-recommends libcap2-bin \
 && setcap cap_net_bind_service+ep /usr/bin/authentik-server \
 && apt-get purge -y libcap2-bin && rm -rf /var/lib/apt/lists/*

# 2. Enterprise fix
COPY agent /tmp/agent
RUN python3 /tmp/agent \
 && rm -f /tmp/agent /authentik/enterprise/__pycache__/license*.pyc

USER 1000
