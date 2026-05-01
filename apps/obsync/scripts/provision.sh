#!/bin/bash
# Boot-time provisioner. Reads a JSON provisioning config from a Docker swarm
# secret and ensures CouchDB users, JWT public keys, shared databases, and
# _security membership match. Idempotent — safe to run on every boot.
#
# The config secret JSON shape:
#   {
#     "users": {
#       "alice": {
#         "password": "...",
#         "e2ee_passphrase": "...",
#         "jwt": {                              # optional; if present, public
#           "public_key": "-----BEGIN PUBLIC KEY-----\n...\n",
#           "algorithm":  "ES256"               # or ES512
#         }
#       },
#       ...
#     },
#     "shared_vaults": {
#       "team-engineering": {
#         "members":         ["alice","bob"],
#         "e2ee_passphrase": "..."
#       },
#       ...
#     }
#   }
#
# The `e2ee_passphrase` and `jwt.private_key` (if any) are not consumed here —
# they're handed to the `obsync setup-uri` command later. They live in the
# same config so the image has a single source of truth.

set -eu

LOG_PREFIX="[provision]"
log() { echo "${LOG_PREFIX} $*"; }

ADMIN_USER=$(cat /run/secrets/obsync_admin_user)
ADMIN_PASS=$(cat /run/secrets/obsync_admin_password)
URL=http://localhost:5984
CONFIG=/run/secrets/obsync_provisioning_config

if [ ! -f "$CONFIG" ]; then
    log "no provisioning config mounted at $CONFIG; skipping"
    exit 0
fi

log "waiting for CouchDB to be ready..."
for _ in $(seq 1 90); do
    if curl -fsS "$URL/_up" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done
if ! curl -fsS "$URL/_up" >/dev/null 2>&1; then
    log "FATAL: CouchDB did not respond to /_up within 90s; aborting"
    exit 1
fi
log "CouchDB ready"

# 1. Ensure system databases exist (idempotent).
for db in _users _replicator _global_changes; do
    code=$(curl -s -o /dev/null -w '%{http_code}' \
        -u "$ADMIN_USER:$ADMIN_PASS" "$URL/$db")
    if [ "$code" = "404" ]; then
        log "creating system db $db"
        curl -sf -u "$ADMIN_USER:$ADMIN_PASS" -X PUT "$URL/$db" >/dev/null \
            || log "WARN: PUT /$db failed"
    fi
done

# 2. Ensure each managed user exists with the declared password.
jq -r '(.users // {}) | to_entries[] | "\(.key)\t\(.value.password)"' "$CONFIG" \
| while IFS=$'\t' read -r name password; do
    [ -z "$name" ] && continue
    log "ensuring user '$name'"
    existing=$(curl -sS -u "$ADMIN_USER:$ADMIN_PASS" \
        "$URL/_users/org.couchdb.user:$name")
    rev=$(printf '%s' "$existing" | jq -r '._rev // empty')

    if [ -n "$rev" ]; then
        body=$(jq -nc --arg n "$name" --arg p "$password" --arg r "$rev" \
            '{_id:("org.couchdb.user:"+$n), _rev:$r, name:$n, password:$p, roles:[], type:"user"}')
    else
        body=$(jq -nc --arg n "$name" --arg p "$password" \
            '{name:$n, password:$p, roles:[], type:"user"}')
    fi

    code=$(printf '%s' "$body" | curl -s -o /dev/null -w '%{http_code}' \
        -u "$ADMIN_USER:$ADMIN_PASS" -X PUT \
        -H 'content-type: application/json' \
        --data-binary @- "$URL/_users/org.couchdb.user:$name")
    case "$code" in
        201|200) ;;
        409)     log "WARN: rev conflict for $name (will retry next boot)" ;;
        *)       log "WARN: PUT user $name returned $code" ;;
    esac
done

# 3. Install / refresh per-user JWT public keys via REST.
#    [jwt_keys] ec:<kid> = <public-key-PEM>
#    The kid we use is the username — keeps things simple, one key per user.
#    The PEM string is sent as a JSON-encoded string so newlines in the key
#    survive the round trip.
jq -c '(.users // {}) | to_entries[]
       | select(.value.jwt? != null)
       | {name: .key, alg: .value.jwt.algorithm, key: .value.jwt.public_key}' "$CONFIG" \
| while IFS= read -r row; do
    [ -z "$row" ] && continue
    name=$(printf '%s' "$row" | jq -r '.name')
    pem=$(printf '%s' "$row"  | jq -r '.key')
    alg=$(printf '%s' "$row"  | jq -r '.alg // "ES256"')

    # CouchDB jwt_keys section uses the algorithm family as the key prefix.
    # ES256 / ES512 → ec:<kid>; HS256/HS512 (we don't use) would be hmac:<kid>.
    case "$alg" in
        ES256|ES512) family=ec ;;
        *) log "WARN: user $name has unsupported jwt algorithm '$alg'; skipping"; continue ;;
    esac

    log "installing JWT public key for '$name' (alg=$alg, kid=$name)"
    # CouchDB stores config values as raw strings — multi-line PEMs are
    # rejected as "Invalid configuration value". The convention (also used
    # by Fauxton) is to escape literal newlines as the 2-char sequence \n
    # in the stored value; CouchDB's PEM parser then re-interprets those
    # at validation time. See: docs/tips/jwt-on-couchdb.md upstream.
    json_body=$(jq -nc --arg p "$pem" '$p | gsub("\n"; "\\n")')
    code=$(printf '%s' "$json_body" | curl -s -o /dev/null -w '%{http_code}' \
        -u "$ADMIN_USER:$ADMIN_PASS" -X PUT \
        -H 'content-type: application/json' \
        --data-binary @- "$URL/_node/_local/_config/jwt_keys/${family}:${name}")
    case "$code" in
        200) ;;
        *)   log "WARN: PUT jwt_keys/${family}:${name} returned $code" ;;
    esac
done

# 4. Ensure each shared vault exists with declared membership.
jq -r '(.shared_vaults // {}) | to_entries[]
       | "\(.key)\t\(.value.members | join(","))"' "$CONFIG" \
| while IFS=$'\t' read -r vault members; do
    [ -z "$vault" ] && continue
    log "ensuring shared vault '$vault' with members: ${members:-<none>}"

    code=$(curl -s -o /dev/null -w '%{http_code}' \
        -u "$ADMIN_USER:$ADMIN_PASS" "$URL/$vault")
    if [ "$code" = "404" ]; then
        log "creating db $vault"
        curl -sf -u "$ADMIN_USER:$ADMIN_PASS" -X PUT "$URL/$vault" >/dev/null \
            || { log "WARN: PUT /$vault failed"; continue; }
    fi

    members_json=$(printf '%s' "$members" | jq -Rc 'if . == "" then [] else split(",") end')
    sec=$(jq -nc --argjson m "$members_json" \
        '{admins:{names:[],roles:[]}, members:{names:$m,roles:[]}}')
    printf '%s' "$sec" | curl -sf -u "$ADMIN_USER:$ADMIN_PASS" -X PUT \
        -H 'content-type: application/json' \
        --data-binary @- "$URL/$vault/_security" >/dev/null \
        || log "WARN: PUT /$vault/_security failed"
done

log "provisioning complete"
