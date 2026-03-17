#!/bin/bash
# Filename: ../../../devops/authentik/./theme/_build.sh

set +e

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ This is a library and should be sourced, not run directly."  2>&1
    return 1 2>/dev/null || exit 1    
fi


# catch operating folder
_BUILD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd $_BUILD_DIR
source $(realpath "../_0-authentik_lib.sh")
cd $_BUILD_DIR
echo "working dir: $_BUILD_DIR"

_THEME_DIR="../../authentik/theme" # hard code expected context
require_locations _THEME_DIR
# Versão silenciosa do teu check
[[ "$_BUILD_DIR" == "$(realpath $_THEME_DIR)" ]] || echo "Wrong script context" >/dev/null 2>&1

# make sure  theme_dir is on 
theme_assets_dir="$_THEME_DIR/assets"
theme_assests_map="$_THEME_DIR/assets.map"

require_locations theme_assets_dir || mkdir -p "$theme_assets_dir"
require_files theme_assests_map || echo "#Create file: $theme_assests_map | home2500
assets[\"assets/home2500.jpg\"]=\"/web/dist/assets/images/home2500.jpg\"
assets[\"assets/home2500-dark.jpg\"]=\"/web/dist/assets/images/home2500-dark.jpg\"
assets[\"assets/authentik-home2500.svg\"]=\"/web/dist/assets/icons/authentik-home2500.svg\"
assets[\"assets/home2500-icon.svg\"]=\"/web/dist/assets/icons/home2500-icon.svg\"
assets[\"assets/home2500.css\"]=\"/web/dist/custom.css\" 
assets[\"js/theme-toggle.js\"]=\"/web/dist/theme-toggle.js\" > $theme_assests_map
"

branding_file_theme() {
    local THEME="${1^^}"
    echo "$_BUILD_DIR/branding-${THEME,,}.json"
}

container="authentik-server"
brand_domain="auth.$DOMAIN"

_authentik_asset_exist() {
    local target_path="$1"
    
    # 1. Validar se o mapa existe antes de carregar
    if [[ ! -f "$theme_assests_map" ]]; then
        echo "⚠️  Mapa de assets não encontrado em: $theme_assests_map" >&2
        return 1
    fi

    # 2. Carregar o Mapa (usando subshell para não poluir o ambiente)
    declare -A assets
    source "$theme_assests_map"

    # 3. Procurar o valor no array associativo
    for dest in "${assets[@]}"; do
        if [[ "$dest" == "$target_path" ]]; then
            return 0 # Encontrado
        fi
    done

    return 1 # Não encontrado
}
_authentik_asset_exist_published() {
    local target_dest="$1" # Opcional: Caminho no container (ex: /web/dist/custom.css)
    
    declare -A assets
    source "$theme_assests_map"

    for dest in "${assets[@]}"; do
        # Se passarmos um argumento, ignoramos os outros assets
        if [[ -n "$target_dest" && "$dest" != "$target_dest" ]]; then
            continue
        fi

        local asset_url=$(map_asset_to_url "$dest")
        
        # Fazemos o check e guardamos o status
        local status=$(cr_curl_https_status "$asset_url" 2>/dev/null | head -n 1)
        
        if [[ "$status" == *"200"* ]]; then
            echo "✅ PUBLISHED: $asset_url ($status)" >&2
        else
            echo "❌ FAILED: $asset_url ($status)" >&2
            [[ -n "$target_dest" ]] && return 1 # Falha imediata se for um check específico
        fi
    done
}
_copy_authentik_branding_assets() {
    require_vars DOMAIN theme_assests_map _THEME_DIR

    # 1. Carregar o Mapa
    # O ficheiro deve ter: assets["assets/ficheiro.jpg"]="/caminho/no/docker"
    declare -A assets
    source "$theme_assests_map"

    echo "📦 [Docker] Transferindo assets para $container..."
    show_vars container 
    for src_rel in "${!assets[@]}"; do
        local dest="${assets[$src_rel]}"
        local src_full="$_THEME_DIR/$src_rel" # Resolve o caminho real
        
        require_files src_full
        if [[ -f "$src_full" ]]; then                 
            # Unlock & Log
            docker exec -u root "$container" bash -c "chown authentik:authentik '$dest' 2>/dev/null || true"
            
            # Copy
            docker cp "$src_full" "$container:$dest"
            
            # Lock & Verify
            docker exec -u root "$container" bash -c "
                chown root:root '$dest'
                chmod 644 '$dest'
                ls -la '$dest' | grep -q '$(basename "$dest")' && echo '✅ $(basename "$src_rel") -> $dest'
            "
        else
            echo "⚠️  Ficheiro não encontrado: $src_full"
        fi
    done

    # --- PARTE 2: TESTE DE ACESSIBILIDADE ---
    echo "🚀 Validando URLs públicas..."
    for dest in "${assets[@]}"; do
        local asset_url=$(map_asset_to_url "$dest")
        echo -n "🌍 $asset_url: "
        # head -n 1 para mostrar apenas o status HTTP (200 OK)
        cr_curl_https_status "$asset_url" 2>/dev/null | head -n 1
    done
}
map_asset_to_url() {
    local container_path="$1"
    # Mapeamento do Authentik: /web/dist/ -> /static/dist/
    local public_path=$(echo "$container_path" | sed 's|/web/dist/|/static/dist/|')
    echo "https://${brand_domain}${public_path}"
}
_get_default_brand_pk() {
    local url="${AUTHENTIK_INTERNAL_URL:-"http://authentik-server.app-network:9000"}"
    # Pegamos o ID da marca 'authentik-default'
    local pk
    local resp
    resp=$(curl -s -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
        "$url/api/v3/core/brands/" | jq -r '.')
    #pk=$(echo $resp | jq -r '.results[0].pk // empty')
    pk=$(echo $resp | jq -r '.results[0].brand_uuid // empty')
    if [[ -z "$pk" ]]; then
        echo "❌ Erro ao capturar brand_pk. API ainda offline ou Token inválido." >&2
        echo $rest | jq . >&2
        return 1
    fi
    export brand_pk="$pk"
    echo "$pk"
}
_apply_authentik_branding() {
    require_vars DOMAIN AUTHENTIK_API_TOKEN
    local branding_file="$(branding_file_theme "${1:-DARK}")"
    
    if [[ ! -f "$branding_file" ]]; then
        echo "❌ Erro: Ficheiro $branding_file não encontrado!"
        return 1
    fi
    local branding_json=$(cat $branding_file | jq .)


    # --- PARTE 2: API LOGIC ---
    # Update da Brand (Tema, Cores, Background)
    local brand_pk="$(_get_default_brand_pk)"

    #local brand=$(curl -k -s -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
    #    "https://${brand_domain}/api/v3/core/brands/" | jq -r '.')    
    # O -r (raw) remove as aspas do valor extraído
    #local brand_pk="$(echo $brand | jq -r '.results[0].brand_uuid')"

    require_vars brand_pk || {
        echo $brand | jq .
        return 1
    }

    echo "🔗 [DEBUG] Brand $brand_pk..."
    echo "-- current brand .results[0]"
    echo $brand | jq '.results[0]'
    echo "-- $(basename $branding_file)"
    echo $branding_json | jq . 
    
    echo "🔗 [API] A atualizar Brand $brand_pk..."

    # review assets. ned to make sur $branding_json  as  resource ref exists
    # 1. Extraímos o background com um fallback seguro
    local flow_bg=$(echo "$branding_json" | jq -r '.attributes.settings.background // ""')
    if ! _authentik_asset_exist "$flow_bg"; then
        echo "🚀 Background validado e online. Aplicando PATCH..."      
    else
        echo "⚠️  Warning: Background $flow_bg resource is not defined on assets.map yet."
    fi

    # 2. Construímos o JSON final usando --arg para evitar problemas de escape de caracteres
    # O comando abaixo pega no branding_json e força a atualização do campo background
    local final_payload=$(echo "$branding_json" | jq --arg bg "$flow_bg" '.attributes.settings.background = $bg')

    local response=$(curl -k -s -X PATCH "https://${brand_domain}/api/v3/core/brands/${brand_pk}/" \
         -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
         -H "Content-Type: application/json" \
         -d "$final_payload")

    # Verifica se o retorno tem o que queremos, caso contrário mostra o erro
    if [[ $(echo "$response" | jq -r '.branding_title') != "null" ]]; then
        echo "✅ Brand atualizada: $(echo "$response" | jq -r '.brading_title')"
        echo "$response" | jq -r '.'
    else
        echo "❌ Erro na API: $(echo "$response" | jq -c '. // "Sem resposta do servidor"')"
        return 1
    fi

    # Sincronização automática do Flow com o Layout definido no JSON
    local flow_layout=$(echo "$branding_json" | jq -r '.attributes.settings.layout // "sidebar_left"')
    
    echo "🔗 [API] Sincronizando Flow (Layout: $flow_layout)"
    curl -k -s -X PATCH "https://${brand_domain}/api/v3/flows/instances/default-authentication-flow/" \
        -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"layout\": \"$flow_layout\"}" | jq '.' > /dev/null
        
}


_get_brand_themes() {
    # Verifica se o diretório existe para evitar erros de ls
    if [[ ! -d "$_THEME_DIR" ]]; then
        echo "[]"
        return
    fi

    # Inicializa um array JSON vazio
    local array_themes="[]"

    # Loop pelos ficheiros branding-*.json
    for file in "$_THEME_DIR"/branding-*.json; do
        
        # EXCLUSÃO: Se o nome do ficheiro contiver "copy", salta para o próximo
        if [[ "$file" == *"copy"* ]]; then
            continue
        fi
        # Verifica se o ficheiro existe (evita erro se não houver match)        
        [[ -e "$file" ]] || continue

        # Extrai o nome do tema a partir do nome do ficheiro (ex: dark, light)
        local theme_name=$(basename "$file" | sed 's/branding-\(.*\)\.json/\1/')
        
        # Lê o conteúdo do ficheiro e adiciona uma chave "id" para o seletor
        local theme_content=$(cat "$file" | jq --arg id "$theme_name" '. + {id: $id}')

        # Faz o merge no array principal
        array_themes=$(echo "$array_themes" | jq --argjson new "$theme_content" '. += [$new]')
    done

    # Output do JSON final formatado
    echo "$array_themes" | jq .
}

_get_brand_theme_ids() {
    #_get_brand_themes | jq -r '[.[].id | (.[0:1] | ascii_upcase) + .[1:]]'
    #_get_brand_themes | jq -r '[.[].id | ascii_upcase]'
    echo $(_get_brand_themes) | jq '[.[].id]'
}
_get_brand_theme_ids() {
    # Gera um array JSON com os IDs originais e capitalizados para labels
    _get_brand_themes | jq '[.[] | {id: .id, label: ((.id[0:1] | ascii_upcase) + .id[1:])}]'
}


_build_brand_theme() {

    local target_id="${1:-dark}"
    local themes_json=$(_get_brand_themes)
    local theme_exists=$(echo "$themes_json" | jq --arg id "$target_id" 'any(.[]; .id == $id)')

    if [[ "$theme_exists" == "true" ]]; then
        _copy_authentik_branding_assets
        _apply_authentik_branding "$target_id"
    else
        echo "❌ Tema '$target_id' inválido. Disponíveis: $(echo "$themes_json" | jq -r '.[].id' | xargs)"
    fi
}

choose_and_apply() {
    local ids=$(echo "$(_get_brand_themes)" | jq -r '.[].id')
    PS3="🎨 Home2500 | Select Theme: "
    select opt in $ids; do
        [[ -n "$opt" ]] && { _build_brand_theme "$opt"; break; } || echo "Invalido."
    done
}

require_functions \
    ak_api_token_generate \
    ak_api_token_restore

echo "You may need to:"
echo "- . ../../vault/vault_lib.sh"
echo "- vault_request_stew_token"
echo "- ak_api_token_generate"
echo "- _copy_authentik_branding_assets"
echo "- _apply_authentik_branding"
echo "- _build_brand_theme"


# --- EXECUTION ---
echo "🛠️ Home2500 Branding Engine Loaded."
_get_brand_theme_ids
require_vars AUTHENTIK_API_TOKEN && { \
        ak_api_token_validate || {
            echo "run:"
            echo "ak_api_token_restore"    
            echo "ak_api_token_generate"    
        }
    } || { 
        echo "run:"
        echo "ak_api_token_generate"
    }


echo "choose_and_apply"
echo "_build_brand_theme <theme>"
