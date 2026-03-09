#!/bin/bash -eu

GH_RUNNER_VERSION=$1
TARGETPLATFORM=${2:-linux/amd64}

TARGET_ARCH="x64"
if [[ "${TARGETPLATFORM}" == "linux/arm64" ]]; then
  TARGET_ARCH="arm64"
fi

curl -fsSL "https://github.com/actions/runner/releases/download/v${GH_RUNNER_VERSION}/actions-runner-linux-${TARGET_ARCH}-${GH_RUNNER_VERSION}.tar.gz" > actions.tar.gz
tar -zxf actions.tar.gz
rm -f actions.tar.gz
./bin/installdependencies.sh
mkdir -p /_work
