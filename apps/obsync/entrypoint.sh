#!/bin/bash
# obsync image entrypoint: bridges Docker swarm secrets to env vars consumed
# by the upstream couchdb entrypoint, optionally backgrounds the provisioner,
# then hands off to the upstream entrypoint with the original CMD.
set -eu

if [ -f /run/secrets/obsync_admin_user ]; then
    export COUCHDB_USER=$(cat /run/secrets/obsync_admin_user)
fi
if [ -f /run/secrets/obsync_admin_password ]; then
    export COUCHDB_PASSWORD=$(cat /run/secrets/obsync_admin_password)
fi
if [ -f /run/secrets/obsync_chttpd_secret ]; then
    export COUCHDB_SECRET=$(cat /run/secrets/obsync_chttpd_secret)
fi

# If a provisioning config is mounted, fork the provisioner so it can run
# in parallel with CouchDB startup. It polls /_up before doing any work.
if [ -f /run/secrets/obsync_provisioning_config ]; then
    /opt/obsync/provision.sh &
fi

# Hand off to the upstream couchdb entrypoint with the original CMD.
exec /usr/local/bin/docker-entrypoint.sh "$@"
