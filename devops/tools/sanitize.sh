#!/bin/bash

# Exit on error
# set -e

set +e

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ This is a library and should be sourced, not run directly."  >&2
    echo "     Try: source ./$(realpath --relative-to="$PWD" "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
    return 1 2> /dev/null || exit 1
fi

# 1. Higieniza nomes de caminhos (Permite barras '/' mas remove caracteres perigosos)
sanitize_path_name() {
    local input="$1"
    # Remove espaços, remove caracteres especiais exceto '/' '.' '-' '_'
    # Converte tudo o que não seja permitido para '_'
    echo "${input//[^a-zA-Z0-9./_-]/_}" | sed 's|//*|/|g'
}

# 2. Higieniza nomes de bases de dados / identificadores SQL
# Normalmente DBs só aceitam letras, números e underscores
sanitize_db_name() {
    local input="$1"
    # Remove espaços e converte tudo o que não for alfanumérico ou underscore para '_'
    # Força minúsculas (bom para consistência em DBs)
    echo "${input//[^a-zA-Z0-9_]/_}" | tr '[:upper:]' '[:lower:]'
}

# 3. Refinamento do teu sanitize_var_name (evitar que comece com números se necessário)
sanitize_var_name() {
    local var_name=$1
    # 1. Transforma pontos e traços em underscores
    # 2. Remove caracteres não alfanuméricos residuais
    echo "$var_name" | sed 's/[.-]/_/g' | sed 's/[^a-zA-Z0-9_]//g' 
}
