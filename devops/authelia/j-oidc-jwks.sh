#!/bin/bash

# Generate RSA private key
openssl genrsa -out data/authelia/secrets/oidc.key 2048

# Generate public key
openssl rsa -in data/authelia/secrets/oidc.key -pubout -out data/authelia/secrets/oidc.pub

# Extract modulus and convert to proper Base64 format
N=$(openssl rsa -in data/authelia/secrets/oidc.key -modulus -noout | cut -d= -f2)
# Convert hex to binary and then to base64
N_BASE64=$(echo $N | xxd -r -p | base64 -w0 | tr '/+' '_-' | tr -d '=')

echo "Modulus (N): $N_BASE64"

# Create JWKS file with proper formatting
cat > data/authelia/secrets/jwks.json << EOF
{
  "keys": [
    {
      "kty": "RSA",
      "use": "sig", 
      "kid": "1",
      "alg": "RS256",
      "n": "$N_BASE64",
      "e": "AQAB"
    }
  ]
}
EOF

echo "JWKS file created at data/authelia/secrets/jwks.json"