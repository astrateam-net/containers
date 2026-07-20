# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom
ARG VERSION

FROM docker.io/llamaindex/llamacloud-backend:${VERSION} AS upstream

FROM --platform=$BUILDPLATFORM python:3.13-alpine AS patcher
WORKDIR /w
COPY patch.py keys/astrarag_public.pem ./
COPY --from=upstream /app/src/app/license/license_public_key.pub ./app.in
COPY --from=upstream /app/src/usage/license/license_public_key.pub ./usage.in
RUN python patch.py astrarag_public.pem app.in app.out \
 && python patch.py astrarag_public.pem usage.in usage.out

FROM docker.io/llamaindex/llamacloud-backend:${VERSION}
COPY --from=patcher /w/app.out   /app/src/app/license/license_public_key.pub
COPY --from=patcher /w/usage.out /app/src/usage/license/license_public_key.pub
