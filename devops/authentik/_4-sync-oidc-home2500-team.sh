#!/bin/bash
# --- _5-enable-oidc-vault.sh ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

set -e
. $(realpath ./_3-enable-oidc-vault.sh)
set +e



# 1. Load enable oidc provider environment
require_vars "AUTENTIK_OIDC_VAULT_STEWARD_ROLE" || exit
require_vars "CURL_CA_OPTS" "VAULT_CACERT" "DOMAIN" \
        "AUTHENTIK_API_TOKEN" \
        "AUTHENTIK_ADMIN_USER" \
        "AUTHENTIK_ADMIN_PASS" || exit

for f in kp check_well_known_openid_config; do ! declare -F "$f" >/dev/null && echo "❌ Function $f not found" && exit 1; done

# 4. Configure Vault OIDC Method
echo "🔐 Configuring Vault OIDC Auth Method..."


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

generate_authentik_admin_root() {
    # 1. Pre-flight
    require_vars "AUTHENTIK_ADMIN_USER" "DOMAIN"
    
    local USER_EMAIL="admin@$DOMAIN"
    local USER_NAME="$AUTENTIK_OIDC_VAULT_STEWARD_ROLE"
    local USER_PATH="home2500/$AUTENTIK_OIDC_VAULT_STEWARD_ROLE"

    echo "👤 Sincronizando Superuser '$AUTHENTIK_ADMIN_USER' via Python Shell..."

    # 2. Execução via Docker Exec (Mantendo indentações de 4 espaços para o Python)
    local RAW_OUTPUT=$(docker exec -i authentik-server python3 /lifecycle/ak.py shell <<EOF
from authentik.core.models import User, Group
from django.utils.crypto import get_random_string
import sys

# Localizar o usuário definido no ENV
u = User.objects.filter(username="$AUTHENTIK_ADMIN_USER").first()

if not u:
    print("FATAL: Superuser not found in DB")
    sys.exit(1)

# Gerar nova senha e atualizar perfil
new_secret = get_random_string(24)
u.email = '$USER_EMAIL'
u.name = '$USER_NAME'
u.set_password(new_secret)
u.path = '$USER_PATH'
u.is_active = True
u.is_superuser = True
u.save()

# Sincronizar Grupos Críticos
target_groups = ['Home-Admins', 'authentik Admins']
for g_name in target_groups:
    g = Group.objects.filter(name=g_name).first()
    if g:
        g.users.add(u)
        print(f"🔗 Linked to group: {g_name}")
    else:
        print(f"⚠️ Warning: Group '{g_name}' not found.")

print(f"PYTHON_SUCCESS: {u.username} synced.")
print(f"RESULT_PASSWORD:{new_secret}")
EOF
)

    # 3. Extração da nova senha
    local NEW_PASS=$(echo "$RAW_OUTPUT" | grep "RESULT_PASSWORD:" | cut -d':' -f2 | tr -d '[:space:]' | tr -d '\r')

    if [ -z "$NEW_PASS" ]; then
        echo "❌ Erro ao sincronizar administrador. Output bruto:"
        echo "$RAW_OUTPUT"
        return 1
    fi

    # 4. Persistência nos Secrets
    export AUTHENTIK_ADMIN_PASS="$NEW_PASS"
    
    # Salva no Vault e no KeePass usando as suas ferramentas

    PROVIDER_SELECT="keepass mem" core_secret_service_put \
         "secret/authentik" "AUTHENTIK_ADMIN_PASS" "$AUTHENTIK_ADMIN_PASS"
    
    echo "------------------------------------------------"
    echo "✅ Admin Root Sync Completo!"
    echo "👤 User: $AUTHENTIK_ADMIN_USER"
    echo "👤 email: $USER_EMAIL"
    echo "🔑 Pass: ${AUTHENTIK_ADMIN_PASS:0:4}****************"
    echo "------------------------------------------------"
}
export -f generate_authentik_admin_root

_set_user_password() {
    local TARGET_USER="${1:?"Erro: Username é obrigatório."}"
    local KP_VAR="kp_authentik_${TARGET_USER}_password"
    
    echo "🔐 Iniciando configuração de senha para: $TARGET_USER"

    # 1. Recuperação do KeePassXC se a variável de sessão estiver vazia
    if [ -z "${!KP_VAR}" ]; then
        local kp_recovery="vault-users/$KP_VAR"
        echo "🔍 Procurando no KeePassXC: $kp_recovery"
        local RECOVERED_USER_PASSWORD="$(kp_get_entry_pass "$kp_recovery")"
        
        if [ -n "$RECOVERED_USER_PASSWORD" ]; then
            # 'printf -v' é mais seguro que 'eval' para atribuir valores dinâmicos
            printf -v "$KP_VAR" "%s" "$RECOVERED_USER_PASSWORD"
            export "$KP_VAR"
        fi
    fi

    # 2. Geração de fallback se ainda estiver vazia
    if [ -z "${!KP_VAR}" ]; then
        echo "🎲 Gerando nova senha segura..."
        local NEW_PASS=$(openssl rand -base64 18)
        printf -v "$KP_VAR" "%s" "$NEW_PASS"
        export "$KP_VAR"
    else
        echo "📋 Usando senha existente (Sessão/KeePassXC)"
    fi

    local PASSWORD="${!KP_VAR}"

    # 3. Localizar PK do usuário
    # Adicionei a extração correta do ID para garantir que o curl não falhe silenciosamente
    local USER_JSON=$(curl -s -k $CURL_CA_OPTS -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
        "$AUTHENTIK_URL/api/v3/core/users/?username=$TARGET_USER")
    
    local PK=$(echo "$USER_JSON" | jq -r '.results[0].pk // empty')

    if [[ -z "$PK" ]]; then
        echo "❌ Erro: Usuário '$TARGET_USER' não encontrado."
        return 1
    fi

    # 4. API Call
    echo "📡 Sincronizando com Authentik (PK: $PK)..."
    local STATUS_CODE=$(curl -s -k $CURL_CA_OPTS -o /dev/null -w "%{http_code}" \
        -X POST "$AUTHENTIK_URL/api/v3/core/users/$PK/set_password/" \
        -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"password\": \"$PASSWORD\"}")

    if [[ "$STATUS_CODE" =~ ^(200|204)$ ]]; then
        echo "✅ Senha sincronizada com sucesso para $TARGET_USER."
    else
        echo "❌ Erro API Authentik: $STATUS_CODE"
        return 1
    fi
}

