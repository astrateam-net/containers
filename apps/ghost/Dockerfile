# syntax=docker/dockerfile:1

ARG VERSION
FROM docker.io/ghost:${VERSION}

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      git \
      openssh-client \
      ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*