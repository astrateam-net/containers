#!/bin/sh
set -e

# GitLab CI creates build directories with world-writable permissions (0777).
# Ansible refuses to load ansible.cfg from such directories for security.
# Fix directory permissions so project ansible.cfg is respected.
find . -maxdepth 3 -type d -perm /o+w -exec chmod o-w {} + 2>/dev/null || true

# Ensure project-local collections (installed via `ansible-galaxy -p collections`)
# are discoverable alongside the default system paths.
: "${ANSIBLE_COLLECTIONS_PATH:=collections:/usr/share/ansible/collections:${HOME}/.ansible/collections}"
export ANSIBLE_COLLECTIONS_PATH

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
