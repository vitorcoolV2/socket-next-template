#!/bin/bash

# Change to script directory
cd "$(dirname "$0")"

echo "Working directory: $(pwd)"

docker compose down

echo "RUN CA"
sudo mkdir -p step
sudo chown -R 1001:1001 step
sudo chmod -R 755 step

docker compose up -d step-ca 

# Wait for Step CA to be ready
echo "Aguardando Step CA..."
until curl -k -s https://localhost:8443/health > /dev/null; do
    sleep 2
done

# Get env from root certificate
FINGERPRINT=$(openssl x509 -in step/certs/root_ca.crt -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':')
echo "FINGERPRINT=$FINGERPRINT"

{
  touch .fingerprint
  grep -v "CA_FINGERPRINT=" .fingerprint | grep -v "CA_CONTEXT=" | $CA_CONTEXT
  echo "CA_FINGERPRINT=$FINGERPRINT"
  echo "CA_CONTEXT=$CA_CONTEXT"
  echo "CA_CONTEXT_AUTHORITY=$CA_CONTEXT_AUTHORITY"
} > .fingerprint.tmp && mv .fingerprint.tmp .fingerprint


echo "Step ACME CLIENT start"
docker compose --profile cli up step-acme -d

./renew-host2500.local.sh
./renew-openldap.app-network.sh
./renew-step-ca.app-network.sh

