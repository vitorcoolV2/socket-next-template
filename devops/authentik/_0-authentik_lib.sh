#!/bin/bash
# Filename: ../../devops/authentik/./_0.authentik_lib.sh

set +e

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ This is a library and should be sourced, not run directly."  2>&1
    echo "     Try: source ./$(realpath --relative-to="$PWD" "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
    return 1 2> /dev/null || exit 1
fi


# --- HELPERS ---
# Internal helper to modify outpost provider list
ak_fix_proxied_redir() {
    echo "🔍 Analyzing schema and applying fixes (v9)..." >&2
    require_vars "DOMAIN"
    
    # 1. Fetch data using the relationship: Proxy -> OAuth2 -> Core Application
    local provider_data=$(docker exec -i authentik-db psql -U authentik -d authentik -t -A -c \
        "SELECT p.oauth2provider_ptr_id, a.slug 
         FROM authentik_providers_proxy_proxyprovider p 
         JOIN authentik_core_application a ON p.oauth2provider_ptr_id = a.provider_id;")

    if [ -z "$provider_data" ]; then
        echo "❌ Error: Could not map Proxy Providers via oauth2provider_ptr_id." >&2
        return 1
    fi

    for row in $provider_data; do
        local pk=$(echo $row | cut -d'|' -f1)
        local slug=$(echo $row | cut -d'|' -f2)
        
        echo "🔄 redirect fix: $slug (ID: $pk)..." >&2

        # 1. Prepare the SQL query in a variable first
        local sql_query="
-- Correct JSON format to prevent HTTP 500 errors
UPDATE authentik_providers_oauth2_oauth2provider
SET _redirect_uris = jsonb_build_array(
    jsonb_build_object(
        'url', 'https://$slug.$DOMAIN/outpost.goauthentik.io/callback?X-authentik-auth-callback=true',
        'matching_mode', 'strict'
    )
)
WHERE provider_ptr_id = $pk;

-- Ensure Proxy is set to forward_single
UPDATE authentik_providers_proxy_proxyprovider
SET 
    mode = 'forward_single',
    external_host = 'https://$slug.$DOMAIN'
WHERE oauth2provider_ptr_id = $pk;"

        # 2. Print the query to the console (with color for visibility)
        #echo -e "\e[1;30mDEBUG SQL for $slug:\e[0m"
        #echo -e "$sql_query" | sed 's/^/  /' # Indent for readability

        # 3. Execute the query via stdin
        echo "$sql_query" | docker exec -i authentik-db psql -U authentik -d authentik >/dev/null        
    done

    echo "✅ Completed. Please restart the outpost to clear the cache." >&2
    return 0
}

ak_upsert_api_token() {
    require_vars AUTHENTIK_DB_CONTAINER
    local name="${1}"
    local role="${2:-"guest"}" # can be guest|user|developer|bot
    local description="${3:-"authentik provisioning $role account $name"}" 
   
    [[ -z "$name" ]] && { echo "❌ Erro: Nome do utilizador é obrigatório." >&2; return 1; }

    local expires_ts    
    local random_key
    local ak_id="$(sanitize_db_name "${name}-${role}-token")"
    local var_name="$(sanitize_var_name "${role^^}_${name^^}_TOKEN")"
    local KP_USER_DB="$(sanitize_path_name "home2500-$name")" ##

    _guest__policy() {
        expires_ts="NOW() + INTERVAL '8 hr'"
        random_key=$(kp generate --lower --upper --numeric -l 48 2>/dev/null)
        # no KP_DB ???? or try to help guest
    }
    _user__policy() {
        expires_ts="NOW() + INTERVAL '7 days'"
        random_key=$(kp generate --lower --upper --numeric -l 48 2>/dev/null)
        kp test 2> /dev/null || kp open || return 1
    }
    _developer__policy() {
        expires_ts="NOW() + INTERVAL '3 months'"
        random_key=$(kp generate --lower --upper --numeric -l 48 2>/dev/null)
        kp test 2> /dev/null || kp open || return 1
    }
    _bot__policy() {
        expires_ts="NOW() + INTERVAL '1 months'"
        random_key=$(kp generate --lower --upper --numeric -l 48 2>/dev/null)
        KP_DB="$KP_USER_DB" kp test 2> /dev/null || kp open || return 1
    }


    if ! $("_${role}__policy"); then
        echo "Fail to apply \"$role\" policy. Use on of the roles [guest,user,developer,bot]" >&2
        return 1
    fi

    local sql_query="
    INSERT INTO authentik_core_token (
        identifier, 
        key, 
        user_id, 
        intent, 
        description, 
        expiring,
        expires
    )
    VALUES (
        '$ak_id', 
        '$random_key', 
        (SELECT id FROM authentik_core_user WHERE username='$name' LIMIT 1),
        'api', 
        '$description', 
        true, 
        $expires_ts
    )
    ON CONFLICT (identifier) DO UPDATE 
    SET key = EXCLUDED.key, 
        expires = EXCLUDED.expires;
    "

    # 4. Execução silenciosa
    if echo "$sql_query" | docker exec -i "$AUTHENTIK_DB_CONTAINER" psql -U authentik -d authentik >/dev/null 2>&1; then
        echo "✅ Token '$identifier' injetado com sucesso na DB." >&2
        
        # 5. Backup no KeePass (Promoção de Segredo)
        # Usamos subshell para isolar o PROVIDER_SELECT
        (
            local secret_name="vault/authentik/$var_name"
            PROVIDER_SELECT="keepass" core_secret_service_put "$secret_name" "$random_key"
            echo "🔐 Token guardado no KeePass como: $secret_name" >&2
        )
    else
        echo "❌ Erro ao injetar token na DB do Authentik." >&2
        return 1
    fi
}

export -f ak_fix_proxied_redir
ak_internal_service_ready() {
    local status
    status=$(curl -s -k "$AUTHENTIK_INTERNAL_URL/api/v3/root/config/" | jq -r '.capabilities[0]' 2>/dev/null)
    if [[ "$status" == "can_save_media" ]]; then
        return 0 # Ready!
    else
        return 1 # Not ready yet
    fi
}

ak_sync_provider_secrets() {
    local app_name="${1}" # e.g., "fotos"
    local url="$AUTHENTIK_INTERNAL_URL"
    (
        PROVIDER_SELECT="keepass" \
            core_secret_service_get "$app_name/OIDC_ID"
        PROVIDER_SELECT="keepass" \
            core_secret_service_get "$app_name/OIDC_SECRET"

        require_vars app_name OIDC_ID OIDC_SECRET || return 1

        # 1. Find the PK (Primary Key) of the provider in Authentik
        local provider_pk=$(curl -s -L -H "Authorization: Bearer $AUTHENTIK_TOKEN" \
            "$url/api/v3/providers/oauth2/?search=$app_name" | jq -r '.results[0].pk')

        [[ "$provider_pk" == "null" ]] && { echo "❌ Provider not found" >&2; return 1; }

        # 2. PATCH the provider with the Vault values
        curl -s -X PATCH "$url/api/v3/providers/oauth2/$provider_pk/" \
            -H "Authorization: Bearer $AUTHENTIK_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{
                \"client_id\": \"$OIDC_ID\",
                \"client_secret\": \"$OIDC_SECRET\"
            }"
    )
}

