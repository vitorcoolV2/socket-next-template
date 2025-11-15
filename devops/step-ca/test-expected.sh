#!/bin/bash
echo "=== Testing Step CA with curl ==="

echo "1. Testing health endpoint:"
curl -k -s https://localhost:8443/health && echo " ✅" || echo " ❌"

echo "2. Testing ACME directory:"
curl -k -s https://localhost:8443/acme/acme/directory | jq . 2>/dev/null && echo " ✅" || curl -k -s https://localhost:8443/acme/acme/directory

echo "3. Testing root certificate:"
curl -k -s https://localhost:8443/roots.pem | head -3 && echo " ✅"

echo "4. Testing internal network:"
docker exec step-acme curl -k -s https://step-ca:8443/health && echo " ✅" || echo " ❌"


# Quick ACME check  
curl -k -s https://localhost:8443/acme/acme/directory | grep -q "newNonce" && echo "✅ ACME Working" || echo "❌ ACME Broken"

# Test if we can get a certificate via ACME
curl -k -X POST https://localhost:8443/acme/acme/new-order \
  -H "Content-Type: application/json" \
  -d '{"identifiers": [{"type": "dns", "value": "home2500.local"}]}'

  
  
openssl genpkey -algorithm RSA -out account.key
curl -k -X POST https://localhost:8443/acme/acme/new-account \
  -H "Content-Type: application/jose+json" \
  --data-binary @-<<EOF
{
  "protected": "$(echo -n '{"alg":"RS256","jwk":'$(cat account.key | step crypto jwk keypair -f pem | jq -c .public_key)',"nonce":"NONCE_FROM_CA","url":"https://localhost:8443/acme/acme/new-account"}' | base64 -w0)",
  "payload": "$(echo -n '{"termsOfServiceAgreed":true}' | base64 -w0)",
  "signature": "$(echo -n '{"protected":...,"payload":...}' | openssl dgst -sha256 -sign account.key | base64 -w0)"
}
EOF  
echo "=== Test Complete ==="