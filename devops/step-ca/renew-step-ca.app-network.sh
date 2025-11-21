#!/bin/bash
# generate-certs.sh 

set -e  # Sai no primeiro erro

# Carregar variáveis do .env se existir
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

HOST_NAME="step-ca.app-network"
CERTS_TARGET_DIR="step/web-certs/$HOST_NAME"
CONTAINER_PATH="/home/step/web-certs/$HOST_NAME"

echo "🚀 Gerando certificados TLS para ${HOST_NAME}..."

# Verificar se o container step-ca está rodando
if ! docker ps | grep -q step-ca; then
    echo "📦 Container step-ca não está rodando. Iniciando..."
    docker compose up -d step-ca
    echo "⏳ Aguardando Step CA inicializar..."
    sleep 15
fi

# Aguardar Step CA ficar pronto
echo "🕐 Aguardando Step CA ficar pronto..."
until curl -k -s https://localhost:8443/health > /dev/null; do
    echo "⏳ Step CA ainda não responde, aguardando..."
    sleep 5
done

echo "✅ Step CA está pronto!"

# Criar diretórios
mkdir -p ${CERTS_TARGET_DIR}
docker exec step-ca mkdir -p $CONTAINER_PATH

# Gerar certificado
echo "📄 Gerando certificado para ${HOST_NAME}..."
docker exec -t step-ca step ca certificate ${HOST_NAME} \
    $CONTAINER_PATH/cert.pem \
    $CONTAINER_PATH/key.pem \
    --provisioner admin \
    --provisioner-password-file /home/step/secrets/password \
    --san "*.${HOST_NAME}" --san "${HOST_NAME}" --san "localhost" \
    --kty RSA \
    --size 2048 \
    --force

# Copiar CA intermediária
echo "📋 Copiando CA intermediária..."
docker exec step-ca cp /home/step/certs/intermediate_ca.crt $CONTAINER_PATH/intermediate-ca.crt

echo "📋 Copiando CA root..."
docker exec step-ca cp /home/step/certs/root_ca.crt $CONTAINER_PATH/root_ca.crt


# Verificar geração no container
echo "🔍 Verificando certificados no container:"
docker exec step-ca ls -la $CONTAINER_PATH/

# Copiar para o host
echo "📤 Copiando certificados para o host..."
docker cp step-ca:$CONTAINER_PATH/. ${CERTS_TARGET_DIR}/

# Verificar no host
echo "🔍 Verificando certificados no host:"
ls -la $CERTS_TARGET_DIR/

# Validar certificados
echo "🔐 Validando certificados..."
echo "1. Informações do certificado:"
openssl x509 -in ${CERTS_TARGET_DIR}/cert.pem -text -noout | grep -E "Subject:|Not Before|Not After|DNS:"

echo "2. Verificando correspondência chave-certificado:"
CERT_MODULUS=$(openssl x509 -in ${CERTS_TARGET_DIR}/cert.pem -noout -modulus 2>/dev/null | openssl md5)
KEY_MODULUS=$(openssl rsa -in ${CERTS_TARGET_DIR}/key.pem -noout -modulus 2>/dev/null | openssl md5 2>/dev/null || 
              openssl ec -in ${CERTS_TARGET_DIR}/key.pem -noout -text 2>/dev/null | grep -A5 "pub:" | tail -1 | tr -d ' :' | openssl md5)

if [ "$CERT_MODULUS" = "$KEY_MODULUS" ] && [ -n "$CERT_MODULUS" ]; then
    echo "✅ Chave e certificado correspondem!"
else
    echo "❌ Chave e certificado NÃO correspondem"
    exit 1
fi

echo "🎉 Certificados gerados com sucesso!"
echo "📁 Local: ./${CERTS_TARGET_DIR}/"
