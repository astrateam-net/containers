# syntax=docker/dockerfile:1

ARG VERSION
FROM ghcr.io/paperless-ngx/paperless-ngx:${VERSION}
USER root
RUN apt-get update && apt-get install -y \
    tesseract-ocr-rus \
    && rm -rf /var/lib/apt/lists/*
USER 1000
