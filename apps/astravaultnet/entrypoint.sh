#!/bin/sh
# astravaultnet — env-driven wrapper around the Infisical CLI networking
# components. One image, one role per container:
#
#   ASTRAVAULT_NET=gateway   -> infisical gateway start <name> [flags]
#   ASTRAVAULT_NET=relay     -> infisical relay start [flags]
#
# The entire user-facing interface is namespaced ASTRAVAULT_*. Internally the
# wrapper translates it to what the CLI needs: most values become flags; a few
# that the CLI reads only from its own environment are re-exported to the
# matching INFISICAL_* name. It also:
#   - resolves Docker / Swarm secrets: any VAR_FILE is read into VAR;
#   - dispatches to gateway|relay from a single variable;
#   - supplies --token and --domain, which the CLI accepts only as flags.
#
# Extra args passed to the container are forwarded to the subcommand, so
# `... --help` and ad-hoc flags still work.
set -eu

log() { printf '%s astravaultnet: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

# ---------------------------------------------------------------------------
# 1. Docker / Swarm secrets. For every VAR_FILE in the environment, read the
#    file into VAR (a single trailing newline is stripped). An explicitly set
#    VAR always wins over its _FILE companion.
# ---------------------------------------------------------------------------
for _f in $(env | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)_FILE=.*/\1_FILE/p'); do
  _base=${_f%_FILE}
  _path=$(printenv "$_f" || true)
  [ -n "$_path" ] || continue
  eval "_cur=\${$_base:-}"
  if [ -n "${_cur:-}" ]; then
    log "both $_base and $_f are set; using $_base and ignoring $_f"
    continue
  fi
  [ -f "$_path" ] || die "$_f points to '$_path' but that file does not exist"
  export "$_base=$(cat "$_path")"
  log "loaded $_base from $_f ($_path)"
done

# ---------------------------------------------------------------------------
# 2. Re-export the values the CLI reads only from its own INFISICAL_* env, so
#    users only ever set ASTRAVAULT_*. (Flag-mapped values are handled below.)
# ---------------------------------------------------------------------------
reexport() { # reexport ASTRAVAULT_X INFISICAL_Y
  eval "_v=\${$1:-}"
  [ -n "${_v:-}" ] || return 0
  export "$2=$_v"
}
reexport ASTRAVAULT_GATEWAY_ACCESS_TOKEN INFISICAL_GATEWAY_ACCESS_TOKEN
reexport ASTRAVAULT_RELAY_ACCESS_TOKEN   INFISICAL_RELAY_ACCESS_TOKEN
reexport ASTRAVAULT_RELAY_AUTH_SECRET    INFISICAL_RELAY_AUTH_SECRET
reexport ASTRAVAULT_CLIENT_ID            INFISICAL_UNIVERSAL_AUTH_CLIENT_ID
reexport ASTRAVAULT_CLIENT_SECRET        INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET

# %h in a name is replaced with the container hostname. Handy for Swarm global
# mode with --hostname={{.Node.Hostname}} so each task gets a unique name.
subst_hostname() { printf '%s' "$1" | sed "s/%h/$(hostname)/g"; }

role=$(printf '%s' "${ASTRAVAULT_NET:-}" | tr '[:upper:]' '[:lower:]')

# Escape hatch: no role set but args given -> run a raw infisical command.
if [ -z "$role" ]; then
  if [ "$#" -gt 0 ]; then
    exec /bin/infisical "$@"
  fi
  die "ASTRAVAULT_NET must be 'gateway' or 'relay' (or pass an infisical subcommand as arguments)"
fi

case "$role" in
  gateway)
    name=$(subst_hostname "${ASTRAVAULT_GATEWAY_NAME:-}")
    # flags first (appended after any user args), then positional name, then subcommand
    [ -n "${ASTRAVAULT_DOMAIN:-}" ]            && set -- "$@" "--domain=$ASTRAVAULT_DOMAIN"
    [ -n "${ASTRAVAULT_ENROLL_METHOD:-}" ]     && set -- "$@" "--enroll-method=$ASTRAVAULT_ENROLL_METHOD"
    [ -n "${ASTRAVAULT_TOKEN:-}" ]             && set -- "$@" "--token=$ASTRAVAULT_TOKEN"
    [ -n "${ASTRAVAULT_GATEWAY_ID:-}" ]        && set -- "$@" "--gateway-id=$ASTRAVAULT_GATEWAY_ID"
    [ -n "${ASTRAVAULT_TARGET_RELAY_NAME:-}" ] && set -- "$@" "--target-relay-name=$ASTRAVAULT_TARGET_RELAY_NAME"
    [ -n "${ASTRAVAULT_AUTH_METHOD:-}" ]       && set -- "$@" "--auth-method=$ASTRAVAULT_AUTH_METHOD"
    [ -n "${ASTRAVAULT_PKCS11_MODULE:-}" ]     && set -- "$@" "--pkcs11-module=$ASTRAVAULT_PKCS11_MODULE"
    [ -n "$name" ] && set -- "$name" "$@"
    set -- gateway start "$@"
    ;;
  relay)
    name=$(subst_hostname "${ASTRAVAULT_RELAY_NAME:-}")
    [ -n "${ASTRAVAULT_DOMAIN:-}" ]        && set -- "$@" "--domain=$ASTRAVAULT_DOMAIN"
    [ -n "$name" ]                         && set -- "$@" "--name=$name"
    [ -n "${ASTRAVAULT_RELAY_HOST:-}" ]    && set -- "$@" "--host=$ASTRAVAULT_RELAY_HOST"
    [ -n "${ASTRAVAULT_RELAY_TYPE:-}" ]    && set -- "$@" "--type=$ASTRAVAULT_RELAY_TYPE"
    [ -n "${ASTRAVAULT_ENROLL_METHOD:-}" ] && set -- "$@" "--enroll-method=$ASTRAVAULT_ENROLL_METHOD"
    [ -n "${ASTRAVAULT_TOKEN:-}" ]         && set -- "$@" "--token=$ASTRAVAULT_TOKEN"
    [ -n "${ASTRAVAULT_RELAY_ID:-}" ]      && set -- "$@" "--relay-id=$ASTRAVAULT_RELAY_ID"
    [ -n "${ASTRAVAULT_AUTH_METHOD:-}" ]   && set -- "$@" "--auth-method=$ASTRAVAULT_AUTH_METHOD"
    set -- relay start "$@"
    ;;
  *)
    die "invalid ASTRAVAULT_NET='$ASTRAVAULT_NET' (expected 'gateway' or 'relay')"
    ;;
esac

# Dry run for tests / debugging: print the resolved argv (secrets redacted) and
# exit without launching. Enable with ASTRAVAULT_NET_DEBUG=1.
if [ -n "${ASTRAVAULT_NET_DEBUG:-}" ]; then
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
  exit 0
fi

log "starting: infisical $1 $2 (role=$role)"
exec /bin/infisical "$@"
