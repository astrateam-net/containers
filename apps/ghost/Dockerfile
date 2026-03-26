# syntax=docker/dockerfile:1

ARG VERSION=6.23.0
FROM docker.io/ghost:${VERSION}

RUN apt-get update -qq \
    && apt-get install -y -qq --no-install-recommends \
        ca-certificates \
        git \
        openssh-client \
    && rm -rf /var/lib/apt/lists/*
