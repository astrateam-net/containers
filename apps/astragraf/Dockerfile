# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

# Grafana Enterprise with the license trust-root swapped to ours: agent.py rewrites
# the kid=1 verification key in the binary to our public key, so tokens we sign
# (token.py) validate against 100% stock Grafana code - status=Valid, edition=
# Enterprise, all features. Named astragraf, not grafana, because it patches
# licensing. VERSION comes from docker-bake.hcl.
#
# The env-only path (GF_ENTERPRISE_LICENSE_VALIDATION_KEY) is AWS-Marketplace-only
# and cannot inject an arbitrary trust key, so the key is baked in at build time.
# agent.py asserts its anchors - the build fails if upstream moves the trust root.

ARG VERSION

# Source of the target-arch enterprise binary (defaults to $TARGETPLATFORM).
FROM grafana/grafana-enterprise:${VERSION} AS upstream

# Patch on the BUILD arch (native, no emulation) - the rewrite is byte-level and
# arch-independent, so build-arch python edits the target-arch binary correctly.
FROM --platform=$BUILDPLATFORM python:3.13-alpine AS patcher
RUN pip install --no-cache-dir cryptography
WORKDIR /w
COPY agent.py keys/astragraf_public.pem ./
COPY --from=upstream /usr/share/grafana/bin/grafana ./grafana.in
RUN python agent.py ./grafana.in ./astragraf_public.pem ./grafana.out

FROM grafana/grafana-enterprise:${VERSION}
# --chmod restores the executable bit (agent.py writes 0644).
COPY --from=patcher --chmod=0755 /w/grafana.out /usr/share/grafana/bin/grafana
