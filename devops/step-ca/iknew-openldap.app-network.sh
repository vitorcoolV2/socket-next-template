#!/bin/bash

set -e

# Change to script directory
cd "$(dirname "$0")"

echo "Working directory: $(pwd)"

#### powerfull name bounder. stop docker container, define certs prefix,
PREFIX_NAME="openldap"


docker stop $PREFIX_NAME || true

HOST_NETWORK_NAME="app-network"

CONTAINER_PATH="/home/step/web-certs/$HOST_NETWORK_NAME"

echo "🚀 Generating TLS certificates for ${HOST_NETWORK_NAME}..."

# Check if step-ca container is running
if ! docker ps | grep -q step-ca; then
    echo "📦 Starting Step CA..."
    docker compose up -d step-ca
    sleep 15
fi

# Wait for Step CA to be ready
echo "🕐 Waiting for Step CA..."
until curl -k -s https://localhost:8443/health > /dev/null; do
    sleep 5
done

echo "✅ Step CA is ready!"

# 🔥 FIX: Generate key and certificate TOGETHER to ensure matching
echo "📄 Generating certificate with matching key..."
echo "HOST_NETWORK_NAME: $HOST_NETWORK_NAME"
echo "CONTAINER_PATH: $CONTAINER_PATH"

# Create directory
if ! docker exec -t step-ca mkdir -p "$CONTAINER_PATH"; then
    echo "❌ Failed to create directory: $CONTAINER_PATH"
    exit 1
fi

# Verify directory was created
docker exec step-ca ls -la "$CONTAINER_PATH"
echo "$HOST_NETWORK_NAME"
echo "$CONTAINER_PATH/$PREFIX_NAME.cert.pem"
echo "$CONTAINER_PATH/$PREFIX_NAME.key.pem"
docker exec -t step-ca step ca certificate \
    "$HOST_NETWORK_NAME" \
    "$CONTAINER_PATH/$PREFIX_NAME.cert.pem" \
    "$CONTAINER_PATH/$PREFIX_NAME.key.pem" \
    --kty=RSA \
    --size=2048 \
    --provisioner=admin \
    --provisioner-password-file=/home/step/secrets/password \
    --san="*.$HOST_NETWORK_NAME" \
    --san="$HOST_NETWORK_NAME" \
    --san="$PREFIX_NAME.$HOST_NETWORK_NAME" \
    --not-after=24h \
    --force

# Verify generation
echo "🔍 Verifying certificates in container: step-ca path: $CONTAINER_PATH"
docker exec step-ca ls -la "$CONTAINER_PATH"    

# Verify generation
echo "🔍 Verifying certificates in container: step-ca path: $CONTAINER_PATH"
docker exec step-ca ls -la $CONTAINER_PATH/

############## COPY TO TARGET SERVICE CERTIFICATION PATH
COMPOSE_SERVICE_PATH=$(realpath ${PWD}/../openldap)
echo "the service: $COMPOSE_SERVICE_PATH"
sudo mkdir -p $COMPOSE_SERVICE_PATH/ldap/tls
SERVICE_CERT_PATH=$(realpath "${PWD}/../openldap/ldap/tls")

echo "📤 Step-ca copy: ${CONTAINER_PATH} to: ${SERVICE_CERT_PATH}/"

sudo chown -R $USER:$USER ${SERVICE_CERT_PATH}
ls -la ${SERVICE_CERT_PATH}

# copy static path chain validation, the intermediate CA signer
docker cp step-ca:/home/step/web-certs/$HOST_NETWORK_NAME/$PREFIX_NAME.cert.pem "${SERVICE_CERT_PATH}/ldap.crt"
docker cp step-ca:/home/step/web-certs/$HOST_NETWORK_NAME/$PREFIX_NAME.key.pem "${SERVICE_CERT_PATH}/ldap.key"
#docker cp step-ca:/home/step/certs/intermediate_ca.crt "${SERVICE_CERT_PATH}/intermediate-ca.cert.pem"
docker cp step-ca:/home/step/certs/root_ca.crt "${SERVICE_CERT_PATH}/ca.crt"

# 🔥 FIX: Rename files to the format $PREFIX_NAME expects
cd ${SERVICE_CERT_PATH}

echo "🔐 Validating certificates..."

# Check if files exist
echo "1. Checking files:"
ls -la ${SERVICE_CERT_PATH}/

# Verify matching
echo "2. Verifying key-certificate matching:"

# Universal method to verify matching
CERT_HASH=$(openssl x509 -in ${SERVICE_CERT_PATH}/ldap.crt -noout -pubkey 2>/dev/null | openssl md5)
KEY_HASH=$(openssl pkey -in ${SERVICE_CERT_PATH}/ldap.key -pubout 2>/dev/null | openssl md5)

if [ "$CERT_HASH" = "$KEY_HASH" ] && [ -n "$CERT_HASH" ]; then
    echo "✅ ✅ ✅ KEY AND CERTIFICATE MATCH!"
fi

# Certificate information
echo "3. Certificate information:"
openssl x509 -in ${SERVICE_CERT_PATH}/ldap.crt -text -noout 

echo "🎉 Process completed!"
echo "📁 Certificates in: ${SERVICE_CERT_PATH}"

# Fix permissions on host
sudo chmod 644 ${SERVICE_CERT_PATH}/ldap.crt
sudo chmod 600 ${SERVICE_CERT_PATH}/ldap.key
sudo chown -R 911:911 ${SERVICE_CERT_PATH}


# docker restart $PREFIX_NAME -d