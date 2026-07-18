# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom
ARG VERSION

FROM ghcr.io/toeverything/affine:${VERSION}

USER root
COPY agent /tmp/agent
RUN node /tmp/agent && rm -f /tmp/agent
