#!/usr/bin/env bash
# Launch `orca serve` from the unpacked Electron app, wiring flags from env.
# Defaults suit a Coder/reverse-proxy front: loopback bind + /trusted-session.
set -euo pipefail

APP=/opt/astraide/orca-ide

args=()
# Chromium's setuid sandbox can't initialize in most containers; --no-sandbox is
# the supported container path (it's a chromium flag, before the serve subcmd).
if [ "${ORCA_NO_SANDBOX:-true}" = "true" ]; then
  args+=(--no-sandbox)
fi

args+=(serve --port "${ORCA_PORT:-6768}")

# The address clients (and the trusted-session offer) advertise — set this to the
# Coder app URL / reachable host, or reconnects will dial 127.0.0.1.
if [ -n "${ORCA_PAIRING_ADDRESS:-}" ]; then
  args+=(--pairing-address "${ORCA_PAIRING_ADDRESS}")
fi

# Trusted-proxy mode: bind loopback only + serve the pairing offer at
# /trusted-session so a proxied browser connects with no URL token.
if [ "${ORCA_TRUSTED_PROXY:-true}" = "true" ]; then
  args+=(--trusted-proxy)
fi

if [ "${ORCA_JSON:-false}" = "true" ]; then
  args+=(--json)
fi

if [ "${ORCA_NO_PAIRING:-false}" = "true" ]; then
  args+=(--no-pairing)
fi

exec "${APP}" "${args[@]}"
