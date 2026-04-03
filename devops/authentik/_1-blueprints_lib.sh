#!/bin/bash
# Filename: ../../devops/authentik/./_1-blueprints_lib.sh

set +e

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ This is a library and should be sourced, not run directly."  2>&1
    return 1  ## disable return 1 only on development mode. why ??? 
fi

AUTHENTIK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source $(realpath "$AUTHENTIK_DIR/_0-authentik_lib.sh") > /dev/null 2>&1 

check_well_known_openid_config() {
    # 1. Verificação de Requisitos
    # Usando verificação direta para evitar problemas com o status de retorno do require_vars
    if [ -z "$VAULT_CACERT" ]; then
        echo "❌ Authentik OIDC: VAULT_CACERT não definido."
        echo "Antes de continuar, mude o serviço Vault para HTTPS."
        return 1
    fi    
    require_vars "VAULT_CACERT" "AUTHENTIK_API_TOKEN" "DOMAIN" "INTERNAL_DOMAIN" "app_slug"

    # 2. Configuração de URLs e Parâmetros
    local local_url="http://authentik-server.$INTERNAL_DOMAIN:9000"
    local proxy_url="https://$AUTHENTIK_URL"
    local suffix="application/o/${app_slug}/.well-known/openid-configuration"
    
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
        echo "Verifique se o App Slug '$app_slug' existe no Authentik."
        echo "------------------------------------------------------------"
        
        if [ "$exit_on_error" = "true" ]; then    
            return 1
        else
            return 1
        fi
    fi
}
export -f check_well_known_openid_config

blue_authentik_oidc_provider() {
    local app_name=${1:-$CLIENT_APP_NAME}
    require_vars AUTHENTIK_URL AUTHENTIK_API_TOKEN VAULT_NS || return 1

    local domain_only="${AUTHENTIK_URL#*//}"
    domain_only="${domain_only%/}"
    local ak_api_url="https://${domain_only}/api/v3"
    local auth_header="Authorization: Bearer $AUTHENTIK_API_TOKEN"

    # --- 1. Busca de Mappings (O que faltava) ---
    echo "🔍 Coletando Property Mappings (Scopes)..."
    local MAPPINGS=$(curl -s -k -H "$auth_header" "${ak_api_url}/propertymappings/all/?managed__startsWith=goauthentik.io/providers/oauth2/scope-" | \
        jq -c 'if .results == null or .results == [] then [] else [.results[].pk] end' 2>/dev/null || echo "[]")

    # --- 2. Busca de Flows e Chaves ---
    fetch_pk() {
        curl -s -k -H "$auth_header" "${ak_api_url}/$1/?$2" | jq -r '.results[0].pk // empty'
    }

    local AUTHE_PK=$(fetch_pk "flows/instances" "slug=default-authentication-flow")
    local AUTHO_PK=$(fetch_pk "flows/instances" "slug=default-provider-authorization-implicit-consent")
    local INVAL_PK=$(fetch_pk "flows/instances" "slug=default-provider-invalidation-flow")
    local SIGN_PK=$(fetch_pk "crypto/certificatekeypairs" "name__icontains=self-signed")

    # --- 3. Limpeza de Conflitos ---
    local existing_pk=$(fetch_pk "providers/oauth2" "name=${app_name}-provider")
    [[ -n "$existing_pk" ]] && curl -s -k -X DELETE -H "$auth_header" "${ak_api_url}/providers/oauth2/${existing_pk}/" && sleep 1

    # --- 4. Payload Final Robusto ---
    echo "🏗️ Criando Provider com Scopes OIDC..."
    local payload=$(jq -n \
        --arg name "${app_name}-provider" \
        --arg cid "$app_name" \
        --arg auth "$AUTHE_PK" \
        --arg auto "$AUTHO_PK" \
        --arg inva "$INVAL_PK" \
        --arg sign "$SIGN_PK" \
        --argjson maps "$MAPPINGS" \
        --arg r1 "https://$VAULT_NS/ui/vault/auth/oidc/oidc/callback" \
        --arg r2 "http://localhost:8250/oidc/callback" \
        '{
            "name": $name,
            "authentication_flow": $auth,
            "authorization_flow": $auto,
            "invalidation_flow": $inva,
            "property_mappings": $maps,
            "client_id": $cid,
            "signing_key": $sign,
            "client_type": "confidential",
            "include_claims_in_id_token": true,
            "redirect_uris": [
                {"url": $r1, "matching_mode": "strict"},
                {"url": $r2, "matching_mode": "strict"}
            ]
        }')
    echo $payload | jq .
    local response=$(curl -s -k -X POST "${ak_api_url}/providers/oauth2/" \
        -H "$auth_header" \
        -H "Content-Type: application/json" \
        -d "$payload")

    # Validação
    if ! echo "$response" | jq -e '.pk' >/dev/null; then
        echo "❌ Falha. API Response:"
        echo "$response" | jq .
        return 1
    fi

    echo "✅ Provider OIDC '$app_name' configurado com Mappings e Flows."
}
# >>>>>>>>

