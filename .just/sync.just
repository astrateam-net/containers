set working-directory := '..'

[group("sync")]
[doc("Sync Confluence entrypoints and assets from upstream Atlassian repo")]
wiki:
  #!/usr/bin/env bash
  set -euo pipefail
  TMP_DIR=$(mktemp -d)
  trap 'rm -rf "$TMP_DIR"' EXIT
  git clone --recurse-submodules https://bitbucket.org/atlassian-docker/docker-atlassian-confluence-server.git "$TMP_DIR"
  cp "$TMP_DIR/entrypoint.py" apps/wiki/
  cp "$TMP_DIR/shutdown-wait.sh" apps/wiki/
  cp "$TMP_DIR/wait-for-catalina-shutdown.sh" apps/wiki/
  mkdir -p apps/wiki/shared-components/image
  cp "$TMP_DIR/shared-components/image/entrypoint_helpers.py" apps/wiki/shared-components/image/
  mkdir -p apps/wiki/shared-components/support
  cp -r "$TMP_DIR/shared-components/support/." apps/wiki/shared-components/support/
  mkdir -p apps/wiki/config
  cp -r "$TMP_DIR/config/." apps/wiki/config/

[group("sync")]
[doc("Sync Jira entrypoints and assets from upstream Atlassian repo")]
agile:
  #!/usr/bin/env bash
  set -euo pipefail
  TMP_DIR=$(mktemp -d)
  trap 'rm -rf "$TMP_DIR"' EXIT
  git clone --recurse-submodules https://bitbucket.org/atlassian-docker/docker-atlassian-jira.git "$TMP_DIR"
  cp "$TMP_DIR/entrypoint.py" apps/agile/
  cp "$TMP_DIR/shutdown-wait.sh" apps/agile/
  mkdir -p apps/agile/shared-components/image
  cp "$TMP_DIR/shared-components/image/entrypoint_helpers.py" apps/agile/shared-components/image/
  mkdir -p apps/agile/shared-components/support
  cp -r "$TMP_DIR/shared-components/support/." apps/agile/shared-components/support/
  mkdir -p apps/agile/config
  cp -r "$TMP_DIR/config/." apps/agile/config/
