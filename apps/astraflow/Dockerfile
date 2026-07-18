# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG VERSION

FROM docker.io/n8nio/n8n:${VERSION}

USER root
COPY agent /tmp/agent
RUN node /tmp/agent && rm -f /tmp/agent
USER node
