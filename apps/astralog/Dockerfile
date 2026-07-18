# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

# Grafana Enterprise Logs (GEL) with the license trust-root swapped to ours:
# agent.py rewrites the kid=1 verification key in the binary to our public key,
# so the license we sign (tokens.py) validates against 100% stock GEL code -
# "found a valid license", management API live, all enterprise features. Named
# astralog, not enterprise-logs, because it patches licensing. VERSION comes from
# docker-bake.hcl.
#
# GEL ships the SAME grafana/backend-enterprise-libs licensing library as Grafana
# Enterprise (apps/astragraf) - the kid=1 RSA-4096 signing key is byte-identical,
# so agent.py and the reused astragraf public key patch the GEL binary unchanged.
# The base image is DISTROLESS (no shell) - structural verification is done with
# container-structure-test fileContentTests (see tests.yaml), not in-container grep.
# agent.py asserts its anchors - the build fails if upstream moves the trust root.

ARG VERSION

# Source of the target-arch enterprise-logs binary (defaults to $TARGETPLATFORM).
FROM grafana/enterprise-logs:${VERSION} AS upstream

# Patch on the BUILD arch (native, no emulation) - the rewrite is byte-level and
# arch-independent, so build-arch python edits the target-arch binary correctly.
FROM --platform=$BUILDPLATFORM python:3.13-alpine AS patcher
RUN pip install --no-cache-dir cryptography
WORKDIR /w
COPY agent.py keys/astragraf_public.pem ./
COPY --from=upstream /usr/bin/enterprise-logs ./enterprise-logs.in
RUN python agent.py ./enterprise-logs.in ./astragraf_public.pem ./enterprise-logs.out

FROM grafana/enterprise-logs:${VERSION}
# --chmod restores the executable bit (agent.py writes 0644); the distroless image
# runs the binary as its entrypoint, so it must stay executable.
COPY --from=patcher --chmod=0755 /w/enterprise-logs.out /usr/bin/enterprise-logs
