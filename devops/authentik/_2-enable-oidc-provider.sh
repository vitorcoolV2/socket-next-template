#!/bin/bash
# --- _2-enable-oidc-provider.sh ---  
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 1. Load Authentik secrets
set -e
. $(realpath ../authentik/_0-authentik_lib.sh)
set +e

# aboult finding out token validity: vault token lookup | grep -E "display_name|policies|ttl"

require_functions \
    require_vars 
    
require_vars DOMAIN VAULT_CACERT AUTHENTIK_ADMIN_USER 

export AUTHENTIK_REDIRECT_1="https://vault.$DOMAIN/ui/vault/auth/oidc/oidc/callback"
export AUTHENTIK_REDIRECT_2="http://localhost:8250/oidc/callback"

export PROVIDER_APP_SLUG="vault-oidc"
export OIDC_CLIENT_ID="vault-home2500-id"


check_well_known_openid_config() {
    # 1. Verificação de Requisitos
    # Usando verificação direta para evitar problemas com o status de retorno do require_vars
    if [ -z "$VAULT_CACERT" ]; then
        echo "❌ Authentik OIDC: VAULT_CACERT não definido."
        echo "Antes de continuar, mude o serviço Vault para HTTPS."
        return 1
    fi    
    require_vars "VAULT_CACERT" "AUTHENTIK_API_TOKEN" "DOMAIN" "INTERNAL_DOMAIN" "PROVIDER_APP_SLUG"

    # 2. Configuração de URLs e Parâmetros
    local local_url="http://authentik-server.$INTERNAL_DOMAIN:9000"
    local proxy_url="https://auth.$DOMAIN"
    local suffix="application/o/${PROVIDER_APP_SLUG}/.well-known/openid-configuration"
    
    local max_retries=${1:-5}
    local exit_on_error=${2:-"true"}

    # Variáveis para armazenar estado/erros
    local success="none"
    local error_local=""
    local error_proxy=""

    # --- FASE 1: TESTE LOCAL ---
    echo "📡 FASE 1: Testando conexão Interna (Backend): $local_url"
    for ((i=1; i<=max_retries; i++)); do
        local resp=$(curl -sL -k --max-time 3 "$local_url/$suffix")
        if echo "$resp" | grep -q '"issuer"'; then
            echo "✅ Authentik OIDC available at $local_url/$suffix"
            success="partial"
            break
        fi
        echo "⏳ Tentativa Local $i/$max_retries falhou..."
        [ $i -eq $max_retries ] && error_local="Falha total no host local ($local_url)"
        sleep 2
    done

    # --- FASE 2: TESTE PROXY (Só corre se o local for bem succedido) ---
    if [ "$success" = "partial" ]; then
        echo "📡 FASE 2: Testando conexão Externa (Proxy): $proxy_url"
        for ((i=1; i<=max_retries; i++)); do
            local resp=$(curl -sL -k --max-time 3 "$proxy_url/$suffix")
            if echo "$resp" | grep -q '"issuer"'; then
                echo "✅ Authentik OIDC available at $proxy_url/$suffix"
                success="complete"
                break
            fi
            echo "⏳ Tentativa Proxy $i/$max_retries falhou..."
            [ $i -eq $max_retries ] && error_proxy="Falha total no host proxy ($proxy_url)"
            sleep 2
        done
    fi

    # 3. Relatório Final
    if [ "$success" = "complete" ]; then
        [ -z $error_local ] || echo "👉 Erro Interno: $error_local"
        [ -z $error_proxy ] || echo "👉 Erro Proxy:   $error_proxy"
        return 0
    else
        echo "------------------------------------------------------------"
        echo "❌ ERRO CRÍTICO: OIDC indisponível em ambos os caminhos!"
        [ -z $error_local ] || echo "👉 Erro Interno: $error_local"
        [ -z $error_proxy ] || echo "👉 Erro Proxy:   $error_proxy"
        echo $resp | jq .        
        echo "Verifique se o App Slug '$PROVIDER_APP_SLUG' existe no Authentik."
        echo "------------------------------------------------------------"
        
        if [ "$exit_on_error" = "true" ]; then    
            return 1
        else
            return 1
        fi
    fi
}
export -f check_well_known_openid_config
# kind of private func 
_setup_vault_oidc_provider() {
    export PROVIDER_NAME="vault-provider"
    required DOMAIN PROVIDER_NAME PROVIDER_APP_SLUG AUTHENTIK_REDIRECT_1 AUTHENTIK_REDIRECT_2 OIDC_CLIENT_SECRET_KEY

    echo "🔐 Iniciando configuração do Vault OIDC Provider..."
    
    # 1. Definições de Rede
    
    
    # --- 2. Coleta de PKs Necessários ---
    fetch_pk() {
        curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
            "https://auth.$DOMAIN/api/v3/$2/?slug=$1" | jq -r '.results[0].pk // empty'
    }

    local OIDC_AUTHO_FLOW_PK=$(fetch_pk "default-provider-authorization-implicit-consent" "flows/instances")
    local OIDC_AUTHE_FLOW_PK=$(fetch_pk "default-authentication-flow" "flows/instances")
    local OIDC_INVALIDATION_FLOW_PK=$(fetch_pk "default-provider-invalidation-flow" "flows/instances")

    # Busca o certificado (Necessário para assinar os tokens OIDC)
    local SIGN_KEY_PK=$(curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
        "https://auth.$DOMAIN/api/v3/crypto/certificatekeypairs/?name__icontains=self-signed" \
        | jq -r '.results[0].pk // empty')

    # Busca os Scopes (email, profile, openid)
    local PROPERTY_MAPPINGS=$(curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
        "https://auth.$DOMAIN/api/v3/propertymappings/all/?managed__startsWith=goauthentik.io/providers/oauth2/scope-" \
        | jq -c 'if .results == null then [] else [.results[].pk] end')

    # --- 3. Garantir que a Application existe ---
    echo "📦 Garantindo existência da Application: $PROVIDER_APP_SLUG"
    local APP_CHECK=$(curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
        "https://auth.$DOMAIN/api/v3/core/applications/$PROVIDER_APP_SLUG/")
    
    if [[ "$APP_CHECK" == *"Not Found"* ]]; then
        curl -s -k -X POST "https://auth.$DOMAIN/api/v3/core/applications/" \
            -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"name\": \"Vault\", \"slug\": \"$PROVIDER_APP_SLUG\", \"group\": \"Infrastructure\"}"
    fi

    # --- 4. Limpeza de Provider Antigo (Idempotência) ---
    local EXISTING_PROVIDER_PK=$(curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
        "https://auth.$DOMAIN/api/v3/providers/oauth2/?name=$PROVIDER_NAME" | jq -r '.results[0].pk // empty')

    if [ -n "$EXISTING_PROVIDER_PK" ]; then
        echo "🗑️ Removendo Provider antigo..."
        curl -s -k -X DELETE -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
            "https://auth.$DOMAIN/api/v3/providers/oauth2/$EXISTING_PROVIDER_PK/"
    fi

    # --- 5. Criação do Provider OIDC ---
    echo "🏗️ Criando Provider OIDC..."
    local PROVIDER_JSON=$(jq -n \
        --arg name "$PROVIDER_NAME" \
        --arg cid "$OIDC_CLIENT_ID" \
        --arg csec "$OIDC_CLIENT_SECRET_KEY" \
        --arg sign "$SIGN_KEY_PK" \
        --arg auth_f "$OIDC_AUTHE_FLOW_PK" \
        --arg auto_f "$OIDC_AUTHO_FLOW_PK" \
        --arg inva_f "$OIDC_INVALIDATION_FLOW_PK" \
        --arg r1 "$AUTHENTIK_REDIRECT_1" \
        --arg r2 "$AUTHENTIK_REDIRECT_2" \
        --argjson prop_mappings "$PROPERTY_MAPPINGS" \
        '{
            "name": $name,
            "authentication_flow": $auth_f,
            "authorization_flow": $auto_f,
            "invalidation_flow": $inva_f,
            "property_mappings": $prop_mappings,
            "client_id": $cid,
            "client_secret": $csec,
            "signing_key": $sign,
            "client_type": "confidential",
            "access_code_validity": "minutes=1",
            "token_validity": "hours=24",
            "include_claims_in_id_token": true,
            "issuer_mode": "per_provider",
            "redirect_uris": [
                {"url": $r1, "matching_mode": "strict"},
                {"url": $r2, "matching_mode": "strict"}
            ]
        }')

    local PROV_RESPONSE=$(curl -s -k -X POST "https://auth.$DOMAIN/api/v3/providers/oauth2/" \
        -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$PROVIDER_JSON")

    local NEW_PROV_PK=$(echo "$PROV_RESPONSE" | jq -r '.pk // empty')

    if [ -z "$NEW_PROV_PK" ]; then
        echo "❌ Erro ao criar Provider OIDC. Resposta:"
        echo "$PROV_RESPONSE" | jq .
        return 1
    fi

    # --- 6. O PASSO FINAL: Ligar Provider à Application ---
    echo "🔗 Vinculando Provider à Application..."
    curl -s -k -X PATCH "https://auth.$DOMAIN/api/v3/core/applications/$PROVIDER_APP_SLUG/" \
        -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"provider\": $NEW_PROV_PK}" | jq

    echo "✅ Vault OIDC Link completo."
    echo "📍 Issuer URL: https://auth.$DOMAIN/application/o/$PROVIDER_APP_SLUG/.well-known/openid-configuration"
    return 0
}




# Describe the flow
enable_oidc_well_known_openid_flow() {
    #ak_api_token_generate
    #_setup_vault_oidc_provider
    
    check_well_known_openid_config 

    blue_outpost_sync
    ak_fix_proxied_redir

    # and voila
    check_well_known_openid_config

}
export -f enable_oidc_well_known_openid_flow


echo ""
echo "Available function:"
echo "enable_oidc_well_known_openid_flow"
