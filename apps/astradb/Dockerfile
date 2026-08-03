# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG VERSION

FROM dbeaver/cloudbeaver-ee:${VERSION}

COPY keys/astradb-public.key /tmp/agent-assets/public.key
COPY agent /tmp/agent
RUN /tmp/agent && rm -rf /tmp/agent /tmp/agent-assets

ENV CLOUDBEAVER_RESTRICT_EXTERNAL_SERVICES_INVOCATION=true