blue_vault_oidc_provider() {
    require TRUSTED_CA_FILE VAULT_CACERT
    local app_name=${1:-$CLIENT_APP_NAME}
    
    # Normalização da URL do Vault para garantir que não há barras duplas no fim
    local vault_url="https://${VAULT_NS%/}"
    
    # Normalização da URL do Authentik (Remove o protocolo se já existir)
    local ak_domain="${AUTHENTIK_URL#*//}"
    ak_domain="${ak_domain%/}"
    
    require_vars app_name VAULT_NS AUTHENTIK_API_TOKEN || return 1
    vault_validate_token || return 1

    # 1. Configura o lado do Authentik (Idempotente)
    blue_authentik_oidc_provider "$app_name" || return 1

    # 2. Obtém as credenciais reais do Authentik
    echo "🔑 Recuperando credenciais do Authentik..."
    local PROVIDER_DATA=$(curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
        "https://$ak_domain/api/v3/providers/oauth2/?search=$app_name")
    
    local CLIENT_ID=$(echo "$PROVIDER_DATA" | jq -r '.results[0].client_id // empty')
    local CLIENT_SECRET=$(echo "$PROVIDER_DATA" | jq -r '.results[0].client_secret // empty')
    local ISSUER_URL="https://$ak_domain/application/o/$app_name/"

    [[ -z "$CLIENT_ID" || "$CLIENT_ID" == "null" ]] && { echo "❌ Falha ao obter credenciais."; return 1; }

    # 3. Preparar o Vault
    vault auth list | grep -q "oidc/" || vault auth enable oidc

    # 4. Configuração Global OIDC (Com tratamento de TLS)
    echo "⚙️ Configurando endpoint OIDC no Vault..."
    vault write auth/oidc/config \
        oidc_discovery_url="$ISSUER_URL" \
        oidc_client_id="$CLIENT_ID" \
        oidc_client_secret="$CLIENT_SECRET" \
        default_role="reader" \
        oidc_discovery_ca_pem="$($TRUSTED_CA_FILE)" \

    # 5. Garante Política de Acesso (Mantive a tua lógica correta)
    local policy_name="$app_name-policy"
    if ! vault policy read "$policy_name" >/dev/null 2>&1; then
        echo "📝 Criando política $policy_name..."
        printf 'path "secret/data/%s/*" { capabilities = ["read", "list"] }\npath "secret/metadata/%s/*" { capabilities = ["list"] }' "$app_name" "$app_name" | \
            vault policy write "$policy_name" -
    fi

    # 6. Define a Role
    # Adicionado verbose para depurar se houver erro nos redirect_uris
    echo "🛂 Configurando Role 'reader'..."
    vault write auth/oidc/role/reader \
        bound_audiences="$CLIENT_ID" \
        allowed_redirect_uris="$vault_url/ui/vault/auth/oidc/oidc/callback" \
        allowed_redirect_uris="$vault_url/oidc/callback" \
        allowed_redirect_uris="http://localhost:8250/oidc/callback" \
        user_claim="sub" \
        oidc_scopes="openid,profile,email" \
        policies="default,$policy_name" \
        ttl="1h"

    echo -e "\n✅ Vault OIDC Integrado com Sucesso!"
    echo "👉 Podes testar o login com: vault login -method=oidc role=reader"
}
export -f blue_vault_oidc_provider


