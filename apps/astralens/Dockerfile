# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom
ARG VERSION

FROM docker.io/llamaindex/llamacloud-layout-detection-api:${VERSION} AS upstream

FROM --platform=$BUILDPLATFORM python:3.13-alpine AS patcher
WORKDIR /w
COPY patch.py keys/astrarag_public.pem ./
COPY --from=upstream /app/license_public_key.pub ./k.in
RUN python patch.py astrarag_public.pem k.in k.out

FROM docker.io/llamaindex/llamacloud-layout-detection-api:${VERSION}
COPY --from=patcher /w/k.out /app/license_public_key.pub
