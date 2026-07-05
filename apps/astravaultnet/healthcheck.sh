#!/bin/sh
# Component-aware container healthcheck.
#
#   relay   -> the relay binds a local SSH listener (2222) for gateway tunnels
#              and a TLS control port (8443). A successful TCP connect to the
#              SSH port means the relay is up and serving.
#   gateway -> the gateway is outbound-only (it opens an SSH reverse tunnel to a
#              relay and never listens locally), so there is no port to probe.
#              The best local signal is that the infisical process is alive.
#              A hard crash already exits the container (tini is PID 1); this
#              catches a hung/zombie process.
#
# Uses only busybox applets (nc, pgrep) already present in the base image.
set -eu

role=$(printf '%s' "${ASTRAVAULT_NET:-}" | tr '[:upper:]' '[:lower:]')

case "$role" in
  relay)
    port=${ASTRAVAULT_RELAY_SSH_PORT:-2222}
    nc -z 127.0.0.1 "$port" >/dev/null 2>&1 || exit 1
    ;;
  *)
    # gateway (default): process liveness
    pgrep infisical >/dev/null 2>&1 || exit 1
    ;;
esac

exit 0
