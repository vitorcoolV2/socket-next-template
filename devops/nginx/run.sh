#!/bin/bash

# Change to script directory
cd "$(dirname "$0")"

echo "Working directory: $(pwd)"

docker compose down

echo "COPY certs..."
sudo cp -R ../step-ca/step/web-certs/home2500.local/ certs
sudo chown -R 1001:1001 certs
sudo chmod -R 755 certs

echo "RUN NGINX"
docker compose up -d web-server