#!/bin/sh
# File-secret expansion for the upstream image, which has no native support for it.
#
# expand_file_secrets: for every environment variable named <VAR>_FILE, read the
# file it points to and export <VAR> with the file's contents (trailing newlines
# stripped, so tokens stay intact). This lets any sensitive setting — the database
# password (DB_PASSWORD_FILE), the auth/encryption secrets (AUTH_SECRET_FILE,
# ENCRYPTION_KEY_FILE), integration keys, ... — be delivered as a Docker/Swarm
# secret mounted at /run/secrets/<name> instead of a plaintext environment value.
#
# Sourced by the entrypoint; kept standalone (no side effects on load) so it can be
# sourced and exercised on its own in tests.
expand_file_secrets() {
  # Enumerate real variable names via awk's ENVIRON, so a multi-line value that
  # happens to contain a line like "X_FILE=..." cannot be mistaken for a variable.
  # Names are whitespace-free, so word-splitting the awk output is safe (SC2013).
  # shellcheck disable=SC2013
  for _file_var in $(awk 'BEGIN { for (v in ENVIRON) if (v ~ /_FILE$/) print v }'); do
    _var="${_file_var%_FILE}"
    eval "_path=\${$_file_var}"
    # _path/_current are assigned via eval above, which shellcheck can't see.
    # shellcheck disable=SC2154
    if [ ! -r "$_path" ]; then
      echo "astravault: \$$_file_var=$_path is not readable" >&2
      return 1
    fi
    eval "_current=\${$_var:-}"
    if [ -n "$_current" ]; then
      echo "astravault: \$$_var is set in the environment and via \$$_file_var; the file takes precedence" >&2
    fi
    _value="$(cat "$_path")"
    export "$_var=$_value"
    unset "$_file_var"
  done
}
