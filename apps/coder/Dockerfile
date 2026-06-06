# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

# Coder server with cap_net_bind_service granted on the binary, so the
# non-root (uid 1000) process can bind privileged ports (e.g. 80/443) directly
# without running as root or relying on an external port-forwarder.
#
# Thin overlay on the upstream (Alpine) image — VERSION is supplied by
# docker-bake.hcl. libcap is kept in the final image so getcap can verify the
# capability (the Alpine base ships no python3/xattr reader for the test).

ARG VERSION

FROM ghcr.io/coder/coder:${VERSION}

USER root
RUN apk add --no-cache libcap \
 && setcap cap_net_bind_service=+ep /opt/coder
USER 1000:1000
