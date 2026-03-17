#!/bin/bash
# Filename: _3-pki-architect-setup.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ./vault_lib.sh

vault_switch http
vault_unseal


set -e
FORCE_CA=false
[[ "$1" == "--renew-ca" ]] && FORCE_CA=true
FORCE_INT_CA=false
[[ "$1" == "--renew-int-ca" || "$FORCE_CA" == "true" ]] && FORCE_INT_CA=true

if $FORCE_INT_CA; then
    echo "⚠️  FORCE MODE: A recriar Intermediate CA!"
fi
if $FORCE_CA; then
    echo "⚠️  FORCE MODE: A recriar CA!"
fi


# Use SECURE_VAULT_ADDR for AIA/CRL URLs
SECURE_CONFIG_FILE=$(realpath "./config/vault-https.hcl")
VAULT_URL=$(yq -oy '.api_addr' "$SECURE_CONFIG_FILE")

echo "🚀 Starting PKI Architect Setup for: $DOMAIN" &>2

vault_request_root_token || return 1

if $FORCE_CA || ! vault secrets list | grep -q "^pki/"; then
    
    if $FORCE_CA; then
        echo "🗑️  Limpando PKI existente..." &>2
        vault secrets disable pki || true
    fi

    echo "📦 Enabling Root PKI..." &>2
    vault secrets enable pki
    vault secrets tune -max-lease-ttl=87600h pki
    
    echo "🏗️ Generating $VAULT_PKI_CN Root CA (Exported)..." &>2
    ROOT_DATA=$(vault write -format=json pki/root/generate/exported \
        common_name="$VAULT_PKI_CN Root CA" \
        ttl=87600h \
        issuer_name="$VAULT_ROOT_CA_NAME")
    
    ROOT_CERT=$(echo "$ROOT_DATA" | jq -r '.data.certificate')    
    ROOT_KEY=$(echo "$ROOT_DATA" | jq -r '.data.private_key')

    echo "kp_save root-ca" &>2
    set +e
    kp_save_ca_pair "vault/pki/root-ca" "$ROOT_CERT" "$ROOT_KEY"
    set -e    

else
    echo "ℹ️ Root PKI já ativa. A sincronizar com KeePass... (descructive --renew-ca)" &>2
    # Se já existe, garantimos que o ficheiro local e a BD estão em dia
    ROOT_CERT=$(vault read -field=certificate pki/cert/ca)

    # Get Public Cert from Notes
    #ROOT_CERT=$(echo "$DB_PASS" | keepassxc-cli show -q -a notes "$KP_DB" "vault/pki/root-ca")
    # Get Private Key from Custom Attributes
    ROOT_KEY=$(echo "$DB_PASS" | keepassxc-cli show -q -a password "$KP_DB" "vault/pki/root-ca")

    # Nota: A chave privada não pode ser lida se for 'internal', 
    # por isso confiamos na que já está no KeePass ou na geração inicial.
fi

# --- Logo após gerar a Root CA na Fase 2 ---
echo "🔗 Configuring Root AIA/CRL URLs..." &>2
vault write pki/config/urls \
    issuing_certificates="$VAULT_URL/v1/pki/ca" \
    crl_distribution_points="$VAULT_URL/v1/pki/crl" \
    ocsp_servers="$VAULT_URL/v1/pki/ocsp"


# --- 3. Setup Intermediate CA ---
if ! vault secrets list | grep -q "^pki_int/"; then
    echo "📦 Enabling Intermediate PKI..." &>2
    vault secrets enable -path=pki_int pki
    vault secrets tune -max-lease-ttl=43800h pki_int
fi

# ---- 5.
echo "📜 Creating Steward Issuance Role..." &>2
vault_create_home_server_role
echo "✅ Architect Phase Complete." &>2


SAVE_ROOT_TOKEN="${VAULT_TOKEN}"

