#!/bin/bash

# Change to script directory
cd "$(dirname "$0")"
echo "Working directory: $(pwd)"
docker compose authelia -d
docker compose run --rm authelia authelia config validate --config /config/configuration.yml