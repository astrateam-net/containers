# syntax=docker/dockerfile:1

ARG VERSION
FROM docker.io/cloudflare/cloudflared:${VERSION}

USER root

# Install envsubst (from gettext)
RUN apt-get update && apt-get install -y gettext && rm -rf /var/lib/apt/lists/*

# Add entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER 65532:65532

ENTRYPOINT ["/entrypoint.sh"]
CMD ["tunnel", "--no-autoupdate"]