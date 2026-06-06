#!/usr/bin/env bash
# Run the locally-built forked Coder for manual UI verification.
#
# Single container: Coder uses its built-in PostgreSQL when no
# CODER_PG_CONNECTION_URL is set, so there is nothing else to start. Open the
# URL, create the first admin in the browser, then check that the premium
# features are unlocked (Deployment > Licenses, plus the Organizations and
# Custom Roles sections in the sidebar).
#
# Data persists in the named volume "coder-dev-data", so the admin user and any
# templates survive restarts. Remove it with `docker volume rm coder-dev-data`
# to start fresh.
set -euo pipefail

IMG="${IMG:-coder-dev:local}"
PORT="${PORT:-3000}"

cd "$(dirname "$0")"

# Build (and tag) on demand if the image is not already present locally.
if ! docker image inspect "$IMG" >/dev/null 2>&1; then
  echo ">> $IMG not found, building via buildx bake (this takes a while)..."
  docker buildx bake -f docker-bake.hcl image-local --set "image-local.tags=$IMG" --load
fi

echo ">> Starting Coder at http://localhost:${PORT}"
echo ">> First run boots the built-in PostgreSQL and applies migrations (~30-60s)."
echo ">> Open the URL and create the first admin user in the browser."

exec docker run --rm --name coder-dev \
  -p "${PORT}:3000" \
  -e CODER_HTTP_ADDRESS=0.0.0.0:3000 \
  -e CODER_ACCESS_URL="http://localhost:${PORT}" \
  -v coder-dev-data:/home/coder \
  "$IMG"
