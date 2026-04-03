#!/bin/sh
set -e

# Auto-load SSH key from env var or file if available
if [ -n "${CI_RUNNER_SSH_PRIVATE_KEY}" ]; then
  eval "$(ssh-agent -s)" > /dev/null
  echo "${CI_RUNNER_SSH_PRIVATE_KEY}" | ssh-add - 2>/dev/null
fi

if [ -f "${CI_RUNNER_SSH_PRIVATE_KEY_FILE:-/dev/null}" ]; then
  eval "$(ssh-agent -s)" > /dev/null
  ssh-add "${CI_RUNNER_SSH_PRIVATE_KEY_FILE}" 2>/dev/null
fi

# Disable strict host key checking for CI
mkdir -p ~/.ssh
echo "StrictHostKeyChecking no" > ~/.ssh/config
echo "UserKnownHostsFile /dev/null" >> ~/.ssh/config
chmod 700 ~/.ssh
chmod 600 ~/.ssh/config

exec "$@"
