# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG VERSION

FROM rasa/studio-backend:${VERSION}

USER root
COPY keys/astratalk-public.pem /tmp/agent-assets/public.pem
COPY agent /tmp/agent
RUN /tmp/agent && rm -rf /tmp/agent /tmp/agent-assets
USER 1001
