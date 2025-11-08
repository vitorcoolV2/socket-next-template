#!/bin/bash

# Exit on error
set -e

# Define array of Compose file directories relative to devops/
COMPOSE_FILES=("portainer" "kuma"  "pihole" "socket-io" "react-app" )

# Function to relaunch a Compose service
relaunchCompose() {
  local dir=$1
  echo "Processing $dir..."
  cd "devops/$dir" || { echo "Directory devops/$dir not found"; exit 1; }
  docker-compose down
  docker-compose up -d
  cd - > /dev/null || exit 1
}

# Create or ensure app-network exists
if ! docker network ls --format '{{.Name}}' | grep -q app-network; then
  echo "Creating app-network..."
  docker network create app-network
else
  echo "app-network already exists, reusing it."
fi

# Relaunch each service
for file in "${COMPOSE_FILES[@]}"; do
  relaunchCompose "$file"
done

echo "All services relaunched."