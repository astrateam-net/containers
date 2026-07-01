#!/bin/sh
# astravault entrypoint: bring Docker/Swarm file-secret support to the stock image,
# then hand off to the upstream launcher unchanged.
#
# The upstream standalone-entrypoint.sh still runs update-ca-certificates and execs
# `node dist/main.mjs` — we only resolve <VAR>_FILE secrets into the environment first.
set -eu

# shellcheck source=/dev/null  # resolved at runtime inside the image
. /backend/astravault-file-secrets.sh
expand_file_secrets

exec /backend/standalone-entrypoint.sh "$@"
