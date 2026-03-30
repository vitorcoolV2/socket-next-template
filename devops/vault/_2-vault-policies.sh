#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

set -e

. ./vault_lib.sh

# -----------------------------------------------------------------------------
# Root Setup: Enable KV and create all roles
# -----------------------------------------------------------------------------
vault_setup_roles() {
    (    
        kp open || return 1
        vault_request_root_token || return 1
        PROVIDER_SELECT="keepass" core_secret_service_get "root/VAULT_TOKEN" 
        
        if ! require_vars VAULT_TOKEN; then return 1; fi

        export VAULT_TOKEN=$VAULT_TOKEN
        #show_vars VAULT_TOKEN
        # Mount KV v2 at 'secret/' (if not already)
        if ! vault secrets list | grep -q "^secret/"; then
            echo "📦 Ativando KV v2 em secret/..."
            vault secrets enable -path=secret/ -version=2 kv
        else
            echo "ℹ️ KV em secret/ já está ativo."
        fi
    
        # Create all roles
        vault__steward_policy__DO_NOT_DELETE                
        vault__developer_policy        
        vault__user_policy
        vault__guest_policy
        vault__bot_policy

        PROVIDER_SELECT="mem" core_secret_service_delete "vault/VAULT_TOKEN"
        kp close
        
        ## root token not needed
    )
}

# -----------------------------------------------------------------------------
# Steward Role: Full admin capabilities
# -----------------------------------------------------------------------------
vault__steward_policy() {
    echo "📋 Creating/updating steward policy..."

    vault policy write app-steward-policy - <<'EOF'
# --- 1. SEGREDOS (KV v2) ---
path "secret" { capabilities = ["list", "read"] }
path "secret/data/*" { capabilities = ["create", "read", "update", "patch", "delete", "list"] }
path "secret/metadata/*" { capabilities = ["list", "read", "delete"] }

# --- 2. UI Discovery ---
path "sys/internal/ui/mounts" { capabilities = ["read"] }
path "sys/internal/ui/mounts/secret" { capabilities = ["read"] }
path "sys/internal/ui/mounts/secret/*" { capabilities = ["read"] }
path "sys/internal/ui/mounts/secret/data" { capabilities = ["read", "list"] }
path "sys/internal/ui/mounts/secret/data/**" { capabilities = ["read", "list"] }
path "sys/mounts" { capabilities = ["read"] }
path "sys/mounts/secret" { capabilities = ["read"] }

# --- 3. PKI Intermediate CA ---
path "pki_int/*" { capabilities = ["create", "read", "update", "delete", "list"] }
path "pki_int/roles/home-server-role" { capabilities = ["create", "read", "update", "delete"] }
path "pki_int/roles" { capabilities = ["list"] }
path "pki_int/issue/home-server-role" { capabilities = ["create", "update"] }
path "pki_int/sign/home-server-role" { capabilities = ["create", "update"] }

# --- 4. Root CA (read-only) ---
path "pki/cert/ca" { capabilities = ["read"] }
path "pki/config/urls" { capabilities = ["read"] }

# --- 5. Auth & OIDC ---
path "sys/auth/oidc" { capabilities = ["create", "update", "read", "delete", "sudo"] }
path "sys/auth/oidc" { capabilities = ["create", "update", "read", "delete", "sudo"] }
path "sys/mounts/auth/oidc/tune" { capabilities = ["update", "sudo"] }
path "auth/oidc/*" { capabilities = ["create", "read", "update", "delete", "list"] }
path "sys/auth" { capabilities = ["read"] }

# --- 6. AppRole Management (self) ---
path "auth/approle/role/steward-role/role-id" { capabilities = ["read"] }
path "auth/approle/role/steward-role/secret-id" { capabilities = ["update", "create"] }

# --- 7. Token Lookup ---
path "auth/token/lookup-self" { capabilities = ["read"] }
EOF

    # Enable AppRole if not already
    if ! vault auth list | grep -q "^approle/"; then
        echo "📦 Enabling AppRole..."
        vault auth enable approle
    else
        echo "ℹ️ AppRole already enabled."
    fi

    # Create/update steward AppRole
    vault write auth/approle/role/steward-role \
        token_policies="app-steward-policy" \
        token_ttl="4h" \
        token_max_ttl="4h" \
        bind_secret_id=true

    # 1. Obter o Role ID (Idestático do AppRole)
    local r_id=$(vault read -format=json auth/approle/role/steward-role/role-id | jq -r '.data.role_id')

    # 2. Gerar um novo Secret ID (A chave dinâmica)
    # Nota: Cada vez que corres isto, geras um novo segredo. 
    # O anterior continua válido até expirar ou ser revogado.
    local s_id=$(vault write -f -format=json auth/approle/role/steward-role/secret-id | jq -r '.data.secret_id')

    # 3. Guardar no teu "Master de Verdade"
    if [[ -n "$r_id" && -n "$s_id" ]]; then
        kp_save_approle "vault/AppRole/steward-role" "$r_id" "$s_id"
        echo "✅ steward-role created/updated and credentials saved to KeePass"
    else
        echo "❌ Erro ao obter credenciais do Vault para o steward-role" >&2
        return 1
    fi
    echo "✅ steward-role created/updated"
}