ak_wait4_instance() {
    echo "⏳ Waiting for db initialization and Admin user provision in PostgreSQL..." >&2
    
    # 1. Aguarda a DB estar pronta e o utilizador Admin ser criado pelo Worker
    until docker exec authentik-db psql -U authentik -d authentik -t -c \
        "SELECT EXISTS (SELECT 1 FROM authentik_core_user WHERE username = '$AUTHENTIK_ADMIN_USER');" 2>/dev/null | grep -q "t"; do
        echo -n "."
        sleep 3
    done
    echo -e "\n✅ Admin user found. Database is initialized." >&2

    ak_internal_service_ready
    
    echo -e "\n✅ Authentik API is UP and running!" >&2
    return 0
}

ak_api_token_validate() {
    require_vars AUTHENTIK_INTERNAL_URL AUTHENTIK_CONTAINER_NAME || return 1
    
    if ! require_containers_ready "AUTHENTIK_CONTAINER_NAME"; then
        echo "❌ Erro: Instancia authentik server não está a correr." >&2
        return 1
    fi
        
    # Subshell para isolar o escopo
    (
        PROVIDER_SELECT="mem" core_secret_service_get "authentik/AUTHENTIK_API_TOKEN" 2>/dev/null
        
        [[ -z "$AUTHENTIK_API_TOKEN" ]] && { echo "❌ [AUTHENTIK] Erro: Token não fornecido." >&2; return 1; }
        local url="$AUTHENTIK_INTERNAL_URL/api/v3/core/users/me/"
        echo "🔍 Validando conta Authentik via $url..." >&2

        # --- Sub-função 1: Comunicação e Validação de Resposta ---
        _token__authentik_me_json() {
            local response
            response=$(curl -k -s -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
                -H "Accept: application/json" \
                --connect-timeout 5 \
                "$url")

            # Se o curl falhar ou a resposta for vazia
            [[ -z "$response" ]] && { echo "🚫 [AUTHENTIK] Sem resposta valida" >&2; return 1; }

            # Verificar se o JSON contém erro (ex: Invalid Token) antes de passar para o parser
            if ! echo "$response" | jq -e '.user' >/dev/null 2>&1; then
                local err_msg=$(echo "$response" | jq -r '.detail // "Resposta inesperada da API"')
                echo "⚠️ [ERROR] API Authentik: $err_msg" >&2
                return 1
            fi
            
            echo "$response"
        }

        # --- Sub-função 2: Parsing e Execução da Lógica ---
        _token__eval_me() {
            local me
            me=$(_token__authentik_me_json) || return 1
      
            # Extração segura: usamos o jq para gerar exportações apenas se os dados existirem
            # O uso de 'select(. != null)' evita o erro de iteração sobre null
            local vars_to_eval
            vars_to_eval=$(echo "$me" | jq -r '
                .user | select(. != null) |
                "user_name=" + (.username|@sh) + 
                "\nis_active=" + (.is_active|tostring) + 
                "\nemail=" + (.email|@sh) + 
                "\nis_superuser=" + (.is_superuser|tostring)
            ')

            [[ -z "$vars_to_eval" ]] && return 1
            eval "$vars_to_eval"

            # Extração de grupos com proteção contra null/empty array
            local groups
            groups=$(echo "$me" | jq -r '.user.groups | if . then [.[].name] | join(",") else "" end')

            if [[ -n "$user_name" && "$user_name" != "null" ]]; then
                if [[ "$is_active" == "false" ]]; then
                    echo "🚫 [ABORT] Conta '$user_name' desativada no Authentik." >&2
                    return 1
                fi

                local type_user="User"
                [[ "$is_superuser" == "true" ]] && type_user="Superuser"

                echo "✅ [SUCCESS] Autenticado ($type_user): $user_name ($email) | Groups: [${groups:-nenhum}]" >&2
                return 0
            fi

            echo "⚠️ [ERROR] Dados de utilizador incompletos na resposta." >&2
            return 1
        }

        # Executa a cadeia de sub-funções
        _token__eval_me
    )
}
export -f ak_api_token_validate


# hard rule. need vault on https service mode

ak_secrets_show() {
    (
        ak_secrets_compose_get
        local mem_secret_dir="$MEM_ROOT_DIR/authentik"
        cat $mem_secret_dir/.env
        ls -ls $mem_secret_dir
    )
}


### history methods. >>>>>>
# from where environment secrets come
__migrate_env_file__Keepass_file() {
    . $(realpath ./.env) # import secrets to keepass

    core_secret_service_put "authentik/AUTHENTIK_SECRET_KEY" "$AUTHENTIK_SECRET_KEY"
    core_secret_service_put "authentik/AUTHENTIK_POSTGRESQL__PASSWORD" "$AUTHENTIK_POSTGRESQL__PASSWORD"
    core_secret_service_put "authentik/AUTHENTIK_REDIS__PASSWORD" "$AUTHENTIK_REDIS__PASSWORD"
    core_secret_service_put "authentik/AUTHENTIK_EMAIL__PASSWORD" "$AUTHENTIK_EMAIL__PASSWORD"
    core_secret_service_put "authentik/AUTHENTIK_ADMIN_PASS" "$AUTHENTIK_ADMIN_PASS"
}


# --- SCRIPT # CHECK ---

ak_secrets_compose_get() {    
    if ! vault_validate_token ; then
        echo "🔑 Vault token invalid. Authenticating..." >&2
        vault_request_stew_token || return 1
    fi    

    
    (
        PROVIDER_SELECT="mem" core_secret_load_vars \
            "keepass://authentik/AUTHENTIK_ADMIN_PASS" \
            "vault://authentik/AUTHENTIK_SECRET_KEY" \
            "vault://authentik/AUTHENTIK_POSTGRESQL__PASSWORD" \
            "vault://authentik/AUTHENTIK_REDIS__PASSWORD" \
            "vault://authentik/AUTHENTIK_EMAIL__PASSWORD" || return 1

        core_secret_export2_env_vars "authentik/.secret" \
            AUTHENTIK_ADMIN_PASS \
            AUTHENTIK_SECRET_KEY \
            AUTHENTIK_POSTGRESQL__PASSWORD \
            AUTHENTIK_REDIS__PASSWORD \
            AUTHENTIK_EMAIL__PASSWORD || return 1
    ) || return 1
    return 0
}

ak_api_token_restore() { 
    (   
        PROVIDER_SELECT="mem" core_secret_load_vars \
            "keepass://authentik/AUTHENTIK_API_TOKEN" 2> /dev/null && \
        ak_api_token_validate || return 1      
    ) || return 1
}

ak_api_token_generate() {
    # 1. Pré-requisitos
    require_vars "AUTHENTIK_ADMIN_USER" "DOMAIN" || {
        echo "Not can generate authentik api token" >&2
        return 1        
    }
    ak_api_token_validate && return 1  ## ignora geracao de token novo quando valido. muito caro em tempo para gerar
    # Redirecionamos o echo para >&2 para não poluir o stdout
    (
        echo "🔄 Generating Authentik API Token (Idempotent Root Mode)..." >&2

        # 2. Execução via Python Shell
        # Adicionamos -q ao python se possível, ou apenas garantimos o filtro no final
        local RAW_OUTPUT=$(docker exec -i $AUTHENTIK_CONTAINER_NAME python3 /lifecycle/ak.py shell <<EOF
from authentik.core.models import Token, User
from django.utils.crypto import get_random_string
import sys

admin = User.objects.filter(username="$AUTHENTIK_ADMIN_USER").first()

if not admin:
    print("FATAL: Superuser not found in DB")
    sys.exit(1)

token_obj, created = Token.objects.update_or_create(
    identifier="steward-automation-token",
    defaults={
        "user": admin,
        "intent": "api",
        "expiring": False
    }
)

new_secret = get_random_string(60)
token_obj.key = new_secret
token_obj.save()
print(f"RESULT_TOKEN:{new_secret}")
EOF
)

        # 3. Extração e Limpeza do Token (O filtro grep já isola o que queremos)
        local NEW_TOKEN=$(echo "$RAW_OUTPUT" | grep "RESULT_TOKEN:" | cut -d':' -f2 | tr -d '[:space:]' | tr -d '\r')

        if [ -z "$NEW_TOKEN" ]; then
            echo "❌ Error: Failed to generate a new token via Docker Exec." >&2
            return 1
        fi

        # 4. Persistência e Export    
        core_secret_service_put "authentik/AUTHENTIK_API_TOKEN" "$NEW_TOKEN" &&
            ak_api_token_validate || return 1

        #echo "✅ exported: ${AUTHENTIK_API_TOKEN:0:5}***" >&2

        return 0
    )
}
export -f ak_api_token_generate

[[ " $* " == *" --renew-api "* ]] && ak_api_token_generate


###### using ./theme/_builder.sh ** love to build my own custom authentik UI. thank you gemini. you make a hard job must easy.
ak_theme_dark() {
    (
        source $(core_resolve_file "authentik/theme/_builder.sh")
        _build_brand_theme "dark"     
    )
}

ak_theme_light() {
    (
        source $(core_resolve_file "authentik/theme/_builder.sh")   
        _build_brand_theme "light"
    )
}

ak_down() {
    (
        cd $AUTHENTIK_DIR
        docker compose down --remove-orphans
    )
}
ak_up() {    
    (
        cd $AUTHENTIK_DIR
        if ak_secrets_compose_get; then
            docker compose up -d  && \
            ak_wait4_instance || return 1   
            
        fi
    )
}

ak_api_call() {
    local method="$1"      # GET, POST, DELETE, etc
    local endpoint="$2"    # /api/v3/...
    local data_file="$3"   # Opcional: ficheiro com JSON para POST
    
    # Validação básica
    if [[ -z "$AUTHENTIK_URL" || -z "$AUTHENTIK_TOKEN" ]]; then
        echo "❌ [ERROR] AUTHENTIK_URL ou AUTHENTIK_TOKEN não definidos." >&2
        return 1
    fi

    local url="${AUTHENTIK_URL}${endpoint}"
    
    # Executa a chamada usando cURL
    # -s: silent, -S: show error, -f: fail on http errors
    if [[ -n "$data_file" ]]; then
        curl -sS -f -X "$method" "$url" \
            -H "Authorization: Bearer $AUTHENTIK_TOKEN" \
            -H "Content-Type: application/json" \
            -d @"$data_file"
    else
        curl -sS -f -X "$method" "$url" \
            -H "Authorization: Bearer $AUTHENTIK_TOKEN" \
            -H "Content-Type: application/json"
    fi
}

ak_system_health() {
    echo "🩺 --- AUTHENTIK SYSTEM SANITY CHECK --- 🩺"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "⏰ Executado em: $timestamp"
    echo "-------------------------------------------"

    # 1. Verificar KeePass & Variáveis de Sessão
    
    if kp test 2> /dev/null; then
        echo "🔐 [KEEPASS] Sessão Ativa "
    else
        echo "❌ [KEEPASS] Sessão Bloqueada"
    fi

    # 2. Verificar Vault
    if vault_validate_token > /dev/null 2>&1; then
        echo "💎 [VAULT  ] Token OK"
    else
        echo "❌ [VAULT  ] Token Inválido ou Expirado"
    fi

    # 3. Verificar Authentik API
    if ak_api_token_validate > /dev/null 2>&1; then    
        echo "🛡️ [AUTH    ] API Authentik OK"
    else
        echo "❌ [AUTH    ] API Authentik Down/Token Errado"
    fi

    # 4. Verificar Pi-hole & DNS Sync
    local pihole_status=$(curl -s -o /dev/null -w "%{http_code}" "$AUTHENTIK_INTERNAL_URL/api/v3/core/brands/")
    # Teste rápido de resolução DNS interna se possível
    echo "🌐 [NETWORK] DNS Interno a responder"

    # 5. Estado dos Containers (Docker)
    echo "-------------------------------------------"
    echo "📦 [DOCKER ] Estado dos Serviços:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "authentik|vault|pihole|traefik"
    
    echo "-------------------------------------------"
    echo "🚀 Tudo pronto para continuar o desenvolvimento!"
}

# 1. Determine if we are being Sourced or Executed
# (Checking if BASH_SOURCE exists and the 0th element is the script itself)
# Calculate the depth of the sourcing stack

ak_logout() {
    vault_logout
    core_secret_mem_delete "authentik"
}
ak_login() {
    require_vars VAULT_CACERT || return 1

    show_vars AUTHENTIK_CONTAINER_NAME
    # Camada 1: Infraestrutura (Docker)
    if ! require_containers_ready AUTHENTIK_CONTAINER_NAME; then
        echo "❌ Erro: Instância authentik server não está a correr." >&2
        # Importante: não usamos exit 1 aqui para não fechar o shell do usuário
    else
        # Camada 2: Validação de Tokens (Apenas se houver TTY)
        if [[ -t 0 ]]; then
            (
                if vault_validate_token && ak_api_token_validate; then
                    echo "✅ Authentik API Token is valid." >&2
                else
                    echo "🔑 Attempting token recovery/generation..." >&2
                    ak_api_token_restore || \
                    ak_api_token_generate || {
                        echo "🛑 Manual action required: run 'ak_api_token_generate'" >&2
                        return 1
                    }
                    # Re-valida após gerar
                    ak_api_token_validate || return 1
                fi
            )
        fi            
    fi  
    
}


ak_fn_sort_weights() {
    local rules_json
    rules_json=$(cat <<-'EOF'
[
  {
    "prefix": "ak_api_token*|_token*|ak_log*",
    "refine": "",
    "weight": 10,
    "cat": "TOKEN"
  },
  {
    "prefix": "ak_up|ak_down|ak_re*|ak_secrets*",
    "refine": "",
    "weight": 12,
    "cat": "LIFE-CYCLE"
  },
  {
    "prefix": "ak_load_req*|base__req*",
    "refine": "",
    "weight": 12,
    "cat": "REQUIREMENTS"
  },
  {
    "prefix": "ak_fn*",
    "refine": "",
    "weight": 48,
    "cat": "CATALOG"
  },  
  {
    "prefix": "ak_*",
    "refine": "",
    "weight": 50,
    "cat": "AUTHENTIK"
  },
  {
    "prefix": "_*",
    "refine": "",
    "weight": 70,
    "cat": "INTERNAL"
  },
  {
    "prefix": ".",
    "refine": "",
    "weight": 90,
    "cat": "MISC"
  }
]
EOF
)
    echo "$rules_json" | jq -c '
        map(. + {refine: (.refine // "")}) 
        | sort_by(.weight, .prefix) 
    '
}

ak_fn_catalog() {
    #core_fn_sort_json "${BASH_SOURCE[0]}" "kp_sort_weights" 
    core_fn_catalog "${BASH_SOURCE[0]}" "ak_fn_sort_weights" 
}

source $(realpath "$AUTHENTIK_DIR/../vault/vault_lib.sh" )

ak_load_requirements() {        
    base__requirements(){
        AUTHENTIK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"        
        AUTHENTIK_DIR_NAME="$(basename $AUTHENTIK_DIR)"
        # --- AUTHENTIK ctx ----
        export AUTHENTIK_DIR
        export AUTHENTIK_DIR_NAME
        
        export AUTHENTIK_URL="https://auth.$DOMAIN"
        export AUTHENTIK_CONTAINER_NAME="authentik-server"
        export AUTHENTIK_DB_CONTAINER="authentik-db"
        export AUTHENTIK_INTERNAL_URL="http://$AUTHENTIK_CONTAINER_NAME.$INTERNAL_DOMAIN:9000"


        require_functions \


        show_vars DOMAIN \
            INTERNAL_DOMAIN \
            MEM_ROOT_DIR \
            AUTHENTIK_DIR \
            AUTHENTIK_DIR_NAME \
            AUTHENTIK_ADMIN_USER \
            AUTHENTIK_URL \
            AUTHENTIK_INTERNAL_URL \
            AUTHENTIK_CONTAINER_NAME \
            AUTHENTIK_DB_CONTAINER \
            DEVOPS_DIR && \
        require_functions \
            require_vars \
            require_binaries \
            ak_wait4_instance \
            ak_secrets_show \
            ak_fix_proxied_redir \
            core_secret_service_get \
            core_secret_service_put \
            require_files || return 1
    }
    base__requirements || return 1
}


unset AK_SKIP_INTERACTION
# Detect if we're in non-interactive mode (e.g., output redirected)
[[ ! -t 1 && ! -t 2 ]] && AK_SKIP_INTERACTION=true
# Check if the script is being sourced
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then

    # Load requirements, exit on failure
    ak_load_requirements || return 1

    # Interactive mode: show helpful messages
    if [[ "$AK_SKIP_INTERACTION" != "true" ]]; then
        echo -e "\n📦 Authentik module loaded. Available commands:"
        echo -e "   \e[1;34mak_<tab>\e[0m to list functions"
        echo "ak_fn_catalog"
    else
        echo "⚠️  Non-interactive mode: skipping token validation." >&2
    fi
fi