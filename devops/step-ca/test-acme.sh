#!/bin/bash

# Variables
CA_URL="https://step-ca:8443"
DOMAIN="test.example.com"
EMAIL="admin@example.com"
ROOT_CA_CERT="./step/certs/root_ca.crt"

# Helper function to handle errors
function check_response() {
  if [[ $? -ne 0 ]]; then
    echo "Error: $1"
    exit 1
  fi
}

# Step 1: Fetch a Nonce
echo "Fetching nonce..."
NONCE=$(curl -s -o /dev/null -w "%{http_code}" -I "$CA_URL/acme/acme/new-nonce" --cacert "$ROOT_CA_CERT")
check_response "Failed to fetch nonce."

echo "Nonce fetched successfully."

# Step 2: Create an Account
echo "Creating a new ACME account..."
ACCOUNT_PAYLOAD='{
  "termsOfServiceAgreed": true,
  "contact": ["mailto:'"$EMAIL"'"]
}'
ACCOUNT_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/jose+json" \
  --data "$ACCOUNT_PAYLOAD" \
  "$CA_URL/acme/acme/new-account" \
  --cacert "$ROOT_CA_CERT")
check_response "Failed to create account."

ACCOUNT_LOCATION=$(echo "$ACCOUNT_RESPONSE" | jq -r '.location')
echo "Account created successfully. Location: $ACCOUNT_LOCATION"

# Step 3: Place an Order
echo "Placing a new order for domain '$DOMAIN'..."
ORDER_PAYLOAD='{
  "identifiers": [{"type": "dns", "value": "'"$DOMAIN"'"}]
}'
ORDER_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/jose+json" \
  --data "$ORDER_PAYLOAD" \
  "$CA_URL/acme/acme/new-order" \
  --cacert "$ROOT_CA_CERT")
check_response "Failed to place order."

ORDER_URL=$(echo "$ORDER_RESPONSE" | jq -r '.orderUrl')
AUTHZ_URL=$(echo "$ORDER_RESPONSE" | jq -r '.authorizations[0]')
echo "Order placed successfully. Order URL: $ORDER_URL"

# Step 4: Validate the Challenge
echo "Fetching authorization details..."
AUTHZ_RESPONSE=$(curl -s "$AUTHZ_URL" --cacert "$ROOT_CA_CERT")
check_response "Failed to fetch authorization details."

CHALLENGE_URL=$(echo "$AUTHZ_RESPONSE" | jq -r '.challenges[0].url')
TOKEN=$(echo "$AUTHZ_RESPONSE" | jq -r '.challenges[0].token')

echo "Simulating challenge validation..."
# Simulate HTTP-01 challenge by creating a file at the token path
mkdir -p "./.well-known/acme-challenge"
echo "$TOKEN" > "./.well-known/acme-challenge/$TOKEN"

# Notify the CA that the challenge is ready
VALIDATION_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/jose+json" \
  --data '{"keyAuthorization": "'"$TOKEN"'"}' \
  "$CHALLENGE_URL" \
  --cacert "$ROOT_CA_CERT")
check_response "Failed to validate challenge."

echo "Challenge validated successfully."

# Step 5: Finalize the Order
echo "Finalizing the order..."
CSR=$(openssl req -new -newkey rsa:2048 -nodes -keyout private.key -subj "/CN=$DOMAIN" -out csr.pem)
FINALIZE_URL=$(echo "$ORDER_RESPONSE" | jq -r '.finalize')
FINALIZE_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/jose+json" \
  --data "$(cat csr.pem)" \
  "$FINALIZE_URL" \
  --cacert "$ROOT_CA_CERT")
check_response "Failed to finalize order."

CERT_URL=$(echo "$FINALIZE_RESPONSE" | jq -r '.certificate')
echo "Order finalized successfully. Certificate URL: $CERT_URL"

# Step 6: Download the Certificate
echo "Downloading the issued certificate..."
curl -s "$CERT_URL" --cacert "$ROOT_CA_CERT" -o "$DOMAIN.crt"
check_response "Failed to download certificate."

echo "Certificate downloaded successfully: $DOMAIN.crt"

# Optional: Revoke the Certificate
echo "Revoking the certificate..."
REVOKE_PAYLOAD='{
  "certificate": "'"$(cat "$DOMAIN.crt")"'"
}'
REVOKE_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/jose+json" \
  --data "$REVOKE_PAYLOAD" \
  "$CA_URL/acme/acme/revoke-cert" \
  --cacert "$ROOT_CA_CERT")
check_response "Failed to revoke certificate."

echo "Certificate revoked successfully."