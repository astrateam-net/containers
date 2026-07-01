#!/bin/sh
# astrai18n entrypoint: bring Docker/Swarm file-secret support to the stock image,
# then hand off to the upstream launcher unchanged.
#
# The JVM still reads JAVA_TOOL_OPTIONS (our javaagent) and /app/cmd.sh still applies
# its OTEL/arch logic — we only resolve <VAR>_FILE secrets into the environment first.
set -eu

# shellcheck source=/dev/null  # resolved at runtime inside the image
. /app/astrai18n-file-secrets.sh
expand_file_secrets

exec /app/cmd.sh "$@"
