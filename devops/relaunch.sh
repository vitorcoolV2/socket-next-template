#!/bin/bash

# Exit on error
set -e

#!/bin/bash

# Change to script directory
cd "$(dirname "$0")"

echo "Working directory: $(pwd)"


COMPOSE_FILES=( "pihole" "step-ca" "authelia" "traefik" )
# "socket.io" "react-app" "hedgedoc"  "kuma" )

# Function to relaunch a Compose service
downCompose() {
  local dir=$1
  echo "Processing $dir..."
  cd "$dir" || { echo "Directory $dir not found"; exit 1; }
  docker-compose down
  cd - > /dev/null || exit 1
}

upCompose() {
  local dir=$1
  echo "Processing $dir..."
  cd "$dir" || { echo "Directory $dir not found"; exit 1; }
  docker-compose up -d
  sleep 5
  cd - > /dev/null || exit 1
}

# Create or ensure app-network exists
if ! docker network ls --format '{{.Name}}' | grep -q app-network; then
  echo "Creating app-network..."
  docker network create app-network
else
  echo "app-network already exists, reusing it."
fi


# Relaunch each service in reverse order
for ((i=${#COMPOSE_FILES[@]}-1; i>=0; i--)); do
  downCompose "${COMPOSE_FILES[i]}"
done
# Relaunch each service
for file in "${COMPOSE_FILES[@]}"; do
  upCompose "$file"
done

echo "All services relaunched."