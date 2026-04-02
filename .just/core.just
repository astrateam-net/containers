set working-directory := '..'

_bin_dir := justfile_directory() + "/../.bin"

[group("setup")]
[doc("Initialize the project (download goss/dgoss)")]
init:
  #!/usr/bin/env bash
  set -euo pipefail
  command -v gh >/dev/null || { echo "ERROR: gh CLI not found in PATH"; exit 1; }
  mkdir -p "{{_bin_dir}}/goss" "{{_bin_dir}}/dgoss"
  ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
  gh release download --repo goss-org/goss --skip-existing --pattern "*-linux-${ARCH}" --output "{{_bin_dir}}/goss/goss"
  gh release download --repo goss-org/goss --skip-existing --pattern "dgoss" --output "{{_bin_dir}}/dgoss/dgoss"
  chmod +x "{{_bin_dir}}/goss/goss" "{{_bin_dir}}/dgoss/dgoss"

[group("ci")]
[doc("Generate app labels in the labels config file")]
generate-app-labels:
  #!/usr/bin/env bash
  set -euo pipefail
  for dir in apps/*/; do
    app=$(basename "$dir")
    yq --inplace '. += [{"name": "app/'"$app"'", "color": "0e8a16"}]' .github/labels.yaml
  done