# -----------------------------------------------------------------------------
# Developer Role: For tool.sh app provisioning
# -----------------------------------------------------------------------------
vault__developer_policy() {
    echo "📋 Creating/updating developer policy..."

    vault policy write developer-policy - <<'EOF'
# --- OIDC credentials for any app (chat, fotos, files, etc.) ---
path "secret/data/*/OIDC_*" { capabilities = ["create", "read", "update", "list"] }
path "secret/metadata/*/OIDC_*" { capabilities = ["list", "read"] }

# --- Database passwords for apps ---
path "secret/data/*/DATABASE_*" { capabilities = ["read", "list"] }
path "secret/data/*/POSTGRES_*" { capabilities = ["read", "list"] }
path "secret/data/*/MYSQL_*" { capabilities = ["read", "list"] }

# --- Redis passwords ---
path "secret/data/*/REDIS_*" { capabilities = ["read", "list"] }

# --- Authentik tokens (read) ---
path "secret/data/authentik/*" { capabilities = ["list"] }

# --- User credentials (read) ---
path "secret/data/*/USER_*" { capabilities = ["read", "list"] }
path "secret/data/*/PASSWORD" { capabilities = ["read", "list"] }

# --- UI Discovery ---
path "sys/internal/ui/mounts/secret" { capabilities = ["read"] }
path "sys/mounts" { capabilities = ["read"] }
path "sys/mounts/secret" { capabilities = ["read"] }

# --- Token Self Lookup (required) ---
path "auth/token/lookup-self" { capabilities = ["read"] }

# --- AppRole Management (self) ---
path "auth/approle/role/developer-role/role-id" { capabilities = ["read"] }
path "auth/approle/role/developer-role/secret-id" { capabilities = ["update", "create"] }
EOF

    # Create/update developer AppRole
    vault write auth/approle/role/developer-role \
        token_policies="developer-policy" \
        token_ttl="24h" \
        token_max_ttl="24h" \
        secret_id_ttl="30d" \
        bind_secret_id=true

    # 1. Obter o Role ID (Idestático do AppRole)
    local r_id=$(vault read -format=json auth/approle/role/developer-role/role-id | jq -r '.data.role_id')

    # 2. Gerar um novo Secret ID (A chave dinâmica)
    # Nota: Cada vez que corres isto, geras um novo segredo. 
    # O anterior continua válido até expirar ou ser revogado.
    local s_id=$(vault write -f -format=json auth/approle/role/developer-role/secret-id | jq -r '.data.secret_id')

    # 3. Guardar no teu "Master de Verdade"
    if [[ -n "$r_id" && -n "$s_id" ]]; then
        kp_save_approle "vault/AppRole/developer-role" "$r_id" "$s_id"
        echo "✅ stdevelopereward-role created/updated and credentials saved to KeePass"
    else
        echo "❌ Erro ao obter credenciais do Vault para o developer-role" >&2
        return 1
    fi

    echo "✅ developer-role created/updated"
}


vault__bot_policy() {
    echo "📋 Creating/updating Bot policy..."

    vault policy write bot-policy - <<'EOF'
# --- Full access to app secrets (for provision_oidc) ---
path "secret/data/*" { capabilities = ["create", "read", "update", "list", "delete"] }
path "secret/metadata/*" { capabilities = ["create", "read", "update", "list", "delete"] }

# --- Component stack OIDC credentials for any app (chat, fotos, files, etc.) ---
path "secret/data/*/OIDC_*" { capabilities = ["create", "read", "update", "list"] }
path "secret/metadata/*/OIDC_*" { capabilities = ["list", "read"] }

# --- Database passwords for apps ---
path "secret/data/*/DATABASE_*" { capabilities = ["create", "read", "update", "list"] }
path "secret/data/*/POSTGRES_*" { capabilities = ["create", "read", "update", "list"] }
path "secret/data/*/MYSQL_*" { capabilities = ["create", "read", "update", "list"] }

# --- Redis passwords ---
path "secret/data/*/REDIS_*" { capabilities = ["create", "read", "update", "list"] }

# --- Authentik tokens (read) ---
path "secret/data/authentik/*" { capabilities = ["read", "list"] }

# --- User credentials (read/write) ---
path "secret/data/*/USER_*" { capabilities = ["create", "read", "update", "list"] }
path "secret/data/*/PASSWORD" { capabilities = ["create", "read", "update", "list"] }

# --- UI Discovery ---
path "sys/internal/ui/mounts/secret" { capabilities = ["read"] }
path "sys/mounts" { capabilities = ["read"] }
path "sys/mounts/secret" { capabilities = ["read"] }

# --- Token Self Lookup (required) ---
path "auth/token/lookup-self" { capabilities = ["read"] }

# --- AppRole Management (self) ---
path "auth/approle/role/bot-role/role-id" { capabilities = ["read"] }
path "auth/approle/role/bot-role/secret-id" { capabilities = ["update", "create"] }
EOF

    # Create/update bot AppRole
    vault write auth/approle/role/bot-role \
        token_policies="bot-policy" \
        token_ttl="24h" \
        token_max_ttl="24h" \
        secret_id_ttl="30d" \
        bind_secret_id=true

    # 1. Obter o Role ID (Idestático do AppRole)
    local r_id=$(vault read -format=json auth/approle/role/bot-role/role-id | jq -r '.data.role_id')

    # 2. Gerar um novo Secret ID (A chave dinâmica)
    # Nota: Cada vez que corres isto, geras um novo segredo. 
    # O anterior continua válido até expirar ou ser revogado.
    local s_id=$(vault write -f -format=json auth/approle/role/bot-role/secret-id | jq -r '.data.secret_id')

    # 3. Guardar no teu "Master de Verdade"
    if [[ -n "$r_id" && -n "$s_id" ]]; then
        kp_save_approle "vault/AppRole/bot-role" "$r_id" "$s_id"
        echo "✅ bot-role created/updated and credentials saved to KeePass"
    else
        echo "❌ Erro ao obter credenciais do Vault para o bot-role" >&2
        return 1
    fi        

    echo "✅ bot-role created/updated"
}

