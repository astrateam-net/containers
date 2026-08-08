# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG VERSION

FROM ghcr.io/berriai/litellm:${VERSION}

COPY selftest.py /tmp/astrallm-selftest.py
COPY keys/astrallm-public.pem /tmp/astrallm-public.pem

RUN set -eu; \
    python /tmp/astrallm-selftest.py; \
    PEM="$(python -c 'import os,litellm.proxy.auth.litellm_license as m; print(os.path.join(os.path.dirname(m.__file__), "public_key.pem"))')"; \
    cp /tmp/astrallm-public.pem "$PEM"; \
    rm -f /tmp/astrallm-selftest.py /tmp/astrallm-public.pem
