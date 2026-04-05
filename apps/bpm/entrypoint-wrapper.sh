#!/bin/bash
set -e

# ============================================================
# Entrypoint wrapper for Jira Docker (Swarm deployment)
# Runs as root before dropping to jira user via original entrypoint.
#
# Handles:
#   1. Custom CA certificates → Java truststore (e.g. Active Directory)
# ============================================================

# --- 1. Import custom CA certificates into Java truststore ---
CERT_DIR="/opt/atlassian/certificates"
CACERTS="$JAVA_HOME/lib/security/cacerts"
TRUSTSTORE="/var/ssl/cacerts"

if [ -d "$CERT_DIR" ] && [ "$(ls -A $CERT_DIR 2>/dev/null)" ]; then
    echo "entrypoint-wrapper: Importing custom CA certificates..."
    cp "$CACERTS" "$TRUSTSTORE"
    chmod 664 "$TRUSTSTORE"

    for crt in "$CERT_DIR"/*; do
        alias=$(basename "$crt" | sed 's/\.[^.]*$//')
        echo "  Adding: $alias ($(basename "$crt"))"
        keytool -import -keystore "$TRUSTSTORE" \
            -storepass changeit -noprompt \
            -alias "$alias" -file "$crt" 2>/dev/null || true
    done

    # Tell Java to use the custom truststore (same approach as Helm chart)
    export JVM_SUPPORT_RECOMMENDED_ARGS="${JVM_SUPPORT_RECOMMENDED_ARGS} -Djavax.net.ssl.trustStore=${TRUSTSTORE}"
    echo "entrypoint-wrapper: Truststore ready at $TRUSTSTORE"

    # Also update system CA store (for curl, wget, etc.)
    cp "$CERT_DIR"/* /usr/local/share/ca-certificates/ 2>/dev/null || true
    update-ca-certificates 2>/dev/null || true
fi

# --- Hand off to original entrypoint ---
exec /entrypoint.py "$@"