# -----------------------------------------------------------------------------
# User Role: Read secrets for assigned apps
# -----------------------------------------------------------------------------
vault__user_policy() {
    echo "📋 Creating/updating user policy..."

    vault policy write user-policy - <<'EOF'
# --- Read secrets for home2500 apps ---
path "secret/data/home2500/*" { capabilities = ["read", "list"] }
path "secret/metadata/home2500/*" { capabilities = ["list", "read"] }

# --- Read own user credentials ---
path "secret/data/users/${ENTITY}/*" { capabilities = ["read", "list"] }

# --- UI Discovery ---
path "sys/internal/ui/mounts/secret" { capabilities = ["read"] }
path "sys/mounts" { capabilities = ["read"] }

# --- Token Self Lookup ---
path "auth/token/lookup-self" { capabilities = ["read"] }
EOF

    # Create/update user AppRole
    vault write auth/approle/role/user-role \
        token_policies="user-policy" \
        token_ttl="24h" \
        token_max_ttl="24h" \
        secret_id_ttl="7d" \
        bind_secret_id=true

    # 1. Obter o Role ID (Idestático do AppRole)
    local r_id=$(vault read -format=json auth/approle/role/user-role/role-id | jq -r '.data.role_id')

    # 2. Gerar um novo Secret ID (A chave dinâmica)
    # Nota: Cada vez que corres isto, geras um novo segredo. 
    # O anterior continua válido até expirar ou ser revogado.
    local s_id=$(vault write -f -format=json auth/approle/role/user-role/secret-id | jq -r '.data.secret_id')

    # 3. Guardar no teu "Master de Verdade"
    if [[ -n "$r_id" && -n "$s_id" ]]; then
        kp_save_approle "vault/AppRole/user-role" "$r_id" "$s_id"
        echo "✅ user-role created/updated and credentials saved to KeePass"
    else
        echo "❌ Erro ao obter credenciais do Vault para o user-role" >&2
        return 1
    fi        

    echo "✅ user-role created/updated"
}

# -----------------------------------------------------------------------------
# Guest Role: Public secrets only
# -----------------------------------------------------------------------------
vault__guest_policy() {
    echo "📋 Creating/updating guest policy..."

    vault policy write guest-policy - <<'EOF'
# --- Public secrets only ---
path "secret/data/public/*" { capabilities = ["read", "list"] }
path "secret/metadata/public/*" { capabilities = ["list", "read"] }

# --- UI Discovery ---
path "sys/internal/ui/mounts/secret" { capabilities = ["read"] }
path "sys/mounts" { capabilities = ["read"] }

# --- Token Self Lookup ---
path "auth/token/lookup-self" { capabilities = ["read"] }
EOF

    # Create/update guest AppRole
    vault write auth/approle/role/guest-role \
        token_policies="guest-policy" \
        token_ttl="24h" \
        token_max_ttl="24h" \
        secret_id_ttl="1d" \
        bind_secret_id=true

        # 1. Obter o Role ID (Idestático do AppRole)
    local r_id=$(vault read -format=json auth/approle/role/guest-role/role-id | jq -r '.data.role_id')

    # 2. Gerar um novo Secret ID (A chave dinâmica)
    # Nota: Cada vez que corres isto, geras um novo segredo. 
    # O anterior continua válido até expirar ou ser revogado.
    local s_id=$(vault write -f -format=json auth/approle/role/guest-role/secret-id | jq -r '.data.secret_id')

    # 3. Guardar no teu "Master de Verdade"
    if [[ -n "$r_id" && -n "$s_id" ]]; then
        kp_save_approle "vault/AppRole/guest-role" "$r_id" "$s_id"
        echo "✅ guest-role created/updated and credentials saved to KeePass"
    else
        echo "❌ Erro ao obter credenciais do Vault para o guest-role" >&2
        return 1
    fi                

    echo "✅ guest-role created/updated"
}

# -----------------------------------------------------------------------------
# Run if executed directly
# -----------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    vault_setup_roles
fi
