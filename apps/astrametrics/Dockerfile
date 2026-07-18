# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom
ARG VERSION

FROM grafana/enterprise-metrics:${VERSION} AS upstream

FROM --platform=$BUILDPLATFORM python:3.13-alpine AS patcher
RUN pip install --no-cache-dir cryptography
WORKDIR /w
COPY agent.py keys/astragraf_public.pem ./
COPY --from=upstream /usr/bin/enterprise-metrics ./bin.in
RUN python agent.py ./bin.in ./astragraf_public.pem ./bin.out

FROM grafana/enterprise-metrics:${VERSION}
COPY --from=patcher --chmod=0755 /w/bin.out /usr/bin/enterprise-metrics
