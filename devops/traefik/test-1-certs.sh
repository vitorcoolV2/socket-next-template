#!/bin/bash

# Change to script directory
cd "$(dirname "$0")"

echo "Working directory: $(pwd)"

WEB_CERTS_FOLDER='traefik/certs'

# Check if your certificate files exist and have content
ls -la $WEB_CERTS_FOLDER/
file $WEB_CERTS_FOLDER/traefik.cert.pem
file $WEB_CERTS_FOLDER/traefik.key.pem

# Check certificate content
# Run a temporary Alpine container with OpenSSL to validate certificates
docker run --rm -v $(pwd)/traefik/certs:/certs alpine sh -c "
  echo '🔐 INSTALLING OPENSSL...'
  apk add --no-cache openssl > /dev/null 2>&1
  echo '✅ OPENSSL INSTALLED'
  ls -la certs
  ls -la certs/home2500.local
  echo ''
  echo '📊 CERTIFICATE VALIDATION REPORT'
  echo '================================'
  
  echo -e '\n📅 1. VALIDITY DATES:'
  openssl x509 -in /certs/home2500.local/traefik.cert.pem -noout -dates
  
  echo -e '\n👤 2. SUBJECT/ISSUER:'
  openssl x509 -in /certs/home2500.local/traefik.cert.pem -noout -subject -issuer
  
  echo -e '\n✅ 3. EXPIRATION CHECK:'
  openssl x509 -in /certs/home2500.local/traefik.cert.pem -noout -checkend 0
  
  echo -e '\n🌐 4. SUBJECT ALTERNATIVE NAMES:'
  openssl x509 -in /certs/home2500.local/traefik.cert.pem -noout -ext subjectAltName 
  
  echo -e '\n🔑 5. PRIVATE KEY VALIDATION:'
  openssl rsa -in /certs/home2500.local/traefik.key.pem -check -noout 
  
  echo -e '\n🔄 6. CERTIFICATE-KEY PAIR MATCH:'
  CERT_MOD=\$(openssl x509 -noout -modulus -in /certs/home2500.local/traefik.cert.pem 2>/dev/null | openssl md5 | cut -d' ' -f2)
  KEY_MOD=\$(openssl rsa -noout -modulus -in /certs/home2500.local/traefik.key.pem 2>/dev/null | openssl md5 | cut -d' ' -f2)
  if [ \"\$CERT_MOD\" = \"\$KEY_MOD\" ] && [ -n \"\$CERT_MOD\" ]; then
    echo '✅ Certificate and private key MATCH'
    echo '   Modulus MD5: ' \$CERT_MOD
  else
    echo '❌ Certificate and private key DO NOT MATCH'
    echo '   Cert modulus: ' \$CERT_MOD
    echo '   Key modulus:  ' \$KEY_MOD
  fi
  
  echo -e '\n📋 7. CERTIFICATE DETAILS:'
  openssl x509 -in /certs/home2500.local/traefik.cert.pem -text -noout 2>/dev/null | head -20
"

echo ""
echo "#"
