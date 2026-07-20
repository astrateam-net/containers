# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom
ARG VERSION

FROM docker.io/llamaindex/llamacloud-llamaparse-ocr:${VERSION} AS upstream

FROM --platform=$BUILDPLATFORM python:3.13-alpine AS patcher
WORKDIR /w
COPY patch.py keys/astrarag_public.pem ./
COPY --from=upstream /home/user/app/license_public_key.pub ./v1.in
COPY --from=upstream /opt/pysetup/app/.venv/lib/python3.11/site-packages/ocrpaddle/utils/license_public_key.pub ./v2.in
RUN python patch.py astrarag_public.pem v1.in v1.out \
 && python patch.py astrarag_public.pem v2.in v2.out

FROM docker.io/llamaindex/llamacloud-llamaparse-ocr:${VERSION}
COPY --from=patcher /w/v1.out /home/user/app/license_public_key.pub
COPY --from=patcher /w/v2.out /opt/pysetup/app/.venv/lib/python3.11/site-packages/ocrpaddle/utils/license_public_key.pub
