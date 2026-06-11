#!/bin/bash

# Exit on error
# set -e

set +e

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ This is a library and should be sourced, not run directly."  >&2
    echo "     Try: source ./$(realpath --relative-to="$PWD" "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
    return 1 2> /dev/null || exit 1
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

git_remote_root_url() {
    git remote get-url origin
}

### do not handle outter workspace relative paths
git_relative_path() {
    local the_path="${1:-.}"
    if ! the_path=$(realpath $the_path);then
        return 1
    fi
    (
        cd $(git_project_root)
        # Se o ficheiro não existir ou realpath falhar, mantém o original
        realpath --relative-to="$PWD" "$the_path" 2>/dev/null || echo "$the_path"
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


git_project_remote_owner() {
    export REMOTE_URL=$(git config --get remote.origin.url)

    # Extract username from HTTPS URL
    if [[ $REMOTE_URL == *"https://github.com/"* ]]; then
        export USERNAME=$(echo "$REMOTE_URL" | sed -n 's#.*/\([^/]*\)/.*#\1#p')
        echo "GitHub Username: $USERNAME"
    fi

    # Extract username from SSH URL
    if [[ $REMOTE_URL == *"git@github.com:"* ]]; then
        export USERNAME=$(echo "$REMOTE_URL" | sed -n 's#git@github.com:\([^/]*\)/.*#\1#p')
        echo "GitHub Username: $USERNAME"
    fi

    echo "Remote Repository Username: $USERNAME"

    # Extract most recent commit author
    AUTHOR=$(git log -1 --pretty=format:"%an <%ae>")
    echo "Most Recent Commit Author: $AUTHOR"

    # Extract all unique authors
    echo "All Unique Authors:"
    git log --pretty=format:"%an <%ae>" | sort | uniq
}