# syntax=docker/dockerfile:1

ARG VERSION
FROM docker.io/ghost:${VERSION}

RUN apk add --no-cache \
      git \
      openssh-client \
      ca-certificates