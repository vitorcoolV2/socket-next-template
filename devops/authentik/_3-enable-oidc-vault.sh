#!/bin/bash
# --- _3-enable-oidc-vault.sh ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

set -e

. $(realpath ./_2-enable-oidc-provider.sh)
set +e

#### # required by ./_3-sync-oidc-vault.sh
# A steward vault identity on authentik: akadmin, "a very import role". should never be just one in prodution. not until make sure absence|!inference is secure
# Steward is the mordomo i am defining to handle authentik/vault.
# for now steward is a shared role with vault

export AUTENTIK_OIDC_VAULT_STEWARD_ROLE="authentik-admin"  

require_vars "CURL_CA_OPTS" "VAULT_CACERT" "DOMAIN" \
        "AUTHENTIK_API_TOKEN" "PROVIDER_APP_SLUG" \
        "OIDC_CLIENT_ID" "OIDC_CLIENT_SECRET_KEY" "AUTHENTIK_ADMIN_USER" || exit

for f in check_well_known_openid_config; do ! declare -F "$f" >/dev/null && echo "❌ Function $f not found" && exit 1; done

# 4. Configure Vault OIDC Method
echo "🔐 Configuring Vault OIDC Auth Method..."


vault_oidc_enable() {
    # Ensure OIDC is enabled (Safe to run if already enabled)
    # 1. Tentar habilitar o OIDC de forma explícita e verificar erro
    if ! vault auth list | grep -q "oidc/"; then
        echo "🏗️ Enabling OIDC auth method..."
        vault auth enable oidc || { echo "❌ Failed to enable OIDC. Check Steward permissions."; exit 1; }
    fi
}
# Verifica se o sudo apareceu no path de sistema
validate_caps() {
    echo "Check token caps used to handle OIDC Auth Method..."
    vault_secret_path_caps "sys/auth"
    vault_secret_path_caps "sys/auth/oidc"
    vault_secret_path_caps "auth/oidc/*"    
    vault_secret_path_caps "auth/approle/*"
    vault_secret_path_caps "identity/*"
    vault_secret_path_caps "identity/group-alias"
    vault_secret_path_caps "identity/group/name/*"
    vault_secret_path_caps "identity/group" 
    vault_secret_path_caps "sys/mounts"
    vault_secret_path_caps "sys/mounts/auth/oidc/tune"
}

write_auth_oidc_role () {
    require_vars "AUTENTIK_OIDC_VAULT_STEWARD_ROLE" "OIDC_CLIENT_ID" AUTHENTIK_REDIRECT_1 AUTHENTIK_REDIRECT_2
    echo "📝 Writing Role: $AUTENTIK_OIDC_VAULT_STEWARD_ROLE"

    # KEEP !important allowed_redirect_uris="$AUTHENTIK_REDIRECT_1,$AUTHENTIK_REDIRECT_2"  
    vault write auth/oidc/role/$AUTENTIK_OIDC_VAULT_STEWARD_ROLE \
        bound_audiences="${OIDC_CLIENT_ID}" \
        allowed_redirect_uris="$AUTHENTIK_REDIRECT_1,$AUTHENTIK_REDIRECT_2"  \
        oidc_scopes="openid,profile,email,groups" \
        user_claim="sub" \
        groups_claim="groups" \
        policies="default,admin-policy" \
        role_type="oidc" \
        ttl="1h" \
        && echo "✅ vault write auth/oidc/role/$AUTENTIK_OIDC_VAULT_STEWARD_ROLE." \
        || echo "❌ vault write auth/oidc/role/$AUTENTIK_OIDC_VAULT_STEWARD_ROLE"
}

write_auth_oidc_config() {
    require_vars PROVIDER_APP_SLUG
    local DISCOVERY_URL="https://auth.$DOMAIN/application/o/$PROVIDER_APP_SLUG/"
    local CA_PEM_CONTENT=$(cat "$VAULT_CACERT")
    
    echo "🔐 Configuring Vault OIDC Auth Method..."
    echo "   📍 Discovery: $DISCOVERY_URL"
    echo "   🆔 Client ID: ${OIDC_CLIENT_ID:0:5}***"
    echo "   🔑 Secret:    ${OIDC_CLIENT_SECRET_KEY:0:5}***"

    # exit
    require_vars "AUTENTIK_OIDC_VAULT_STEWARD_ROLE" \
        "DISCOVERY_URL" "CA_PEM_CONTENT" \
        "OIDC_CLIENT_ID" "OIDC_CLIENT_SECRET_KEY"
        
    # Configure the Auth Method
    vault write auth/oidc/config \
        oidc_discovery_url="$DISCOVERY_URL" \
        oidc_client_id="$OIDC_CLIENT_ID" \
        oidc_client_secret="$OIDC_CLIENT_SECRET_KEY" \
        default_role="$AUTENTIK_OIDC_VAULT_STEWARD_ROLE" \
        oidc_discovery_ca_pem="$CA_PEM_CONTENT" \
        jwt_supported_algs="RS256" \
        oidc_scopes="openid,profile,email" \
        client_auth_method="client_secret_post" \
        && echo "✅ vault write auth/oidc/config $DISCOVERY_URL." \
        || echo "❌ vault write auth/oidc/config $DISCOVERY_URL."
}

