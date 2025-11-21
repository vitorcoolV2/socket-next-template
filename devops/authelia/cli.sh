#!/bin/bash

# Check if Docker Compose is installed

# Check if the 'authelia' service exists in Docker Compose
if ! docker compose ps authelia &> /dev/null; then
    echo "Error: The 'authelia' service does not exist in your Docker Compose setup."
    exit 1
fi

# Relay arguments to the 'authelia' command inside the container
docker compose exec authelia authelia "$@"