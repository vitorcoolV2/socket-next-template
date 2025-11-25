#!/bin/bash

# Change to script directory
cd "$(dirname "$0")"

echo "Working directory: $(pwd)"

./copy-certs.sh

echo "RUN TREAFIK"

docker compose up  -d  

sleep 3

echo "VALIDATING TRAEFIK VALIDITY"
./test-1-certs.sh


echo "VALIDATING home2500 available"
./test-1-available.sh