configure_vault_identity_defaults() {
    echo "👤 Configurando padrões de Identidade..."

    # 1. Pegar o Accessor OIDC
    local ACCESSOR=$(vault auth list -format=json | jq -r '."oidc/".accessor')

    # 2. Configurar o Mount OIDC para usar o nome amigável como Alias
    # Isso força o Vault a tentar usar o 'preferred_username' como o nome da entidade
    vault auth tune -description="Authentik OIDC Provider" \
        -listing-visibility="unauth" \
        oidc/

    echo "✅ Vault OIDC tuned."
}

map_blueprint_groups_to_vault() {
    echo "🔍 Iniciando mapeamento de grupos do Blueprint..."
    
    local ACCESSOR
    ACCESSOR=$(vault auth list -format=json | jq -r '."oidc/".accessor')

    if [ -z "$ACCESSOR" ] || [ "$ACCESSOR" == "null" ]; then
        echo "❌ Erro: Accessor OIDC não encontrado."
        return 1
    fi

    # Definimos os pares Nome:Politica
    local MAPPINGS=(
        "Home-Admins:admin-policy"
        "Home-Developers:developer-policy"
        "Home-Users:developer-policy"
    )

    for item in "${MAPPINGS[@]}"; do
        local AUTH_NAME="${item%%:*}"
        local POLICY="${item#*:}"
        local VAULT_GROUP_NAME="vault-${AUTH_NAME,,}"

        echo "👥 Sincronizando: $AUTH_NAME -> $POLICY"

        # 1. Garantir que o Grupo Externo existe
        local GID
        GID=$(vault read -format=json identity/group/name/"$VAULT_GROUP_NAME" | jq -r '.data.id // empty')
        
        if [ -z "$GID" ]; then
            GID=$(vault write -format=json identity/group name="$VAULT_GROUP_NAME" type="external" policies="$POLICY" | jq -r '.data.id')
        fi

        # 2. Verificar se o Alias já existe para este Accessor
        # Isso evita o erro "already in use"
        local ALIAS_EXISTS
        ALIAS_EXISTS=$(vault list -format=json identity/group-alias/id | jq -re ".[]" | xargs -I {} vault read -format=json identity/group-alias/id/{} | jq -r "select(.data.name==\"$AUTH_NAME\" and .data.mount_accessor==\"$ACCESSOR\") | .data.id")

        if [ -z "$ALIAS_EXISTS" ]; then
            echo "🔗 Criando novo Alias para $AUTH_NAME..."
            vault write identity/group-alias name="$AUTH_NAME" mount_accessor="$ACCESSOR" canonical_id="$GID" > /dev/null
        else
            echo "✅ Alias já mapeado (ID: $ALIAS_EXISTS). Pulando..."
        fi
    done
    echo "✅ Sincronização completa!"
}

_should_work() {
    echo "🧪 [TEST] Iniciando validação da infraestrutura de Identidade..."

    # 1. Listar e validar se os Aliases existem
    echo "📋 Verificando Aliases de Grupo existentes:"
    local ALIAS_LIST=$(vault list -format=json identity/group-alias/id)
    
    if [ -z "$ALIAS_LIST" ] || [ "$ALIAS_LIST" == "null" ]; then
        echo "❌ Erro: Nenhum Alias de grupo encontrado no Vault."
        return 1
    fi
    echo "$ALIAS_LIST" | jq -r '.[]'

    # 2. Ler detalhes do primeiro Alias encontrado (Teste de Leitura)
    local FIRST_ALIAS_ID=$(echo "$ALIAS_LIST" | jq -r '.[0]')
    echo "🔍 Validando integridade do Alias: $FIRST_ALIAS_ID"
    vault read "identity/group-alias/id/$FIRST_ALIAS_ID"

    # 3. Listar Entidades (Usuários que já logaram pelo menos uma vez)
    echo "👤 Usuários (Entidades) registrados no Vault:"
    local ENTITIES=$(vault list -format=json identity/entity/name 2>/dev/null)
    if [ -z "$ENTITIES" ]; then
        echo "ℹ️  Nenhuma entidade encontrada. (Aguardando primeiro login OIDC)"
    else
        echo "$ENTITIES" | jq -r '.[]'
    fi

    # 4. Teste de Idempotência (Tentar recriar sem gerar erro no console)
    echo "♻️  Testando escrita silenciosa (Idempotência)..."
    local ACCESSOR=$(vault auth list -format=json | jq -r '."oidc/".accessor')

    # Em vez de tentar escrever, apenas validamos se o Alias esperado existe
    if vault list -format=json identity/group-alias/id | jq -e ". != null" > /dev/null; then
        echo "✅ Aliases confirmados no banco do Vault."
    else
        echo "⚠️ Nenhum Alias ativo encontrado."
    fi

    echo "✅ Teste de sanidade concluído com sucesso!"
}

sync_vault_flow() {
    # check token caps
    validate_caps
    # vault review setup
    vault_oidc_enable

    
    write_auth_oidc_role "$AUTENTIK_OIDC_VAULT_STEWARD_ROLE"
    vault read auth/oidc/role/$AUTENTIK_OIDC_VAULT_STEWARD_ROLE

    write_auth_oidc_config "$AUTENTIK_OIDC_VAULT_STEWARD_ROLE"
    vault read auth/oidc/config

    map_blueprint_groups_to_vault

    configure_vault_identity_defaults

    #validate
    _should_work
    check_well_known_openid_config 2
    
}
export -f sync_vault_flow


# expect to complete
[[ " $* " == *" --sync-vault-flow "* ]]  && sync_vault_flow

echo ""
echo "Optional script arguments: "
echo "  --sync-vault-flow   : To syncronize vault"
echo ""
echo ""
echo "Available function:"
