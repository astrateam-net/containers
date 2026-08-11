# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG VERSION

FROM docker.io/langchain/langsmith-backend:${VERSION}

COPY --chown=1000:1000 keys/astrascope-public.pem /tmp/astrascope-public.pem
COPY --chown=1000:1000 selftest.py /tmp/astrascope-selftest.py

RUN python3.11 /tmp/astrascope-selftest.py \
    && rm -f /tmp/astrascope-selftest.py /tmp/astrascope-public.pem
