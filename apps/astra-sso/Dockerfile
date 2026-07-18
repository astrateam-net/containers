# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom


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
