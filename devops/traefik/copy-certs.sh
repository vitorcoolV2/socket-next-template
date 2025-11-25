#!/bin/bash

# Change to script directory
cd "$(dirname "$0")"

echo "Working directory: $(pwd)"

docker compose down

sleep 2

echo "COPY step home2500.local certificates..."
mkdir -p traefik/certs
sudo chown -R 1001:1001 traefik/certs
sudo cp -R ../step-ca/step/web-certs/home2500.local/ traefik/certs/
sudo cp -R ../step-ca/step/certs/root_ca.crt traefik/certs


# Fix permissions on host
sudo chown -R root:root traefik/certs/
sudo chmod 644 traefik/certs/home2500.local/traefik.cert.pem
sudo chmod 600 traefik/certs/home2500.local/traefik.key.pem

