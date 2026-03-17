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


##### BLUEPRINT home2500

# Variáveis Locais

require_vars "DOMAIN" "AUTHENTIK_API_TOKEN" "VAULT_CACERT"

AUTHENTIK_BLUE_API_URL="https://auth.${DOMAIN}/api/v3/managed/blueprints/"
AUTHENTIK_BLUE_DIR="$(realpath "../authentik/blueprints")"
# this script is used as source, do not run
blue_template_show() {
    echo -e "\n\e[1;34m─── BLUEPRINT ─────────────────────────────────\e[0m"
    echo -e "  \e[1;32mNAME:\e[0m  $1"
    echo -e "  \e[1;32mSLUG:\e[0m  $2"
    echo -e "  \e[1;32mTEMPLATE:\e[0m  $3"    
    echo -e "  \e[1;32mFILE:\e[0m  $4"
    blue_template_show_match_vars "$(basename $4)"
}

_map_blueprints_from_dir() {
    local dir="${1:-"$AUTHENTIK_BLUE_DIR"}"
    local results=()

    if ! command -v yq &> /dev/null; then
        echo "❌ Error: 'yq' not found." >&2
        return 1
    fi
    #ls $dir

    for file_path in "$dir"/*.yaml; do
        [ -e "$file_path" ] || continue
        
        yq eval '.' "$file_path" >/dev/null 2>&1 || {
            #echo "invalid yaml $file_path" 
            continue
        }
        local filename=$(basename "$file_path")
        
        local name=$(yq eval '.metadata.name // "null"' "$file_path" | xargs)
        local slug=$(yq eval '.metadata.slug // "null"' "$file_path" | xargs)

        [[ "$name" == "null" ]] && name=$(echo "$filename" | cut -f1 -d'.')
        [[ "$slug" == "null" ]] && slug=$(echo "$filename" | cut -f1 -d'.')

        local is_template="false"
        grep -q "{{" "$file_path" && is_template="true"

        # IMPORTANTE: Envolver em aspas para o eval não confundir o pipe |
        results+=("\"$filename|$name|$slug|$is_template\"")
    done
    echo "${results[@]}"
}
# Map all blueprints into memory
eval "BLUEPRINTS=($(_map_blueprints_from_dir "$AUTHENTIK_BLUE_DIR"))"

display_blueprints() {
    require_vars "BLUEPRINTS"
    for entry in "${BLUEPRINTS[@]}"; do
        IFS='|' read -r file name slug is_tpl <<< "$entry"
        
        # Clean whitespaces
        file=$(echo "$file" | xargs)
                
        name=$(echo "$name" | xargs)
        slug=$(echo "$slug" | xargs)
        is_tpl=$(echo "$is_tpl" | xargs)

        blue_template_show "$name" "$slug" "$is_tpl" "$file"                        
    done
}    
export -f display_blueprints

blue_template_show_match_vars() {    
    local file_name="$1" 
    local input_path=$(realpath "$AUTHENTIK_BLUE_DIR/$file_name")

    # 1. Scanner de requisitos
    local vars=$(_get_template_requirements "$input_path" "true")

    echo -e "  \e[1;35m🔐 Environment Check:\e[0m"

    for var in $vars; do
        # Limpeza do nome da variável
        local clean_var=$(echo "$var" | tr -d '$')
        local value="${!clean_var}"
        
        # Lógica de Segurança: Mascarar se for sensível ou mostrar apenas os primeiros caracteres
        if [[ -z "$value" ]]; then
            echo -e "      \e[1;31m✖ $clean_var: MISSING\e[0m"
        elif [[ "$clean_var" =~ (SECRET|TOKEN|PASS|KEY|AUTH) ]]; then
            # Mostra apenas os primeiros 4 caracteres por segurança
            local masked="${value:0:4}****"
            echo -e "      \e[1;32m✔ $clean_var:\e[0m $masked"
        else
            # Variáveis comuns (ex: DOMAIN) podem ser mostradas
            echo -e "      \e[1;32m✔ $clean_var:\e[0m $value"
        fi
    done
}
export -f blue_template_show_match_vars

blue_template_inject_vars() {
    local input_path="$1"        
    local output_path="$2"
    local is_tpl="${3:-true}"

    if [ "$is_tpl" != "true" ]; then
        # Se não é template, apenas copia o ficheiro para o output_path
        cp "$input_path" "$output_path"
        return 0
    fi

    # 1. Scanner de requisitos
    local vars=$(_get_template_requirements "$input_path" "$is_tpl")
    echo -e "  \e[1;33m🔧 Injecting:\e[0m [ $vars ]"

    # 2. Processamento SED (Loop sobre as variáveis detetadas)
    local temp_content=$(cat "$input_path")
    for var in $vars; do
        # Remove o $ se existir no nome da variável para a expansão ${!var}
        local clean_var=$(echo "$var" | tr -d '$')
        local value="${!clean_var}"
        
        # Substitui tanto {{VAR}} como {{$VAR}} por segurança
        temp_content=$(echo "$temp_content" | sed "s|{{$var}}|$value|g; s|{{\$$var}}|$value|g")
    done
    echo "template:"
    echo "$temp_content" > "$output_path"
}
blue_template_vars() {    
    local target_name="$(basename "$1")"
    # Change the comma (,) to a colon-hyphen (:-)
    local output_file="${2:-/tmp/debug_${target_name}}"
    local input_path="$AUTHENTIK_BLUE_DIR/$target_name"

    # Validação imediata: Se o ficheiro não existe, para aqui
    if [[ ! -f "$input_path" ]]; then
        echo "❌ [DevOps Error] Source file not found: $input_path" >&2
        return 1
    fi

    # Executa o motor de template que criámos
    # Usamos o _ na frente para indicar função interna/helper
    blue_template_inject_vars "$input_path" "$output_file" "true"

    # CRITICAL FIX: Don't redirect back to the same file while reading it.
    # Use a temp file to store the 'tail' result, then move it back.
    local tmp_slice=$(mktemp)

    cat "$output_file" > "$tmp_slice"
    mv "$tmp_slice" "$output_file"

    if [[ -s "$output_file" ]]; then                
        cat "$output_file"
    else
        echo "❌ [DevOps Error] Generated file is empty: $output_file" >&2
        return 1
    fi
}
# kind of a private method usage to apply one blueprint
_blue_server_apply_blueprint() {
    local name="$1"
    local slug="$2"
    local file_path="$3" 

    # Correção: Ler o conteúdo do ficheiro real
    if [ ! -f "$file_path" ]; then
        echo "❌ Error: File not found at $file_path"
        return 1
    fi
    local content=$(cat "$file_path")

    # --- SECURE INSPECTION (yq + jq) ---
    echo -e "  \e[1;34m🔍 Final Metadata Inspection:\e[0m"
    echo "$content" | yq eval ".metadata" - -o json 2>/dev/null | jq -C '.' | sed 's/^/      /'
    # ----------------------------------

    local payload=$(jq -n --arg yaml "$content" --arg n "$name" --arg s "$slug" \
        '{name: $n, slug: $s, content: $yaml}')

    echo "🚀 Processing Blueprint: $name ($slug)..."
        
    # 3. Tentar Criar (POST)
    local response=$(curl -s -k -L -X POST "$AUTHENTIK_BLUE_API_URL" \
        -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" -d "$payload")
    
    local pk=$(echo "$response" | jq -r '.pk // empty')

    # 4. Se falhar (PK vazio ou erro de "already exists"), procurar por SLUG OU NOME
    if [ -z "$pk" ] || [ "$pk" == "null" ]; then
        echo "🔍 Name/Slug conflict detected, searching for existing PK..."
        
        # Procuramos na lista por correspondência de slug OU nome
        pk=$(curl -s -k -L -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" "${AUTHENTIK_BLUE_API_URL}?page_size=100" | \
             jq -r --arg s "$slug" --arg n "$name" \
             '.results[] | select(.slug == $s or .name == $n) | .pk' | head -n 1)
        
        if [ -n "$pk" ] && [ "$pk" != "null" ]; then
            echo "🔄 Found existing PK: $pk. Updating content..."
            curl -s -k -L -X PATCH "${AUTHENTIK_BLUE_API_URL}${pk}/" \
                -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
                -H "Content-Type: application/json" -d "$payload" > /dev/null
        else
            echo -e "❌ \e[1;31mError: Failed to create or find blueprint $slug.\e[0m"
            echo "Response: $response"
            return 1
        fi
    fi

    # 5. Aplicar o Blueprint
    echo "⏳ Applying blueprint changes (ID: $pk)..."
    local apply_res=$(curl -s -k -L -X POST "${AUTHENTIK_BLUE_API_URL}${pk}/apply/" \
        -H "Authorization: Bearer $AUTHENTIK_API_TOKEN")
    
    # O Authentik costuma retornar HTTP 204 ou um JSON com log de sucesso
    if [[ $? -eq 0 ]]; then
        echo -e "✅ \e[1;32mApplied successfully:\e[0m $name\n"
    else
        echo -e "⚠️ \e[1;31mApply call returned an error. Check Authentik system tasks.\e[0m\n"
    fi
}
_upsert_one_blueprint2_test_if_needed() {
    local name="$1"
    local slug="$2"
    local file_path="$3" 

    if [ ! -f "$file_path" ]; then
        echo "❌ Error: File not found at $file_path"
        return 1
    fi
    local content=$(cat "$file_path")

    # Ensure AUTHENTIK_BLUE_API_URL has a trailing slash
    [[ "$AUTHENTIK_BLUE_API_URL" != */ ]] && AUTHENTIK_BLUE_API_URL="${AUTHENTIK_BLUE_API_URL}/"

    local payload=$(jq -n --arg yaml "$content" --arg n "$name" --arg s "$slug" \
        '{name: $n, slug: $s, content: $yaml}')

    echo "🚀 Processing Blueprint: [$name] ($slug)..."
    echo $payload
    # 1. Try to create
    local response=$(curl -s -k -L -X POST "$AUTHENTIK_BLUE_API_URL" \
        -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" -d "$payload")
    
    local pk=$(echo "$response" | jq -r '.pk // empty')
    echo $response | jq
    # 2. If create failed, search by slug
    if [ -z "$pk" ] || [ "$pk" == "null" ]; then
        echo "🔍 Conflict or empty response. Searching for existing slug..."

        echo "🔍 Name/Slug conflict detected, searching for existing PK..."
        
        # Procuramos na lista por correspondência de slug OU nome
        curl -s -k -L -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" "${AUTHENTIK_BLUE_API_URL}?page_size=100" | jq
        pk=$(curl -s -k -L -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" "${AUTHENTIK_BLUE_API_URL}?page_size=100" | \
             jq -r --arg s "$slug" --arg n "$name" \
             '.results[] | select(.slug == $s or .name == $n) | .pk' | head -n 1)

        r2=$(curl -s -k -L -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" "${AUTHENTIK_BLUE_API_URL}?slug=$slug" | \
             jq -r '.')
        pk=$(echo $r2 | jq '.results[0].pk // empty')
        echo "r2=$2"
        if [ -n "$pk" ] && [ "$pk" != "null" ]; then
            echo "🔄 Found existing PK: $pk. Updating..."
            curl -s -k -L -X PATCH "${AUTHENTIK_BLUE_API_URL}${pk}/" \
                -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
                -H "Content-Type: application/json" -d "$payload" > /dev/null
        else
            echo -e "❌ Error: Could not create or find blueprint $slug."
            echo "DEBUG Response: $response"
            return 1
        fi
    fi

    # 3. Apply
    echo "⏳ Applying blueprint (PK: $pk)..."
    local apply_status=$(curl -s -k -L -o /dev/null -w "%{http_code}" -X POST "${AUTHENTIK_BLUE_API_URL}${pk}/apply/" \
        -H "Authorization: Bearer $AUTHENTIK_API_TOKEN")
    
    if [[ "$apply_status" == "204" || "$apply_status" == "200" ]]; then
        echo -e "✅ Applied successfully (HTTP $apply_status)\n"
    else
        echo -e "⚠️ Apply failed with status $apply_status. Check Authentik Admin Logs.\n"
        return 1
    fi
}
_get_template_requirements() {
    local path="$1"
    local is_tpl="$2"
    [[ "$is_tpl" == "true" ]] && grep -oP '\{\{\K[^\|\}]+' "$path" | sort -u | xargs
}

# 2. O Processador (Faz a substituição real)


blue_apply() {
    local target_name=$(basename "$1")   

    blue_template_show_match_vars "$target_name"
    # 1. Search for the file in our mapped BLUEPRINTS array
    local found=false

    for entry in "${BLUEPRINTS[@]}"; do
        IFS='|' read -r file name slug is_tpl <<< "$entry"
        file=$(echo "$file" | xargs); name=$(echo "$name" | xargs); 
        slug=$(echo "$slug" | xargs); is_tpl=$(echo "$is_tpl" | xargs)
        
        if [ "$file" == "$target_name" ]; then
            # Caminhos
            local input_path="$AUTHENTIK_BLUE_DIR/$file"
            local output_path="/tmp/applied_$file" # Ficheiro processado

            # Passo 1: Gerar ficheiro (com ou sem templating)
            blue_template_inject_vars "$input_path" "$output_path" "$is_tpl"
            
            # Passo 2: Upsert usando o ficheiro gerado
            _blue_server_apply_blueprint "$name" "$slug" "$output_path"
          
            found=true
            break
        fi
    done

    if [ "$found" = false ]; then
        echo "❌ Error: Blueprint file '$target_name' not found in registry."
        return 1
    fi
}
export -f blue_apply
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


#!disbled display_blueprints                # display all blueprints

# Apply Home2500 base
#blue_apply "blueprint-home2500.yaml"
#blue_template_show_match_vars "blueprint-home2500-OIDC-tpl.yaml"




echo ""
echo "Optional script arguments: # important for operational secrets renewal"
echo "  --renew-api             : generate new api token"

echo ""
echo "Available function:"
echo "enable_oidc_well_known_openid_flow"
echo "blue_template_show_match_vars \"blueprint-home2500-OIDC-tpl.yaml\""
echo "blue_apply \"blueprint-home2500.yaml\""
echo "blue_template_vars \"blueprint-home2500-_DIR_NAME.yaml.tpl\" /to/result.yaml"