# this script is used as source, do not run

blue_template_show_match_vars() {    
    local blueprint_template_file=$1
    # 1. Scanner de requisitos
    local vars=$(blue_template_extract_arguments "$blueprint_template_file")

    echo -e "  \e[1;35m🔐 Environment Check:\e[0m"

    for var in $vars; do
        # Limpeza do nome da variável
        local clean_var=$(echo "$var" | tr -d '$')
        local value="${!clean_var}"
        
        # Lógica de Segurança: Mascarar se for sensível ou mostrar apenas os primeiros caracteres
        if [[ -z "$value" ]]; then
            echo -e "      \e[1;31m✖ $clean_var: MISSING\e[0m"
        elif [[ "$clean_var" =~ (SECRET|TOKEN|PASS|KEY) ]]; then
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

require_single_blue_file() {
    local ref=${1}
    local blueprint_file=${!ref}
    local func="$2"
    
    # Validação silenciosa, mas erro ruidoso se falhar
    [[ -z "$blueprint_file" ]] && { echo "❌ Erro: Referência $blueprint_file vazia." >&2; return 1; }
  
    if blue_file_valid $blueprint_file; then
        local f_line=$(echo "$func_json" | jq -r '.line')
        local f_path=$(echo "$func_json" | jq -r '.script')
        
        # Output de Sucesso com colunas fixas e link clicável
        # %-30s garante que o nome da função ocupe sempre 30 espaços, alinhando as setas
        LABEL=${LABEL:-"✅\e[0m Found:  "}
        printf "  \e[1;32m${LABEL} \e[1;34m%-30s\e[0m \e[1;90m->\e[0m \e[4;36m%s\e[0m\n" "blueprint" "$(core_relative_path2 $blueprint_file)" >&2
        return 0
    else
        # Output de Erro alinhado
        printf "  \e[1;31m󰅙󰅙\e[0m Missing: \e[1;33m%-30s\e[0m \e[1;30m-> [%s]\e[0m\n" "blueprint" "$(core_relative_path2 $blueprint_file)" >&2
        return 1
    fi
}

blue_file_valid() {
    local file_path="$1"
    # 1. Validação de requisitos (Silenciosa) TEST COMPLETED
    { require_vars file_path && require_files file_path; } >/dev/null 2>&1 || return 1
    yq eval '.' "$file_path" >/dev/null 2>&1 || {
        echo "invalid yaml $file_path" >&2
        return 1
    }
    local filename=$(basename "$file_path")
    
    local name=$(yq eval '.metadata.name // "null"' "$file_path" | xargs)
    local slug=$(yq eval '.metadata.slug // "null"' "$file_path" | xargs)

    
    [[ "$name" == "null" ]] && return 1
    [[ "$slug" == "null" ]] && return 1

    local is_template="false"
    grep -q "{{" "$file_path" && is_template="true"
    DEBUG=false require_vars filename name slug is_template || return 1
    ### pack result vaild entry entry with '
    echo "'$filename|$name|$slug|$is_template'"
    return 0
}
blue_folder_valid_entries() {    
    local blue_dir="${1:-"$AUTHENTIK_BLUE_DIR"}"
    require_locations blue_dir
    local results=()
    
    if ! command -v yq &> /dev/null; then
        echo "❌ Error: 'yq' not found." >&2
        return 1
    fi
    #ls $blue_dir
    for file_path in "$blue_dir"/*.yaml; do
        #show_vars file_path
        [ -e "$file_path" ] || continue
        
        # Captura o output da validação
        local entry
        if entry=$(blue_file_valid "$file_path"); then
            #show_vars entry
            results+=($entry)
        fi        
    done
    echo "${results[@]}"
}

blue_template_list() {
    local blueprint_dir=${1:-$AUTHENTIK_BLUE_DIR}
    show_vars blueprint_dir
    _list_single_entry() {
        local entry="${1}"
        local unpack_entry="${entry//\'/}"
        IFS='|' read -r file name slug tpl <<< "$unpack_entry"    

        # Clean whitespaces
        file=$(echo "$file" | xargs)                
        name=$(echo "$name" | xargs)
        slug=$(echo "$slug" | xargs)

        #show_vars file name slug
        
        echo -e "\n\e[1;34m─── BLUEPRINT TEMPLATE ─────────────────────────\e[0m"
        echo -e "  \e[1;32mNAME:\e[0m  $name"
        echo -e "  \e[1;32mSLUG:\e[0m  $slug" 
        echo -e "  \e[1;32mFILE:\e[0m  $file"
    }
    (                
        cd $(realpath $blueprint_dir)        
        
        eval "BLUEPRINTS=($(blue_folder_valid_entries "$blueprint_dir"))" 

        for entry in "${BLUEPRINTS[@]}"; do
            #show_vars entry
            _list_single_entry "$entry"                       
        done
    )
}    
export -f blue_template_list


blue_template_inject_vars() {    
    local blueprint_template_file="$1"        
    local output_path="$2"
    require_files blueprint_template_file || return 1
    # 1. Scanner de requisitos
    local vars=$(blue_template_extract_arguments "$blueprint_template_file")
    echo -e "  \e[1;33m🔧 Injecting:\e[0m [ $vars ]" >&2

    # 2. Processamento SED (Loop sobre as variáveis detetadas)
    local temp_content=$(cat "$blueprint_template_file")
    for var in $vars; do
        # Remove o $ se existir no nome da variável para a expansão ${!var}
        local clean_var=$(echo "$var" | tr -d '$')
        local value="${!clean_var}"
        
        # Substitui tanto {{VAR}} como {{$VAR}} por segurança
        temp_content=$(echo "$temp_content" | sed "s|{{$var}}|$value|g; s|{{\$$var}}|$value|g")
    done
    echo "template:" >&2
    echo "$temp_content" > "$output_path"
    require_files output_path || {
        echo "blue_template_inject_vars function fail to generate $output_path"
        return 1
    }
}
blue_template_vars() {    
    local blueprint_tpl_path="$1"
    local output_file="${2}"
    #local blueprint_tpl_path="$AUTHENTIK_BLUE_DIR/$target_name"
    require_files blueprint_tpl_path || {
        echo "❌ [Error] Source template file: $blueprint_tpl_path" >&2
        return 1
    }

    local tmp_slice=$(mktemp)
    # Validação imediata: Se o ficheiro não existe, para aqui
    
    blue_template_show_match_vars "$blueprint_tpl_path"
    # Executa o motor de template que criámos
    # Usamos o _ na frente para indicar função interna/helper
    blue_template_inject_vars "$blueprint_tpl_path" "$tmp_slice" 

    cat "$tmp_slice" > "$output_file"
    # FIX DE PERMISSÕES: Essencial para o Authentik ler o ficheiro
    chmod 644 "$output_file"
    echo "blueprint file: $(realpath --relative-to="$PWD" "$output_file"  2>/dev/null || echo "$script_file")"
    if [[ ! -s "$output_file" ]]; then                
        echo "❌ [DevOps Error] Generated content is empty: $blueprint_tpl_path" >&2
        rm -f "$tmp_slice"
        return 1
    fi
    
}
blue_template_extract_arguments() {    
    local path2_blueprint="$1"
    require_files path2_blueprint || return 1
    grep -oP '\{\{\K[^\|\}]+' "$path2_blueprint" | sort -u | xargs
}
# kind of a private method usage to apply one blueprint
blue__get_current_json() {
    local blueprint_file="${1}"

    # 1. Validação e extração de metadados
    local entry
    if ! entry=$(blue_file_valid "$blueprint_file"); then 
        echo "file not valid"
        return 1; 
    fi
    
    # Limpeza de pipes e leitura de variáveis
    IFS='|' read -r file name slug tpl <<< "${entry//\'/}"
    
    # xargs remove leading/trailing whitespace nativamente
    file=$(echo "$file" | xargs)                
    name=$(echo "$name" | xargs)
    slug=$(echo "$slug" | xargs)

    # 3. Obter Token e fazer a chamada (SEM subshell de execução)
    # Importante: Não uses $(...) para envolver o bloco inteiro se queres apenas o output
    local response
    response=$(blue__get_all_json | \
        jq -c --arg name "$name" '
            .results | map(select(.name == $name))
        ')
    # 5. Retorno do JSON puro para o chamador
    if echo "$response" | jq -e . >/dev/null 2>&1; then
        echo "$response" | jq -c ".[]"  # Este é o único output para o stdout
    else
        echo "❌ Erro: Resposta da API inválida ou vazia." >&2
        echo "Debug: $response" >&2
        return 1
    fi
}
blue__get_all_json() {
    echo ""
    (
        PROVIDER_SELECT="mem" core_secret_service_get "authentik/AUTHENTIK_API_TOKEN" >/dev/null 2>&1
        
        if [[ -z "$AUTHENTIK_API_TOKEN" ]]; then
            echo "❌ Erro: AUTHENTIK_API_TOKEN não encontrado na memória." >&2
            return 1
        fi

        # 4. Chamada API (GET com query param para o slug)

        local response
        response=$(curl -s -k -L -X GET "${AUTHENTIK_BLUE_API_URL}" \
            -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
            -H "Accept: application/json")
            
        if echo "$response" | jq -e . >/dev/null 2>&1; then
            echo "$response" | jq -c "."  # Este é o único output para o stdout
        else
            echo "❌ Erro: Resposta da API inválida ou vazia." >&2
            echo "Debug: $response" >&2
            return 1
        fi
    ) 
}
blue__get_home2500_json() {
    blue__get_all_json | jq '.results | map(select(.path != null and (.path | startswith("_home2500_CORE/"))))'        
}
_blue_server_apply_blueprint() {    
    local blueprint_path="$1" 
    local _enabled="${2:-true}"
    require_vars blueprint_path || return 1
    local blueprint_filename=$(basename "$blueprint_path")
    
    require_locations AUTHENTIK_BLUE_DIR || return 1
    require_vars blueprint_filename || return 1

    ## the blueprint on shared host<>authentik folder
    local blue_dir_file="$AUTHENTIK_BLUE_DIR/$blueprint_filename"
    require_files blue_dir_file || return 1
    ## prova real
    if ! entry=$(blue_file_valid "$blue_dir_file"); then
        echo $entry  >&2
        return 1
    fi

    local unpack_entry="${entry//\'/}"
    IFS='|' read -r file name slug tpl <<< "$unpack_entry"                
    # Clean whitespaces
    file=$(echo "$file" | xargs)                
    name=$(echo "$name" | xargs)
    slug=$(echo "$slug" | xargs)


    local content
    content=$(cat "$blue_dir_file")

    # 2. Check de variáveis não processadas
    if [[ "$content" == *"{{\$"* ]]; then
        echo "❌ Erro: O Blueprint ainda contém variáveis de template ($blue_dir_file)" >&2
        return 1
    fi

    # --- SECURE INSPECTION (yq + jq) ---
    echo -e "  \e[1;34m🔍 Final Metadata Inspection:\e[0m"  >&2
    echo "$content" | yq eval ".metadata" - -o json 2>/dev/null | jq -C '.' |  sed 's/^/      /'  >&2
    # ----------------------------------    
    local payload=$(
        jq -n --arg yaml "$content" \
            --arg n "$name" \
            --arg s "$slug" \
            --argjson e "${_enabled:-true}" \
            '{name: $n, slug: $s, content: $yaml, enabled: $e}')
    
    apply() {
        require_vars content payload blue_dir_file AUTHENTIK_BLUE_API_URL || return 1
        
        (
            # 1. Garantir Token na Memória
            PROVIDER_SELECT="mem" core_secret_service_get "authentik/AUTHENTIK_API_TOKEN" >/dev/null 2>&1
            [[ -z "$AUTHENTIK_API_TOKEN" ]] && { echo "❌ [BLUEPRINT] Erro: AUTHENTIK_API_TOKEN não encontrado." >&2; return 1; }

            # 2. Verificar se já existe
            local response
            response=$(blue__get_current_json "$blue_dir_file")
            local pk=$(echo "$response" | jq -r '.pk // empty')            
            
            local api_res
            if [[ -z "$pk" ]]; then
                echo "🆕 Creating blueprint..." >&2
                echo $payload | jq . >&2
                api_res=$(curl -s -k -L -X POST "$AUTHENTIK_BLUE_API_URL" \
                            -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
                            -H "Accept: application/json" \
                            -H "Content-Type: application/json" \
                            -d "$payload")
                
                pk=$(echo "$api_res" | jq -r '.pk // empty' 2>/dev/null)
                if [[ -z "$pk" ]]; then
                    echo "❌ API Error Response:" >&2
                    echo "$api_res" | jq '.' 2>/dev/null || echo "$api_res" >&2
                    return 1
                fi
            else             
                echo "🔄 Found existing PK: $pk. Updating content..." >&2
                # Correção da sintaxe do curl e da URL (garantir a barra final)
                api_res=$(curl -s -k -L -X PATCH "${AUTHENTIK_BLUE_API_URL}${pk}/" \
                        -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
                        -H "Content-Type: application/json" -d "$payload")
            fi

            # 3. Aplicar o Blueprint (Triggers a execução do YAML no Authentik)
            echo "⏳ Applying blueprint changes (ID: $pk)..." >&2
            
            # O endpoint de apply retorna 200/204 ou erro se o YAML for inválido
            local apply_http_code
            apply_http_code=$(curl -s -k -L -o /dev/null -w "%{http_code}" -X POST "${AUTHENTIK_BLUE_API_URL}${pk}/apply/" \
                -H "Authorization: Bearer $AUTHENTIK_API_TOKEN")
            
            if [[ "$apply_http_code" =~ ^2[0-9][0-9]$ ]]; then
                echo -e "✅ \e[1;32mApplied successfully:\e[0m $blue_dir_file" >&2
                return 0
            else
                echo -e "⚠️ \e[1;31mApply call returned HTTP $apply_http_code. Check Authentik system tasks.\e[0m" >&2
                return 1
            fi
        ) || return 1
    }
    apply
}
# 2. O Processador (Faz a substituição real)

blue_delete() {
    local blueprint_path="$1"
    require_vars blueprint_path AUTHENTIK_BLUE_API_URL || return 1
    (
        # 1. Obter dados atuais do blueprint
        local response
        response=$(blue__get_current_json "$blueprint_path")
        local pk=$(echo "$response" | jq -r '.pk // empty')

        if [[ -z "$pk" ]]; then
            echo "ℹ️  Blueprint não encontrado no Authentik. Nada para apagar." >&2
            return 0
        fi

        echo "🗑️  Eliminando blueprint: $(basename "$blueprint_path") (PK: $pk)..." >&2
        
        # 2. Garantir Token
        PROVIDER_SELECT="mem" core_secret_service_get "authentik/AUTHENTIK_API_TOKEN" >/dev/null

        # 3. Executar DELETE
        local http_code
        http_code=$(curl -s -k -o /dev/null -w "%{http_code}" -X DELETE \
            -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
            "${AUTHENTIK_BLUE_API_URL}${pk}/")

        if [[ "$http_code" == "204" || "$http_code" == "200" ]]; then
            echo "✅ Blueprint removido com sucesso." >&2
            return 0
        else
            echo "❌ Falha ao apagar. Código HTTP: $http_code" >&2
            return 1
        fi
    ) || return 1
}
blue_apply() {
    require_locations AUTHENTIK_BLUE_DIR || return 1
    local _file="$1"
    local _enabled="${2:-true}"
    local blue_dir_file="$AUTHENTIK_BLUE_DIR/$(basename "$_file")"
    local _file_cli_relative=$(core_relative_path2 $_file)
    require_files _file || return 1

    (                
        #require_files _file || return 1
        cd $(realpath $AUTHENTIK_BLUE_DIR)        
        local entry 
        if entry=$(blue_file_valid "$blue_dir_file"); then            
            {
                echo "📝 blue apply: $entry, enabled: $_enabled" >&2                                                 
                if ! _blue_server_apply_blueprint "$blue_dir_file" "$_enabled"; then
                    echo "❌ Error: blue apply blueprint '$(core_relative_path2 $blue_dir_file)' to server" >&2
                    return 1
                fi
            }
        else
            echo "❌ Error: blue apply '$(core_relative_path2 $blue_dir_file)' is not a blueprint valid file." >&2
            return 1
        fi       
    )  
}
export -f blue_apply



# Apply Home2500 base
#blue_apply "core-home2500.yaml"
#blue_template_show_match_vars "blueprint-home2500-OIDC-tpl.yaml"
outpost__get_current_json() {
    # 3. Obter Token e fazer a chamada (SEM subshell de execução)
    # Importante: Não uses $(...) para envolver o bloco inteiro se queres apenas o output
    
    # Garante que o segredo está na memória
    (
        PROVIDER_SELECT="mem" core_secret_service_get "authentik/AUTHENTIK_API_TOKEN" >/dev/null 2>&1
        
        if [[ -z "$AUTHENTIK_API_TOKEN" ]]; then
            echo "❌ Erro: AUTHENTIK_API_TOKEN não encontrado na memória." >&2
            return 1
        fi

        local response
            # 1. Fetch Outpost State
        response=$(curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
            "$AUTHENTIK_URL/api/v3/outposts/instances/" )    

        # 5. Retorno do JSON puro para o chamador
        if echo "$response" | jq -e '.results[0]' >/dev/null 2>&1; then
            echo "$response" | jq -e '.results[0]' # Este é o único output para o stdout
        else
            echo "❌ Erro: Resposta da API inválida ou vazia." >&2
            echo "Debug: $response" >&2
            return 1
        fi
    )
}
_outpost_provider_engine() {
    local operator="$1"   # add | remove | sync
    local target_name="$2" # the provider name (required for add/remove)
    
    require_vars operator target_name "DOMAIN" || return 1

    (
        PROVIDER_SELECT="mem" core_secret_service_get "authentik/AUTHENTIK_API_TOKEN" >/dev/null 2>&1
        
        if [[ -z "$AUTHENTIK_API_TOKEN" ]]; then
            echo "❌ Erro: AUTHENTIK_API_TOKEN não encontrado na memória." >&2
            return 1
        fi
        # 1. Fetch Outpost State
        local outpost_data=$(curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
            "$AUTHENTIK_URL/api/v3/outposts/instances/")    
        local outpost_pk=$(echo "$outpost_data" | jq -r '.results[0].pk // empty')
        local current_pks=$(echo "$outpost_data" | jq -c '.results[0].providers // []')

        [[ -z "$outpost_pk" ]] && { echo "❌ Outpost not found" >&2; return 1; }

        # 2. Define the JQ operation based on the operator
        local jq_op=""
        case "$operator" in
            add)
                [[ -z "$target_name" ]] && return 1
                local pk=$(curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
                    "$AUTHENTIK_URL/api/v3/providers/proxy/?search=$target_name" | jq -r '.results[0].pk // empty')
                [[ -z "$pk" || "$pk" == "null" ]] && { echo "⚠️ Provider $target_name not found" >&2; return 1; }
                jq_op=". + [$pk] | unique"
                echo "➕ Adding \"$target_name\" (PK: $pk)..." >&2
                ;;
            remove)
                [[ -z "$target_name" ]] && return 1
                local pk=$(curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
                    "$AUTHENTIK_URL/api/v3/providers/proxy/?search=$target_name" | jq -r '.results[0].pk // empty')
                [[ -z "$pk" || "$pk" == "null" ]] && { echo "ℹ️ $target_name not found, skipping remove">&2; return 0; }
                jq_op=". - [$pk]"
                echo "➖ Removing $target_name (PK: $pk)..." >&2
                ;;
            sync)
                local available_pks=$(curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
                    "$AUTHENTIK_URL/api/v3/providers/proxy/?page_size=100" | jq -c '[.results[].pk]')
                jq_op=". + $available_pks | unique"
                echo "🔄 Synchronizing all available proxy providers..." >&2
                ;;
            *)
                echo "❌ Unknown operator: $operator" >&2
                return 1
                ;;
        esac

        # 3. Calculate and Patch
        local updated_pks=$(echo "$current_pks" | jq -c "$jq_op")

        if [[ "$current_pks" == "$updated_pks" ]]; then
            echo "✅ Outpost is already up to date." >&2
            return 0
        fi

        #echo "" >&2
        #echo "PATCH res" >&2
        # 4. Envia o PATCH e valida o conteúdo resultante
        echo -e "\n📡 Patching Authentik Outpost..." >&2
        local patch_res=$(curl -s -k -X PATCH "$AUTHENTIK_URL/api/v3/outposts/instances/$outpost_pk/" \
            -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"providers\": $updated_pks}" | jq -r '.')
        
        echo $patch_res | \
            jq -r '. | "✨ Outpost: \(.name) (PK: \(.pk)) patched\n🔗 Providers: " + ( [.providers_obj[] | "\(.name) (id:\(.pk))"] | join(", ") )' >&2
        return 1        
    )
}

blue_outpost_add_provider() {
    local name="$1"
    require_vars name
    _outpost_provider_engine add "$name"
}

blue_outpost_sync() {
    _outpost_provider_engine sync
}

blue_outpost_remove_provider() {
    local name="$1"
    require_vars name
    _outpost_provider_engine remove "$name"
}


blue_load_requirements() {
    ##### BLUEPRINT home2500
    require_vars DOMAIN \
        VAULT_CACERT \
        VAULT_INTERNAL_NS \
        VAULT_NS \
        AUTHENTIK_DIR \
        AUTHENTIK_ADMIN_USER \
        AUTHENTIK_API_TOKEN \
        AUTHENTIK_URL 
    
    export AUTHENTIK_BLUE_API_URL="$AUTHENTIK_URL/api/v3/managed/blueprints/"
    export AUTHENTIK_BLUE_DIR="$(realpath "$AUTHENTIK_DIR/blueprints")"
    
    require_functions require_vars \
        ak_load_requirements \
        ak_fix_proxied_redir \
        core_secret_service_put
    
    require_vars \
        AUTHENTIK_BLUE_DIR \
        AUTHENTIK_BLUE_API_URL 
    
    eval "BLUEPRINTS=($(blue_folder_valid_entries "$AUTHENTIK_BLUE_DIR"))"
}

blue_fn_sort_weights() {
    local rules_json
    rules_json=$(cat <<-'EOF'
[
  {
    "prefix": "blue_*",
    "weight": 20,
    "cat": "CLI-BLUE"
  },  
  {
    "prefix": "_*",
    "refine": "",
    "weight": 32,
    "cat": "PRIVATE-BLUE"
  },
  {
    "prefix": ".",
    "refine": "",
    "weight": 90,
    "cat": "MISC-BLUE"
  }
]
EOF
)
    echo "$rules_json" | jq -c '
        map(. + {refine: (.refine // "")}) 
        | sort_by(.weight, .prefix) 
    '
}

blue_fn_catalog() {
    core_fn_catalog "${BASH_SOURCE[0]}"  "blue_fn_sort_weights"
}

unset BLUE_SKIP_INTERACTION
BLUE_SKIP_INTERACTION=false
if [[ ! -t 1 && ! -t 2 ]]; then    
    # Estamos em "Silent Mode" (source > /dev/null 2>&1)
    # Podemos pular comandos visuais pesados como o stack_trace()
    BLUE_SKIP_INTERACTION=true
fi
echo "BLUE_SKIP_INTERACTION=$BLUE_SKIP_INTERACTION"
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    # Opcional: Inicia core_load_requirements semnpre que em script esteja em mode source
    blue_load_requirements

    if [[ "$BLUE_SKIP_INTERACTION" != "true" ]]; then
        ak_login
        

        # Sugestão de comandos após o source bem sucedido
        echo -e "\n📦 Authentik BLUE module loaded. client available commands:"
        echo -e "   \e[1;34mblue_<tab>\e[0m to list functions"
        blue_fn_catalog
        #list_functions "${BASH_SOURCE[0]}" "_blue_*";     
        #list_functions "${BASH_SOURCE[0]}" "blue_*";     
    else
        echo "⚠️  Non-interactive mode: skipping token validation." >&2
    fi

fi