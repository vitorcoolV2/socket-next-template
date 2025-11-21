#!/bin/bash

# Change to script directory
cd "$(dirname "$0")"

echo "Working directory: $(pwd)"

docker compose down

sleep 2

echo "COPY step home2500.local certificates..."
mkdir -p traefik/certs

sudo cp -R ../step-ca/step/web-certs/home2500.local/ traefik/certs/
sudo cp -R ../step-ca/step/certs/root_ca.crt traefik/certs
sudo chown -R 1001:1001 traefik/certs

# Fix permissions on host
sudo chown -R root:root traefik/certs/
sudo chmod 644 traefik/certs/home2500.local/traefik.cert.pem
sudo chmod 600 traefik/certs/home2500.local/traefik.key.pem



echo "RUN TREAFIK"

docker compose up  -d  

sleep 3

##### RUN EXPECTED from step-ca, authelia
curl -k -H "Host: auth.home2500.local" https://localhost/ | grep "base href"

# Test whoami service
curl -k -H "Host: whoami.home2500.local" https://localhost/

curl -k -H "Host: pihole.home2500.local" https://localhost/

curl -k -H "Host: portainer.home2500.local" https://localhost/

curl -k -H "Host: kuma.home2500.local" https://localhost/
