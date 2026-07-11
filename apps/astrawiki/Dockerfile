# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

# Docmost with Enterprise opened via the agent (LicenseService -> enterprise),
# which unlocks all EE features (SSO/SAML/OIDC/LDAP, SCIM, MFA, audit logs,
# retention, API keys, page permissions, AI, imports, personal spaces, …).
# Named astrawiki, not docmost, because it patches licensing. VERSION from
# docker-bake.hcl. The agent throws if upstream moves the license gate, failing
# the build loudly. No license key is required at runtime.

ARG VERSION

FROM docmost/docmost:${VERSION}

USER root
COPY agent /tmp/agent
RUN node /tmp/agent && rm -f /tmp/agent

# Docker/Swarm secrets: resolve any <NAME>_FILE env var from its file before
# starting. Upstream Docmost only reads plaintext env vars; this adds *_FILE
# support without touching how the app reads config. ENTRYPOINT clears the
# base image's CMD, so re-declare it.
COPY entrypoint.sh /usr/local/bin/astrawiki-entrypoint.sh
RUN chmod +x /usr/local/bin/astrawiki-entrypoint.sh
USER node

ENTRYPOINT ["/usr/local/bin/astrawiki-entrypoint.sh"]
CMD ["pnpm", "start"]
