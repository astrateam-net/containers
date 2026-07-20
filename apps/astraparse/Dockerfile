# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom
ARG VERSION

FROM docker.io/llamaindex/llamacloud-llamaparse:${VERSION} AS upstream

FROM --platform=$BUILDPLATFORM python:3.13-alpine AS patcher
WORKDIR /w
COPY patch.py keys/astrarag_public.pem ./
COPY --from=upstream /home/node/dist/worker/license/license.js ./license.js.in
RUN python patch.py astrarag_public.pem license.js.in license.js.out

FROM docker.io/llamaindex/llamacloud-llamaparse:${VERSION}
COPY --from=patcher --chown=node:node /w/license.js.out /home/node/dist/worker/license/license.js
