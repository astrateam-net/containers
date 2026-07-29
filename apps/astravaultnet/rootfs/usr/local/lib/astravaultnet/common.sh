# shellcheck shell=sh
# astravaultnet — helpers shared by the role services.
#
# Every role is a subcommand of the same `infisical` binary, so a container can
# run one role or several at once. ASTRAVAULT_NET holds the list; each s6
# longrun asks whether it is in it, and builds its own argv from there.
#
# Because roles coexist, configuration resolves in two steps: a role-scoped
# variable wins, and a bare one is the shared fallback. So a container running
# gateway + agent-proxy under one identity sets ASTRAVAULT_CLIENT_ID once, and
# one running them under separate identities sets ASTRAVAULT_GATEWAY_CLIENT_ID
# and ASTRAVAULT_PROXY_CLIENT_ID instead.

# Role names, normalised and space-separated. Accepts commas, semicolons or
# spaces as separators, any case, and agent_proxy / agentproxy for agent-proxy.
av_roles() {
  printf '%s' "${ASTRAVAULT_NET:-}" |
    tr '[:upper:]' '[:lower:]' |
    tr ',;' '  ' |
    tr '_' '-' |
    sed 's/agentproxy/agent-proxy/g'
}

av_role_enabled() {
  for _r in $(av_roles); do
    if [ "$_r" = "$1" ]; then return 0; fi
  done
  return 1
}

# av_var GATEWAY TOKEN -> $ASTRAVAULT_GATEWAY_TOKEN, falling back to $ASTRAVAULT_TOKEN.
av_var() {
  eval "_v=\${ASTRAVAULT_${1}_${2}:-}"
  if [ -z "${_v:-}" ]; then eval "_v=\${ASTRAVAULT_${2}:-}"; fi
  printf '%s' "${_v:-}"
}

# Export only when non-empty, so an unset knob leaves the CLI's own default alone.
av_export() {
  if [ -n "${2:-}" ]; then export "$1=$2"; fi
}

# Docker / Swarm secrets: for every VAR_FILE in the environment, read the file
# into VAR (one trailing newline stripped). An explicitly set VAR always wins.
av_resolve_file_secrets() {
  for _f in $(env | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)_FILE=.*/\1_FILE/p'); do
    _base=${_f%_FILE}
    _path=$(printenv "$_f" || true)
    [ -n "$_path" ] || continue
    eval "_cur=\${$_base:-}"
    if [ -n "${_cur:-}" ]; then
      echo "both $_base and $_f are set; using $_base and ignoring $_f" >&2
      continue
    fi
    if [ ! -f "$_path" ]; then
      echo "ERROR: $_f points to '$_path' but that file does not exist" >&2
      return 1
    fi
    export "$_base=$(cat "$_path")"
  done
}

# %h in a name is replaced with the container hostname. Handy in Swarm with
# --hostname={{.Node.Hostname}} so each task gets a distinct gateway name.
av_subst_hostname() {
  printf '%s' "$1" | sed "s/%h/$(hostname)/g"
}

# Hand the assembled argv to the CLI. With ASTRAVAULT_NET_DEBUG set, print it
# instead (secrets redacted) and exit — the argv a role builds is then testable
# without a live astravault to connect to.
av_exec() {
  if [ -z "${ASTRAVAULT_NET_DEBUG:-}" ]; then
    exec /bin/infisical "$@"
  fi
  _out="infisical"
  for _a in "$@"; do
    case "$_a" in
      --token=*)             _a="--token=***" ;;
      --relay-auth-secret=*) _a="--relay-auth-secret=***" ;;
      --client-secret=*)     _a="--client-secret=***" ;;
    esac
    _out="$_out $_a"
  done
  printf '%s\n' "$_out"
  # Values that reached the CLI through its own environment rather than argv:
  # names only, so the wiring is visible without leaking the secrets.
  for _n in INFISICAL_GATEWAY_ACCESS_TOKEN INFISICAL_RELAY_ACCESS_TOKEN \
            INFISICAL_RELAY_AUTH_SECRET INFISICAL_UNIVERSAL_AUTH_CLIENT_ID \
            INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET; do
    eval "_v=\${$_n:-}"
    if [ -n "${_v:-}" ]; then printf 'env: %s\n' "$_n"; fi
  done
  exit 0
}
