# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG VERSION

FROM docker.io/langchain/agent-builder-deep-agent:${VERSION}

COPY keys/astrascope-public.pem /tmp/astrascope-public.pem
COPY selftest.py /tmp/astrascope-selftest.py

USER root
RUN python3 /tmp/astrascope-selftest.py \
    && rm -f /tmp/astrascope-selftest.py /tmp/astrascope-public.pem
USER 1000
