#!/bin/bash

# Exit on error
set -e

# Variables
PROJECT_DIR="$(pwd)"
DOCKERFILE="devops/react-app/Dockerfile"
IMAGE_NAME="react-app"
TAG="latest"

# Change to project root if not already there
cd "$PROJECT_DIR" || exit 1

# Load .env file if it exists
if [ -f ".env" ]; then
  echo "Loading environment variables from .env..."
  set -a  # Automatically export all variables
  source .env
  set +a  # Disable automatic export
else
  echo "Warning: .env file not found, proceeding without it."
fi

# Build the Docker image
echo "Building Docker image for React app..."
docker build \
  -f "$DOCKERFILE" \
  --build-arg BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ") \
  --build-arg NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY="${NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY}" \
  -t "$IMAGE_NAME:$TAG" \
  .

# Verify the image was created
if [ $? -eq 0 ]; then
  echo "Successfully built $IMAGE_NAME:$TAG"
  docker images | grep "$IMAGE_NAME"
else
  echo "Failed to build $IMAGE_NAME:$TAG"
  exit 1
fi