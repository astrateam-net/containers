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

# A gateway dials a relay: they are the two ends of one tunnel, so pairing them
# in a single container is always a mistake. The agent proxy is orthogonal and
# pairs with either. Valid: gateway | relay | agent-proxy | gateway,agent-proxy
# | relay,agent-proxy.
if av_role_enabled gateway && av_role_enabled relay; then
  echo "astravaultnet: ERROR: gateway and relay cannot share a container — a gateway dials a relay. Run one of them, optionally alongside agent-proxy" >&2
  exit 1
fi

echo "astravaultnet: roles: $roles" >&2
