#!/bin/sh
# Docker / Swarm secrets support for astrawiki (upstream Docmost has none).
#
# For any env var named <NAME>_FILE, read the file it points at and export its
# contents as <NAME>, then hand off to the original command. This lets every
# secret — DATABASE_URL, APP_SECRET, REDIS_URL, OPENAI_API_KEY, GEMINI_API_KEY,
# TYPESENSE_API_KEY, SMTP_PASSWORD, AWS_S3_*, AZURE_STORAGE_ACCOUNT_KEY, … — be
# delivered via `docker secret` (mounted under /run/secrets) instead of a
# plaintext environment variable. A plain <NAME> (no _FILE) still works
# unchanged, so this is fully opt-in and backward compatible.
set -eu

# Discover *_FILE vars by name only (their values are file paths — single line,
# safe to parse from `env`; secret *contents* are read from the files, not here).
for fileVar in $(env | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*_FILE\)=.*/\1/p'); do
  target=${fileVar%_FILE}
  eval "path=\${$fileVar}"
  [ -n "${path:-}" ] || continue
  if [ ! -r "$path" ]; then
    echo "astrawiki: secret file for ${target} not readable: ${path}" >&2
    exit 1
  fi
  val=$(cat "$path")
  export "${target}=${val}"
  unset "$fileVar"
done

exec "$@"
