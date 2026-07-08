# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

# n8n with Enterprise opened via the agent (License.isLicensed -> true), which
# unlocks all Enterprise features (SSO, variables/environments, source control, …).
# Named astraflow, not n8n, because it patches licensing. VERSION from docker-bake.hcl.
# The agent throws if upstream moves the license gate, failing the build loudly.

ARG VERSION

FROM docker.io/n8nio/n8n:${VERSION}

USER root
COPY agent /tmp/agent
RUN node /tmp/agent && rm -f /tmp/agent
USER node
