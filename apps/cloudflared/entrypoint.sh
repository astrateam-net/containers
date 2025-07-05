#!/bin/sh
set -e

# Find config file (yaml or yml)
CONFIG_FILE=""
if [ -f /etc/cloudflared/config.yaml ]; then
  CONFIG_FILE="/etc/cloudflared/config.yaml"
elif [ -f /etc/cloudflared/config.yml ]; then
  CONFIG_FILE="/etc/cloudflared/config.yml"
fi

# Gather relevant env vars
RELEVANT_ENVS=""
for var in $(env | grep -E '^(HOSTNAME_|CLOUDFLARE_TUNNEL_ID)' | cut -d= -f1); do
  RELEVANT_ENVS="$RELEVANT_ENVS $var"
done

# Only substitute if config file exists and at least one relevant env is set
if [ -n "$CONFIG_FILE" ] && [ -n "$RELEVANT_ENVS" ]; then
  # Export only the relevant envs for envsubst
  export $RELEVANT_ENVS
  envsubst < "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
  mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
fi

# Exec cloudflared with all arguments
exec cloudflared "$@"
