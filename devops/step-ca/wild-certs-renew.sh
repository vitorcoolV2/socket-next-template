#!/bin/bash
# generate-certs-fixed.sh - Gerar certificados TLS corretamente

set -e

HOST_NAME="home2500.local"
CERTS_TARGET_DIR="step/web-certs/$HOST_NAME"
CONTAINER_PATH="/home/step/web-certs/$HOST_NAME"

echo "🚀 Gerando certificados TLS para ${HOST_NAME}..."

# Verificar se o container step-ca está rodando
if ! docker ps | grep -q step-ca; then
    echo "📦 Iniciando Step CA..."
    docker compose up -d step-ca
    sleep 15
fi

# Aguardar Step CA ficar pronto
echo "🕐 Aguardando Step CA..."
until curl -k -s https://localhost:8443/health > /dev/null; do
    sleep 5
done

echo "✅ Step CA está pronto!"

# Criar diretórios
mkdir -p ${CERTS_TARGET_DIR}
docker exec step-ca mkdir -p $CONTAINER_PATH

# 🔥 CORREÇÃO: Gerar chave e certificado JUNTOS para garantir correspondência
echo "📄 Gerando certificado com chave correspondente..."

# Primeiro, gerar a chave separadamente para verificar
docker exec -t step-ca step ca certificate ${HOST_NAME} \
    $CONTAINER_PATH/traefik.crt \
    $CONTAINER_PATH/traefik.key \
    --kty RSA \
    --size 2048 \
    --provisioner admin \
    --provisioner-password-file /home/step/secrets/password \
    --san "*.${HOST_NAME}" \
    --san "${HOST_NAME}" \
    --force

# Copiar CA intermediária
docker exec step-ca cp /home/step/certs/intermediate_ca.crt $CONTAINER_PATH/intermediate-ca.crt

# Verificar geração
echo "🔍 Verificando certificados no container:"
docker exec step-ca ls -la $CONTAINER_PATH/

# Copiar para o host
echo "📤 Copiando para o host..."
docker cp step-ca:$CONTAINER_PATH/. ${CERTS_TARGET_DIR}/

# 🔥 CORREÇÃO: Renomear arquivos para o formato que o Traefik espera
cd ${CERTS_TARGET_DIR}
mv traefik.crt traefik.cert.pem
mv traefik.key traefik.key.pem  
mv intermediate-ca.crt intermediate-ca.cert.pem
cd -

echo "🔐 Validando certificados..."

# Verificar se os arquivos existem
echo "1. Verificando arquivos:"
ls -la ${CERTS_TARGET_DIR}/

# Verificar correspondência
echo "2. Verificando correspondência chave-certificado:"

# Método universal para verificar correspondência
CERT_HASH=$(openssl x509 -in ${CERTS_TARGET_DIR}/traefik.cert.pem -noout -pubkey 2>/dev/null | openssl md5)
KEY_HASH=$(openssl pkey -in ${CERTS_TARGET_DIR}/traefik.key.pem -pubout 2>/dev/null | openssl md5)

if [ "$CERT_HASH" = "$KEY_HASH" ] && [ -n "$CERT_HASH" ]; then
    echo "✅ ✅ ✅ CHAVE E CERTIFICADO CORRESPONDEM!"
else
    echo "❌ ❌ ❌ CHAVE E CERTIFICADO NÃO CORRESPONDEM"
    echo "Tentando método alternativo..."
    
    # Método alternativo
    CERT_MOD=$(openssl x509 -in ${CERTS_TARGET_DIR}/traefik.cert.pem -noout -modulus 2>/dev/null | openssl md5)
    KEY_MOD=$(openssl rsa -in ${CERTS_TARGET_DIR}/traefik.key.pem -noout -modulus 2>/dev/null | openssl md5 2>/dev/null)
    
    if [ "$CERT_MOD" = "$KEY_MOD" ] && [ -n "$CERT_MOD" ]; then
        echo "✅ ✅ ✅ CHAVE E CERTIFICADO CORRESPONDEM (método alternativo)"
    else
        echo "❌ ERRO: Chave e certificado não correspondem"
        echo "Vamos tentar regenerar de forma diferente..."
        
        # Tentativa de recuperação
        regenerate_certificates
    fi
fi

# Função de regeneração alternativa
regenerate_certificates() {
    echo "🔄 Regenerando certificados com método alternativo..."
    
    # Gerar chave separadamente primeiro
    docker exec step-ca step crypto keypair $CONTAINER_PATH/traefik.key.pem $CONTAINER_PATH/traefik.pub.pem --kty RSA --size 2048 --no-password --insecure
    
    # Gerar certificado usando a chave existente
    docker exec -t step-ca step ca certificate ${HOST_NAME} \
        $CONTAINER_PATH/traefik.key.pem \
        $CONTAINER_PATH/traefik.cert.pem \
        --kty RSA \
        --size 2048 \
        --provisioner admin \
        --provisioner-password-file /home/step/secrets/password \
        --san "*.${HOST_NAME}" \
        --san "${HOST_NAME}" \
        --san "localhost" \
        --san "pihole.${HOST_NAME}" \
        --san "kuma.${HOST_NAME}" \
        --san "traefik.${HOST_NAME}" \
        --san "auth.${HOST_NAME}" \
        --force
    
    # Copiar novamente
    docker cp step-ca:$CONTAINER_PATH/traefik.cert.pem ${CERTS_TARGET_DIR}/
    docker cp step-ca:$CONTAINER_PATH/traefik.key.pem ${CERTS_TARGET_DIR}/
    
    # Verificar novamente
    CERT_HASH=$(openssl x509 -in ${CERTS_TARGET_DIR}/traefik.cert.pem -noout -pubkey 2>/dev/null | openssl md5)
    KEY_HASH=$(openssl pkey -in ${CERTS_TARGET_DIR}/traefik.key.pem -pubout 2>/dev/null | openssl md5)
    
    if [ "$CERT_HASH" = "$KEY_HASH" ]; then
        echo "✅ ✅ ✅ AGORA CHAVE E CERTIFICADO CORRESPONDEM!"
    else
        echo "❌ ❌ ❌ FALHA CRÍTICA: Não foi possível gerar chave e certificado correspondentes"
        exit 1
    fi
}

# Informações do certificado
echo "3. Informações do certificado:"
openssl x509 -in ${CERTS_TARGET_DIR}/traefik.cert.pem -text -noout | grep -E "Subject:|Not Before|Not After|DNS:"

echo "🎉 Processo concluído!"
echo "📁 Certificados em: ./${CERTS_TARGET_DIR}/"