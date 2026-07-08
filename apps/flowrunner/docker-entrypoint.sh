#!/bin/sh
# Bridge *_FILE secrets into their plain env vars, then hand off to CMD.
#
# The stock n8nio/runners image — unlike the main n8n image — does NOT resolve
# the *_FILE convention, so docker/1Password secrets can't be file-mounted (the
# launcher reads N8N_RUNNERS_AUTH_TOKEN from plain env only). For each FOO_FILE
# we export FOO from the file's contents. Idempotent: an already-set FOO wins.
set -eu

for file_var in $(env | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*_FILE\)=.*/\1/p'); do
  base_var=${file_var%_FILE}

  # Don't clobber a value that was passed directly.
  if [ -n "$(printenv "$base_var" 2>/dev/null || true)" ]; then
    continue
  fi

  file_path=$(printenv "$file_var")
  if [ -n "$file_path" ] && [ -f "$file_path" ]; then
    export "${base_var}=$(cat "$file_path")"
    unset "$file_var"
  fi
done

exec "$@"
