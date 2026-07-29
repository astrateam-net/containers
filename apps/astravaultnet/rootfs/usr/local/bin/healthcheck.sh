#!/bin/sh
# Healthy only when every role named in ASTRAVAULT_NET is up. Roles that were
# not selected took themselves down at start and are not checked.
#
#   gateway     -> supervised and up. It is outbound-only (an SSH reverse tunnel
#                  to a relay), so there is no local port to probe.
#   relay       -> up, plus a TCP connect to the SSH listener gateways dial.
#   agent-proxy -> up, plus a TCP connect to the forward-proxy port. It binds
#                  only after authenticating and having its intermediate CA
#                  signed, so the connect covers the whole startup path.
set -eu
. /usr/local/lib/astravaultnet/common.sh

svc_up() {
  /package/admin/s6/command/s6-svstat "/run/s6-rc/servicedirs/$1" 2>/dev/null | grep -q '^up'
}

roles=$(av_roles)
[ -n "$roles" ] || exit 1

for role in $roles; do
  svc_up "$role" || exit 1
  case "$role" in
    relay)       nc -z 127.0.0.1 "${ASTRAVAULT_RELAY_SSH_PORT:-2222}" >/dev/null 2>&1 || exit 1 ;;
    agent-proxy) nc -z 127.0.0.1 "${ASTRAVAULT_PROXY_PORT:-17322}"    >/dev/null 2>&1 || exit 1 ;;
  esac
done