# ... (Teu cabeçalho e variáveis iniciais) ...

upsert_user() {
    local TARGET_USERNAME="${1:?"Erro: Username é obrigatório."}"
    local TARGET_GROUPS_INPUT="${2:-"Home-Developers"}"
    
    echo "👤 Processando: [$TARGET_USERNAME]"

    # 1. Obter PK do utilizador
    local USER_DATA=$(curl -s -k $CURL_CA_OPTS -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
        "$AUTHENTIK_URL/api/v3/core/users/?username=$TARGET_USERNAME")
    local PK=$(echo "$USER_DATA" | jq -r ".results[] | select(.username==\"$TARGET_USERNAME\") | .pk // empty")

    local FIRST_GROUP=$(echo "$TARGET_GROUPS_INPUT" | cut -d',' -f1 | xargs)
    local USER_PATH="home2500/${FIRST_GROUP,,}"
    local USER_EMAIL="${TARGET_USERNAME}@${DOMAIN}"

    # 2. Criar se não existir
    if [ -z "$PK" ]; then
        echo "🏗️ Criando utilizador..."
        PK=$(curl -s -k $CURL_CA_OPTS -X POST "$AUTHENTIK_URL/api/v3/core/users/" \
            -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"username\": \"$TARGET_USERNAME\", \"name\": \"${TARGET_USERNAME^}\", \"email\": \"$USER_EMAIL\", \"path\": \"$USER_PATH\"}" | jq -r '.pk')
    fi

    # 3. Mapear Grupos
    local GROUP_PKS_JSON="[]"
    IFS=',' read -ra ADDR <<< "$TARGET_GROUPS_INPUT"
    for GNAME in "${ADDR[@]}"; do
        local GNAME_TRIM=$(echo "$GNAME" | xargs)
        local G_PK=$(curl -s -k $CURL_CA_OPTS -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
            "$AUTHENTIK_URL/api/v3/core/groups/?name=$GNAME_TRIM" | jq -r ".results[] | select(.name==\"$GNAME_TRIM\") | .pk // empty")
        
        [[ -n "$G_PK" ]] && GROUP_PKS_JSON=$(echo "$GROUP_PKS_JSON" | jq ". += [\"$G_PK\"]")
    done

    # 4. Sincronização via PUT
    local DATA_PAYLOAD=$(jq -n --arg un "$TARGET_USERNAME" --arg nm "${TARGET_USERNAME^}" --arg em "$USER_EMAIL" --arg ph "$USER_PATH" --argjson gr "$GROUP_PKS_JSON" \
        '{username: $un, name: $nm, email: $em, path: $ph, groups: $gr, is_active: true}')

    local FINAL_RES=$(curl -s -k $CURL_CA_OPTS -X PUT "$AUTHENTIK_URL/api/v3/core/users/$PK/" \
        -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$DATA_PAYLOAD")

    if echo "$FINAL_RES" | jq -e '.pk' > /dev/null; then
        echo "✅ Sucesso: Grupos sincronizados para $TARGET_USERNAME"
        _set_user_password "$TARGET_USERNAME"
    else
        echo "❌ Falha na sincronização: $FINAL_RES"
    fi
}

onboard_user() {
    local USER="$1"
    local TARGET_GROUPS="$2"
    
    upsert_user "$USER" "$TARGET_GROUPS"

    local VAR_NAME="kp_authentik_${USER}_password"
    if [ -n "${!VAR_NAME}" ]; then
        # Salvaguarda final no KeePassXC se a função interna falhou mas temos a pass na RAM
        kp_save_entry "vault-users/$USER" "${!VAR_NAME}"
        unset "$VAR_NAME"
        echo "✅ Onboarding de '$USER' finalizado."
    fi
}

test_user_login() {
    vault login -method=oidc role="$AUTENTIK_OIDC_VAULT_STEWARD_ROLE"
    vault token lookup
}

check_well_known_openid_config 2

onboard_dev_team_home2500() {    
    #ak_api_token_generate. this method takes to long
    onboard_user "vitor" "Home-Developers"
    onboard_user "carla" "Home-Developers"
    onboard_user "mad" "Home-Users"
    onboard_user "eva" "Home-Users"    
}
export -f onboard_dev_team_home2500
# expect to complete

# script argument:action options


 
[[ " $* " == *" --sync-team "* ]]  && onboard_dev_team_home2500

[[ " $* " == *" --renew-admin "* ]]  && generate_authentik_admin_root 

echo ""
echo "Optional script action arguments: "
echo "  --renew-api     : To generate new api token"
echo "  --sync-team     : Restore onboard team: "

echo ""
echo "Available function:"
echo "onboard_dev_team_home2500"
echo "generate_authentik_admin_root"


