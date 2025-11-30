#!/bin/sh

set -e

# Run migrations if RUN_MIGRATIONS is set to "true"
# Note: Docker daemon is not started yet, so migrations that don't need Docker can run
if [ "${RUN_MIGRATIONS}" = "true" ]; then
  echo "Running database migrations..."
  cd /app
  # Generate Prisma client first (required before migrations)
  echo "Generating Prisma client..."
  if ! pnpm --filter=@webstudio-is/prisma-client generate; then
    echo "WARNING: Prisma client generation failed, but continuing..."
  fi
  # Run migrations (production mode, without --dev flag)
  # Using the same pattern as upstream: pnpm --filter=./packages/prisma-client migrations migrate
  echo "Running database migrations..."
  if ! pnpm --filter=./packages/prisma-client migrations migrate --cwd /app/apps/builder; then
    echo "WARNING: Database migrations failed, but continuing startup..."
    echo "You may need to run migrations manually or check database connection"
  else
    echo "Migrations completed successfully."
  fi
fi

# Now delegate to docker-init.sh which handles Docker-in-Docker setup
# docker-init.sh was created during build time, but executes at runtime
# It will start Docker daemon, then execute the main command
exec /usr/local/share/docker-init.sh "$@"

