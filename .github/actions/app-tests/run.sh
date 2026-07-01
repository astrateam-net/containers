#!/usr/bin/env bash
set -Eeuo pipefail

APP="${1:?}"
IMAGE="${2:?}"


if [[ ! -f "./apps/${APP}/tests.yaml" ]]; then
    echo "No test file found for ${APP}, skipping tests."
    exit 0
fi

if [[ -x "$(command -v container-structure-test)" ]]; then
    container-structure-test test --image "${IMAGE}" --config "./apps/${APP}/tests.yaml"
elif [[ -x "$(command -v goss)" && -x "$(command -v dgoss)" ]]; then
    export GOSS_FILE="./apps/${APP}/tests.yaml"
    # Boot-wait window: some images (e.g. astrai18n boots embedded PostgreSQL +
    # migrations, healthy at ~64s) need well over the old 60s. Cap generously —
    # fast apps still pass immediately and exit. Kept in step with the local
    # `mise run local-build` opts.
    export GOSS_OPTS="--retry-timeout 300s --sleep 2s"
    dgoss run "${IMAGE}"
else
    echo "No testing tool found. Exiting."
    exit 1
fi