# ---- 6. Check if Intermediate is already signed
if $FORCE_INT_CA || ! vault read -field=certificate pki_int/ca/pem >/dev/null 2>&1; then
    echo "📝 Generating Intermediate CSR..." &>2

    ## Only Root can enable disable pki_int 
    vault secrets disable pki_int
    vault secrets enable -path=pki_int pki

    # 1. Gerar CSR e guardar a chave internamente (pendente)
    CSR=$(vault write -format=json pki_int/intermediate/generate/internal \
        common_name="$VAULT_PKI_CN Intermediate CA" ttl=43800h | jq -r '.data.csr')

    RESPONSE=$(vault write -format=json pki/root/sign-intermediate \
        csr="$CSR" format=pem ttl=43800h | jq -r '.')
    CERT=$(echo "$RESPONSE"  | jq -r '.data.certificate')
    CERT_PK=$(echo "$ROOT_DATA" | jq -r '.data.private_key')
    # O correto: pega no array e junta os elementos com \n
    CA_CHAIN=$(echo "$RESPONSE" | jq -r '.data.ca_chain | join("\n")')
    ISSUER_CERT=$(echo "$RESPONSE" | jq -r '.data.issuing_ca')

    echo "🔗 Setting signed Intermediate certificate..." &>2
    echo $CA_CHAIN
    # 2. Use existing vars to ROOT CA
    ROOT_CERT=${ROOT_CERT}
    ROOT_KEY=${ROOT_KEY}
            
    ROOT_KEY=$(echo "$ROOT_DATA" | jq -r '.data.private_key')


    ## Only Root can sign pki_int
    printf "%s" "$CA_CHAIN" | \
        vault write pki_int/intermediate/set-signed certificate=-

    echo "kp_save int-ca" &>2
    set +e
    kp_save_ca_pair "vault/pki_int/intermediate" "$CERT" "$CERT_PK"
    set -e    
        
    
    # 4. REMOVE os comandos de 'issuers' e 'replace-default' que estão a dar erro 404/405
    # O Vault 1.21.1 activará automaticamente este certificado como default no set-signed.
else
    echo "ℹ️ Intermediate PKI ativa. use arg: --renew-int-ca, replace current" &>2
fi

# ---- 7. FASE: PERSISTÊNCIA DE CONFIANÇA (The "Trusted CA" Logic) ---
# Exporta o certificado da Root para ficheiro local se a PKI já existir
# Isso alimenta o CURL_CA_OPTS nos próximos scripts
# ... dentro da FASE: PERSISTÊNCIA ...
TEMP_BUNDLE=$(mktemp)
{
    vault read -field=certificate pki_int/cert/ca 2>/dev/null
    echo "" 
    vault read -field=certificate pki/cert/ca 2>/dev/null
} > "$TEMP_BUNDLE"

if [ -s "$TEMP_BUNDLE" ]; then
    mv "$TEMP_BUNDLE" "$TRUSTED_CA_FILE"
    echo "✅ Trusted CA Bundle updated." &>2
else
    echo "❌ Failed to fetch certificates. Keeping old bundle." &>2
    rm "$TEMP_BUNDLE"
fi
#
TEMP_INTCA=$(mktemp)
INT_CA_FILE="$(dirname $TRUSTED_CA_FILE)/int-ca.pem"
{
    vault read -field=certificate pki_int/cert/ca 2>/dev/null    
} > "$TEMP_INTCA"
if [ -s "$TEMP_INTCA" ]; then
    mv "$TEMP_INTCA" "$INT_CA_FILE"
    echo "✅ Root CA updated." &>2
else
    echo "❌ Failed to fetch certificates. Keeping old bundle." &>2
    rm "$TEMP_INTCA"
fi


####
TEMP_ROOTCA=$(mktemp)
ROOT_CA_FILE="$(dirname $TRUSTED_CA_FILE)/int-ca.pem"
{
    vault read -field=certificate pki/cert/ca 2>/dev/null
} > "$TEMP_ROOTCA"
if [ -s "$TEMP_ROOTCA" ]; then
    mv "$TEMP_ROOTCA" "$ROOT_CA_FILE"
    echo "✅ Intermediate CA updated." &>2
else
    echo "❌ Failed to fetch certificates. Keeping old." &>2
    rm "$TEMP_ROOTCA"
fi




echo "🔧 Setting default issuer..."
# ---- 8. Get the first Issuer ID available
ISSUER_ID=$(vault list -format=json pki_int/issuers | jq -r '.[]' | head -n 1)

if [ -n "$ISSUER_ID" ]; then
    # Correct Command: Set the default issuer using the specialized 'config/issuers' endpoint
    # Note: We are NOT changing the issuer_name, we are changing the default pointer
    vault write pki_int/config/issuers default="$ISSUER_ID"
    echo "✅ Default issuer set to $ISSUER_ID"
else
    echo "❌ No issuers found to set as default."
fi


