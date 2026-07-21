# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom,FromPlatformFlagConstDisallowed
ARG VERSION

FROM --platform=linux/amd64 quay.io/minio/aistor/minio:${VERSION} AS upstream

FROM --platform=$BUILDPLATFORM python:3.13-alpine AS builder
WORKDIR /w
COPY agent.py ./
COPY --from=upstream /usr/bin/minio ./minio.in
RUN python agent.py minio.in minio.out

FROM --platform=linux/amd64 quay.io/minio/aistor/minio:${VERSION}
COPY --from=builder --chmod=755 /w/minio.out /usr/bin/minio
