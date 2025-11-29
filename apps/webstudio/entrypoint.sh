#!/bin/sh

set -e

# Run migrations if RUN_MIGRATIONS is set to "true"
# Note: Docker daemon is not started yet, so migrations that don't need Docker can run
if [ "${RUN_MIGRATIONS}" = "true" ]; then
  echo "Running database migrations..."
  cd /app
  # Generate Prisma client first (required before migrations)
  echo "Generating Prisma client..."
  pnpm --filter=@webstudio-is/prisma-client generate
  # Run migrations (without --dev flag for production)
  echo "Running database migrations..."
  pnpm --filter=./packages/prisma-client migrations migrate --cwd /app/apps/builder
  echo "Migrations completed."
fi

# Now delegate to docker-init.sh which handles Docker-in-Docker setup
# docker-init.sh was created during build time, but executes at runtime
# It will start Docker daemon, then execute the main command
exec /usr/local/share/docker-init.sh "$@"

