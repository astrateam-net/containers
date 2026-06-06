# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

# Authentik server with cap_net_bind_service granted on the binary, so the
# non-root (uid 1000) process can bind privileged ports (e.g. 80/443) directly
# without running as root or relying on an external port-forwarder.
#
# Thin overlay on the upstream image — VERSION is supplied by docker-bake.hcl.

ARG VERSION

FROM ghcr.io/goauthentik/server:${VERSION}

USER root
RUN apt-get update && apt-get install -y --no-install-recommends libcap2-bin \
 && setcap cap_net_bind_service+ep /usr/bin/authentik-server \
 && apt-get purge -y libcap2-bin && rm -rf /var/lib/apt/lists/*
USER 1000
