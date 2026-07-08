# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

# n8n task runners (external mode) with *_FILE secret support added. The stock
# n8nio/runners image — unlike the main n8n image — ignores the *_FILE
# convention, so docker/1Password secrets can't be file-mounted (the launcher
# reads N8N_RUNNERS_AUTH_TOKEN from plain env only). Our entrypoint bridges each
# FOO_FILE -> FOO, then exec's the original tini + launcher (carried in CMD).
# VERSION from docker-bake.hcl and MUST match the astraflow (n8nio/n8n) version
# deployed alongside it — the runner protocol is version-locked to the broker.

ARG VERSION

FROM docker.io/n8nio/runners:${VERSION}

USER root
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod 0755 /docker-entrypoint.sh
USER runner

# Bridge runs first, then hands off to the stock entrypoint/cmd via exec "$@".
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["/sbin/tini", "--", "/usr/local/bin/task-runner-launcher", "javascript", "python"]
