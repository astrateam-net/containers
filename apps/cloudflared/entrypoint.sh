#!/busybox sh
set -e

CONFIG_FILE=""
if [ -f /etc/cloudflared/config.yaml ]; then
  CONFIG_FILE="/etc/cloudflared/config.yaml"
elif [ -f /etc/cloudflared/config.yml ]; then
  CONFIG_FILE="/etc/cloudflared/config.yml"
fi

RELEVANT_ENVS=""
for var in $(env | /busybox grep -E '^(HOSTNAME_|CLOUDFLARE_TUNNEL_ID)' | /busybox cut -d= -f1); do
  RELEVANT_ENVS="$RELEVANT_ENVS $var"
done

if [ -n "$CONFIG_FILE" ] && [ -n "$RELEVANT_ENVS" ]; then
  export $RELEVANT_ENVS
  /busybox envsubst < "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
  mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
fi

exec cloudflared "$@"