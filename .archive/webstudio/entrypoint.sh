#!/bin/sh

# Don't exit on error for the wait loop
set +e

# Run migrations if RUN_MIGRATIONS is set to "true"
# Note: Docker daemon is not started yet, so migrations that don't need Docker can run
if [ "${RUN_MIGRATIONS}" = "true" ]; then
  echo "Running database migrations..."
  cd /app
  
  # Generate Prisma client first (required before migrations)
  # Use pnpm to run prisma (now available via pnpm install - all deps)
  echo "Generating Prisma client..."
  cd /app
  if ! pnpm --filter=@webstudio-is/prisma-client generate; then
    echo "WARNING: Prisma client generation failed, but continuing..."
  fi
  
  # Run migrations using pnpm (tsx is available via pnpm install - all deps)
  # The migrations script is at ./migrations-cli/cli.ts
  echo "Running database migrations..."
  cd /app
  if ! pnpm --filter=./packages/prisma-client migrations migrate --cwd /app/apps/builder; then
    echo "WARNING: Database migrations failed, but continuing startup..."
    echo "You may need to run migrations manually or check database connection"
  else
    echo "Migrations completed successfully."
  fi
fi

# Wait for PostgREST to be ready before starting the app
# PostgREST needs time to load schema cache and establish connections
echo "Waiting for PostgREST to be ready..."
max_attempts=30
attempt=0
while [ $attempt -lt $max_attempts ]; do
  # Use wget if available, otherwise curl
  if command -v wget >/dev/null 2>&1; then
    if wget --quiet --spider --timeout=2 http://localhost:3000/ 2>/dev/null; then
      echo "PostgREST is ready!"
      break
    fi
  elif command -v curl >/dev/null 2>&1; then
    if curl -f -s --max-time 2 http://localhost:3000/ >/dev/null 2>&1; then
      echo "PostgREST is ready!"
      break
    fi
  else
    # If neither curl nor wget is available, just wait a bit
    sleep 2
    break
  fi
  attempt=$((attempt + 1))
  if [ $((attempt % 5)) -eq 0 ]; then
    echo "Waiting for PostgREST... (attempt $attempt/$max_attempts)"
  fi
  sleep 1
done

if [ $attempt -eq $max_attempts ]; then
  echo "WARNING: PostgREST may not be ready after $max_attempts attempts, but continuing startup..."
fi

# Re-enable exit on error for the rest of the script
set -e

# Now delegate to docker-init.sh which handles Docker-in-Docker setup
# docker-init.sh was created during build time, but executes at runtime
# It will start Docker daemon, then execute the main command
# Ensure we're in workspace root (required for pnpm workspace commands)
cd /app
exec /usr/local/share/docker-init.sh "$@"

