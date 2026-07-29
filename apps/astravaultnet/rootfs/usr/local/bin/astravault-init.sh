#!/bin/sh
# Validate the role list once, before any longrun starts. An unknown role is a
# typo that would otherwise show up as three silently-disabled services and a
# container that does nothing, so fail the container here instead
# (S6_BEHAVIOUR_IF_STAGE2_FAILS=2).
#
# Invoked from the init-astravault oneshot, whose `up` file is execline and so
# cannot hold shell itself.
set -eu
. /usr/local/lib/astravaultnet/common.sh

roles=$(av_roles)

if [ -z "$roles" ]; then
  echo "astravaultnet: ASTRAVAULT_NET is empty — no role will start (set gateway, relay and/or agent-proxy)" >&2
  exit 0
fi

for r in $roles; do
  case "$r" in
    gateway | relay | agent-proxy) ;;
    *)
      echo "astravaultnet: ERROR: unknown role '$r' in ASTRAVAULT_NET (expected gateway, relay or agent-proxy)" >&2
      exit 1
      ;;
  esac
done

echo "astravaultnet: roles: $roles" >&2
