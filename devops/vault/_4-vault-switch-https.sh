#!/bin/bash

# ALL SCRIPT WORKS RELATIVELY TO ITS PERSISTENCE FOLDER 
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

. ./vault_lib.sh

vault_switch http || return 1
vault_unseal || return 1
vault_request_stew_token || return 1

vault__self_certificate || return 1

openssl crl2pkcs7 -nocrl -certfile ../traefik/traefik/certs/traefik-fullchain.pem | openssl pkcs7 -print_certs -noout

echo "Test availability"
# must resolve first of all
echo | openssl s_client -connect 172.28.0.6:443 -servername 172.28.0.6 2>/dev/null | openssl x509 -noout -issuer -subject -datest -issuer -subject -dates

# check ip resolution to expected names
curl $CURL_CA_OPTS \
    --resolve vault.$INTERNAL_DOMAIN:443:172.28.0.6 \
    https://vault.$INTERNAL_DOMAIN:443/v1/pki_int/ca/pem

echo ""

echo "✨ Vault está pronto e usando HTTPS!"
