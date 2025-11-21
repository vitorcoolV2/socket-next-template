#!/bin/bash

# Change to script directory
cd "$(dirname "$0")"

echo "Working directory: $(pwd)"

WEB_CERTS_FOLDER='traefik/step-certs'

# Check if your certificate files exist and have content
ls -la $WEB_CERTS_FOLDER/
file $WEB_CERTS_FOLDER/traefik.cert.pem
file $WEB_CERTS_FOLDER/traefik.key.pem

# Check certificate content
openssl x509 -in $WEB_CERTS_FOLDER/traefik.cert.pem -text -noout | head -10

# Check if it contains home2500.local
openssl x509 -in $WEB_CERTS_FOLDER/traefik.cert.pem -text -noout | grep -A 5 "Subject:"
openssl x509 -in $WEB_CERTS_FOLDER/traefik.cert.pem -text -noout | grep -A 5 "X509v3 Subject Alternative Name"


echo ""
echo "#"

##### RUN EXPECTED from step-ca, authelia
curl -k -H "Host: auth.home2500.local" https://localhost/ | grep "base href"

# Test whoami service
curl -k -H "Host: whoami.home2500.local" https://localhost/




##### RUN EXPECTED from step-ca, authelia
curl -k -H "Host: auth.home2500.local" https://localhost/ | grep "base href"

# Test whoami service
curl -k -H "Host: whoami.home2500.local" https://localhost/

