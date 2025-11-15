#!/bin/bash
KEY_FILE="step/web-certs/home2500.local/traefik.key.pem"
CERT_FILE="step/web-certs/home2500.local/traefik.cert.pem"

echo "🔧 DEBUG - Problema no OpenSSL"

echo "1. Verificando arquivos:"
ls -la $KEY_FILE
ls -la $CERT_FILE

echo ""
echo "2. Tentando openssl rsa:"
openssl rsa -in $KEY_FILE -noout -text 2>&1 | head -3

echo ""
echo "3. Tentando openssl ec:"
openssl ec -in $KEY_FILE -noout -text 2>&1 | head -3

echo ""
echo "4. Verificando modulus com diferentes métodos:"
echo "Método 1 - openssl x509:"
openssl x509 -in $CERT_FILE -noout -modulus 2>/dev/null | openssl md5

echo "Método 2 - openssl rsa:"
openssl rsa -in $KEY_FILE -noout -modulus 2>/dev/null | openssl md5

echo "Método 3 - openssl ec:"
openssl ec -in $KEY_FILE -noout -modulus 2>/dev/null | openssl md5

echo ""
echo "5. Verificando se a chave é ECDSA:"
openssl ec -in $KEY_FILE -noout 2>/dev/null && echo "✅ É chave ECDSA" || echo "❌ Não é ECDSA"

echo ""
echo "6. Extraindo chave pública do certificado:"
openssl x509 -in $CERT_FILE -noout -pubkey 2>/dev/null | openssl md5

echo "7. Extraindo chave pública da chave privada:"
openssl ec -in $KEY_FILE -pubout 2>/dev/null | openssl md5