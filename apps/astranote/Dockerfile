# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

# AFFiNE with self-host Team opened via the agent (EntitlementService -> selfhost_team),
# which unlocks Team-workspace features and quotas (team workspaces, effectively
# unlimited members/storage, 500MB blob limit) with NO licence key. Named astranote,
# not affine, because it patches entitlements. VERSION from docker-bake.hcl. The agent
# throws if upstream moves the entitlement seam, failing the build loudly.

ARG VERSION

FROM ghcr.io/toeverything/affine:${VERSION}

USER root
COPY agent /tmp/agent
RUN node /tmp/agent && rm -f /tmp/agent
# Base image runs as root with docker-entrypoint.sh + CMD ["node","./dist/main.js"];
# leave both untouched.
