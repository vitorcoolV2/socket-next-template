#!/bin/bash

# Exit on error
# set -e

set +e

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ This is a library and should be sourced, not run directly."  >&2
    echo "     Try: source ./$(realpath --relative-to="$PWD" "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
    return 1 2> /dev/null || exit 1
fi

# ---------------------------------------------------------
# 🛠️ String Transformation Shortcuts (The Steward's Tools)
# ---------------------------------------------------------



core_transform_inject_env_file_vars() {
    local env_file="${1:-".env"}"
    local match_prefix="${2}" # diz ao regex: "comece no início da linha"
    local replace_prefix="${3}"
    # Substituí * por .* para funcionar corretamente no Regex do Bash
    local match_prefix_exceptions="${4:-ENV.*}"

    if [[ ! -f "$env_file" ]]; then
        echo "⚠️  [WARN] Ficheiro $env_file não encontrado." >&2
        return 1
    fi

    echo -e "📦 Extraindo variáveis $(echo $env_file | rev | cut -d'/' -f1-3 | rev) 
    (match:replace)=>($match_prefix -> $replace_prefix) ..." >&2

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue

        if [[ "$line" =~ ^"$match_prefix" ]]; then
            local key="${line%%=*}"
            local value="${line#*=}"

            # Remove o prefixo para validar a exceção
            local short_key="${key#$match_prefix}"
            #show_vars key value  short_key
            # Lógica de Exceção Corrigida
            if [[ -n "$match_prefix_exceptions" ]]; then
                if [[ "$short_key" =~ ^($match_prefix_exceptions)$ ]]; then
                    echo "   🚫 [Skip] $key coincide com exceção." >&2
                    continue
                fi
            fi

            # Limpar aspas de forma eficiente
            value="${value%\"}"
            value="${value#\"}"
            value="${value%\'}"
            value="${value#\'}"

            local new_key="${replace_prefix}${short_key}"
            export "$new_key"="$value"
            
            echo "    [export $new_key len: (${#value})]" >&2
        fi
    done < "$env_file"
}


# Redutor de strings para o Dono da Casa. O Dono agradece á entidade enriquecida com simpatia e humanidade
core__transform_string() {
    local str="$1"
    local mode="${2:-pascal}"
    
    # Base Limpa: Remove separadores e normaliza para minúsculas
    local clean=$(echo "$str" | tr '[:upper:]' '[:lower:]' | sed -r 's/([-._:+ /]+)/ /g' | sed 's/^ //;s/ $//')

    case "$mode" in
        # --- Família Human (Semântica) ---
        human)    echo "$clean" ;;                               # rainha do baralho
        Human)    echo "${clean^}" ;;                            # Rainha do baralho
        HuMan)    local res=""; for w in $clean; do res+="${w^} "; done; echo "${res% }" ;; # Rainha Do Baralho
        HUMAN)    echo "${clean^^}" ;;                           # RAINHA DO BARALHO

        # --- Família Code (Sintaxe) ---
        pascal)   local res=""; for w in $clean; do res+="${w^}"; done; echo "$res" ;;      # RainhaDoBaralho
        camel)    local res=""; for w in $clean; do res+="${w^}"; done; echo "${res,}" ;;   # rainhaDoBaralho
        flat)     echo "${clean// /}" ;;                         # rainhadobaralho
        
        # --- Família System (Infra) ---
        kebab)    echo "${clean// /-}" ;;                        # rainha-do-baralho
        snake)    echo "${clean// /_}" ;;                        # rainha_do_baralho
        screaming) echo "${clean// /_}" | tr '[:lower:]' '[:upper:]' ;; # RAINHA_DO_BARALHO
        path)     echo "${clean// /\/}" ;;                       # rainha/do/baralho
        
        # --- Família UI (Visual) ---
        initials) echo "$clean" | awk '{for(i=1;i<=NF;i++) printf toupper(substr($i,1,1))}'; echo "" ;;
    esac
}
# ---------------------------------------------------------
# 🛠️ String Transformation Shortcuts (The Steward's Tools)
# ---------------------------------------------------------

# provision_db -> provisionDb (Para JSON/JS)
to_camel_case() {
    core__transform_string "$1" "camel"
}

# provision_db -> ProvisionDb (Para Classes/Tipos)
to_pascal_case() {
    core__transform_string "$1" "pascal"
}

# provision_db -> Provision Db (Para Logs/UI)
to_human_pascal() {
    core__transform_string "$1" "human"
}

# provision_db -> provision-db (Para K8s/Docker)
to_kebab_case() {
    core__transform_string "$1" "kebab"
}

# provision_db -> PROVISION_DB (Para .env/Secrets)
to_screaming_snake() {
    core__transform_string "$1" "screaming"
}

# provision_db -> provision/db (Para Pastas/Namespaces)
to_path_case() {
    core__transform_string "$1" "path"
}

# provision_db -> provision_db (Slug Standard)
to_snake_case() {
    core__transform_string "$1" "snake"
}

test__string_transformation() {
    # Executando o Loop de Transformação
    echo "--- 📂 TESTE DE TRANSFORMAÇÃO DE PATH ($PWD) ---"

    for mode in pascal camel \
        human HuMan Human HUMAN \
        kebab screaming \
        path snake flat initials; do
        result=$(core__transform_string "$PWD" "$mode")
        printf "%-12s | %s\n" "$mode" "$result"
    done
}

test__string_transformation > /dev/null || exit 1 # critical core expression