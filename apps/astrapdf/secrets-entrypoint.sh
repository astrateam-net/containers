#!/bin/sh
# Generic Docker "secrets via file" support for AstraPDF.
#
# Stirling-PDF has no native _FILE convention. This wrapper implements the
# common one: for every environment variable named <NAME>_FILE whose value is a
# readable file, it exports <NAME> with the file's (trimmed) contents, then hands
# off to the original Stirling entrypoint. Lets any setting be supplied as a
# Docker/Swarm secret, e.g.:
#
#   SYSTEM_DATASOURCE_PASSWORD_FILE=/run/secrets/astrapdf_db_password
#   SECURITY_OAUTH2_CLIENTSECRET_FILE=/run/secrets/astrapdf_oidc_client_secret
#
# A directly-set <NAME> is overridden by <NAME>_FILE when the file exists.
set -e

echo "AstraPDF: resolving *_FILE secrets into environment..."
for v in $(env | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)_FILE=.*/\1_FILE/p'); do
    target=${v%_FILE}
    file=$(eval printf '%s' "\"\$$v\"")
    if [ -n "$file" ] && [ -f "$file" ]; then
        export "$target=$(tr -d '\n\r' < "$file")"
        echo "  ✓ ${target} ← ${file}"
    else
        echo "  ⚠ ${v} is set but '${file}' is not a readable file"
    fi
done

# Hand off to the stock Stirling-PDF init (JDK_JAVA_OPTIONS carries our agent).
exec /scripts/init.sh
