#!/bin/bash

# Exit on error
# set -e

set +e

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ This is a library and should be sourced, not run directly."  >&2
    return 1
fi

#-------------------------------------------------------------------------------
# @function git_project_root
# @description Localiza a raiz do projeto (onde está o .git)
#-------------------------------------------------------------------------------
git_project_root() {
    local root
    root=$(git rev-parse --show-toplevel 2>/dev/null)
    
    if [[ -n "$root" ]]; then
        echo "$root"
        return 0
    else
        # Se falhar (ex: dentro de um submodule ou erro de perm), tenta subir manualmente
        local curr="$PWD"
        while [[ "$curr" != "/" ]]; do
            [[ -d "$curr/.git" ]] && echo "$curr" && return 0
            curr=$(dirname "$curr")
        done
    fi
    return 1
}
git_relative_path2() {
    local the_file="$1"
    (
        cd $(git_project_root)
        # Se o ficheiro não existir ou realpath falhar, mantém o original
        realpath --relative-to="$PWD" "$the_file" 2>/dev/null || echo "$the_file"
    )
}

#-------------------------------------------------------------------------------
# @function git_project_root_depth
# @description Calcula a profundidade (L) do PWD em relação à raiz do Git
#-------------------------------------------------------------------------------
git_project_root_depth() {
    local root_dir
    root_dir=$(git rev-parse --show-toplevel 2>/dev/null)
    
    if [[ -z "$root_dir" ]]; then
        echo "0" # Se não for Git, assume Root (L0)
        return
    fi

    # Calcula a distância: remove a root do PWD e conta as barras /
    local relative_path="${PWD#$root_dir}"
    relative_path="${relative_path#/}" # Remove barra inicial se existir
    
    if [[ -z "$relative_path" ]]; then
        echo "0"
    else
        # Conta o número de pastas no caminho relativo
        local depth
        depth=$(echo "$relative_path" | tr -cd '/' | wc -c)
        echo $((depth + 1))
    fi
}
