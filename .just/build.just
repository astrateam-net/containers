set working-directory := '..'

_bin_dir := justfile_directory() + "/../.bin"

[group("build")]
[doc("Build and test an app locally via Docker Buildx")]
local-build app:
  #!/usr/bin/env bash
  set -euo pipefail
  ROOT=$(pwd)
  cd "apps/{{app}}"
  for f in docker-bake.hcl tests.yaml Dockerfile; do
    [[ -f "$f" ]] || { echo "ERROR: missing apps/{{app}}/$f"; exit 1; }
  done
  for cmd in container-structure-test docker jq yq; do
    command -v "$cmd" >/dev/null || { echo "ERROR: $cmd not found in PATH"; exit 1; }
  done
  docker buildx bake --metadata-file docker-bake.json --load
  trap 'rm -f docker-bake.json' EXIT
  IMAGE=$(jq --raw-output '."image-local"."image.name" // ."image-local"."containerimage.config.digest"' docker-bake.json)
  if yq --exit-status '.schemaVersion' tests.yaml &>/dev/null; then
    container-structure-test test --image "${IMAGE}" --config tests.yaml
  else
    GOSS_FILE=tests.yaml \
    GOSS_OPTS="--retry-timeout 60s --sleep 1s" \
    GOSS_PATH="$ROOT/.bin/goss/goss" \
    "$ROOT/.bin/dgoss/dgoss" run "${IMAGE}"
  fi

[group("build")]
[doc("Trigger a remote build via GitHub Actions")]
remote-build app release="false":
  #!/usr/bin/env bash
  set -euo pipefail
  gh auth status
  gh workflow run release.yaml -f app={{app}} -f release={{release}}
