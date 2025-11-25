#!/bin/bash

# Exit on error
set -e

# Variables
PROJECT_DIR="$(pwd)"
DOCKERFILE="devops/socket.io/Dockerfile"
IMAGE_NAME="socket-io-server"
TAG="latest"

# Change to project root if not already there
cd "$PROJECT_DIR" || exit 1

# Build the Docker image
echo "Building Docker image for Socket.IO server..."
docker build \
  -f "$DOCKERFILE" \
  --build-arg BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ") \
  -t "$IMAGE_NAME:$TAG" \
  ./

# Verify the image was created
if [ $? -eq 0 ]; then
  echo "Successfully built $IMAGE_NAME:$TAG"
  docker images | grep "$IMAGE_NAME"
else
  echo "Failed to build $IMAGE_NAME:$TAG"
  exit 1
fi