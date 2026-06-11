#!/bin/bash

# Exit on error
# set -e

set +e

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ This is a library and should be sourced, not run directly."  >&2
    echo "     Try: source ./$(realpath --relative-to="$PWD" "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
    return 1 2> /dev/null || exit 1
fi

_CUR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. $_CUR_DIR/git.sh



project_resources_visible() {
    local target="${1:-.}"  # Diretório ou arquivo alvo (padrão: ".")
    local recursive="${2:-true}"  # Recursividade (padrão: true)
    local mode="${3:-flat}"  # Modo de saída (padrão: "flat")

    # 1. Normalizar o caminho para evitar confusões com ".."
    local abs_target=$(realpath "$target" 2>/dev/null || echo "$target")
    local repo_root=$(git rev-parse --show-toplevel 2>/dev/null)

    # Verificar se o alvo é um arquivo
    if [[ -f "$abs_target" ]]; then
        # Se for um arquivo, exibir apenas ele
        echo "$(basename "$abs_target")"
        return
    fi

    # Continuar com o comportamento padrão para diretórios
    local raw_list=""

    if [[ -n "$repo_root" ]]; then
        # 2. Obter arquivos visíveis no Git, filtrados pelo diretório alvo
        local files=$(git ls-files --cached --others --exclude-standard --full-name "$abs_target" 2>/dev/null)

        # 3. Remover o prefixo do repositório para obter caminhos relativos ao diretório alvo
        local rel_to_root=$(realpath --relative-to="$repo_root" "$abs_target" 2>/dev/null || echo "")
        
        if [[ -z "$rel_to_root" || "$rel_to_root" == "." ]]; then
            raw_list="$files"
        else
            # Remover o prefixo do diretório alvo
            raw_list=$(echo "$files" | sed -E "s|^$rel_to_root/||")
        fi

        # Adicionar diretórios aos resultados
        local dirs=$(echo "$raw_list" | grep '/' | sed 's|/[^/]*$||' | sort -u)
        raw_list=$(echo -e "$raw_list\n$dirs" | sort -u | grep -v '^$')

        # Filtrar por recursividade
        if [[ "$recursive" == "false" ]]; then
            raw_list=$(echo "$raw_list" | grep -v '/')
        fi
    else
        # Fallback para diretórios não-Git
        local max_depth=""
        [[ "$recursive" == "false" ]] && max_depth="-maxdepth 1"
        raw_list=$(find "$abs_target" -mindepth 1 $max_depth -printf "%P\n" 2>/dev/null | sort -u)
    fi

    # 4. Formatar a saída
    if [[ "$mode" == "tree" ]]; then
        echo "📂 $target"
        echo "$raw_list" | sed -e 's|[^/]*/|  │ |g' -e 's|│ \([^/]*\)$|└── \1|'
    else
        echo "$raw_list"
    fi
}
###############################################################################
# _delta_analysis__out_of_project_scope
#
# PURPOSE:
#   Returns files that exist on disk but are NOT visible to Git (delta between
#   filesystem and Git-tracked + untracked non-ignored files)
#
# ARGUMENTS:
#   $1 - target directory (default: current directory)
#   $2 - recursive (true/false, default: true)
#
# OUTPUT:
#   Returns list of non-visible files (one per line)
#
# EXIT CODES:
#   0 - Success (always, even if no files found)
#   1 - Error (invalid directory or system error)
#
# EXAMPLE:
#   project_delta_analysis_local . true
#   # Returns: .env.local
#   #          temp.log
#   #          (empty if none found)s
###############################################################################
## to be digested in data clues. Yes i do not not what on result. But this Delta all author misses
## we digest | stream _delta_analysis__out_of_project_scope with other function
## count , like in SQL 
project_delta_analisis__out_of_scope_paths_json() {
    local target="${1:-.}"  # Diretório alvo (padrão: ".")
    local level="$2"        # Nível de profundidade
    local recursive="${3:-true}"  # Recursividade (padrão: true)

    # Função interna para calcular o delta
    _delta_enum__out_of_project_scope() {
        local target="${1:-.}"
        local recursive="${2:-true}"
        
        # Configuração de filtros
        local filters=(
            "node_modules"
            ".bun"
            ".git"
            "dist"
            "build"
            "__pycache__"
            "\.log$"
            "\.pyc$"
            "\.swp$"
            "~$"
            "\.DS_Store"
        )
        
        # Resolver target absoluto
        local abs_target=$(realpath "$target" 2>/dev/null || echo "$target")
        
        # Validar diretório
        if [[ ! -d "$abs_target" ]]; then
            echo "ERROR: Invalid directory: $target" >&2
            return 1
        fi
        
        # Obter recursos visíveis do git (ou outra lógica de visibilidade)
        local visible=$(project_resources_visible "$target" "$recursive" "flat" 2>/dev/null | sort -u)
        
        # Obter todos os arquivos no disco
        local find_opts="-type f"
        [[ "$recursive" == "false" ]] && find_opts="-maxdepth 1 -type f"
        
        local all_files=$(find "$abs_target" $find_opts 2>/dev/null | \
            sed "s|^$abs_target/||" | \
            sed "s|^\./||" | \
            sort -u)
        
        # Calcular delta (arquivos que existem mas não são visíveis)
        local delta=$(comm -23 <(echo "$all_files") <(echo "$visible") 2>/dev/null)
        
        # Aplicar filtros
        for pattern in "${filters[@]}"; do
            delta=$(echo "$delta" | grep -v "$pattern")
        done
        
        # Remover linhas vazias
        delta=$(echo "$delta" | grep -v '^$')
        
        # Saída limpa (apenas o delta)
        if [[ -n "$delta" ]]; then
            echo "$delta"
        else
            echo ""  # Retorna uma string vazia se não houver resultados
        fi
        
        # Sempre retorna 0 em caso de sucesso (mesmo sem resultados)
        return 0
    }

    # Capturar o diretório atual
    local pwd=$(pwd)

    # Executar a análise e processar os resultados
    # Capturar o resultado como array JSON
    local raw_result=$(
        _delta_enum__out_of_project_scope "$target" "$recursive" | \
        awk -v d="$level" -F'/' '
        {
            sub(/\/+$/, "", $0)
            if (NF >= d && d > 0) {
                result = $1
                for (i = 2; i <= d; i++) {
                    result = result "/" $i
                }
                print result
            } else if (d == 0) {
                print ""  # Nível 0 = raiz
            } else {
                print $0
            }
        }' | \
        sort | \
        uniq -c | \
        awk '{print "{\"distinct\":\"" $2 "\",\"count\":" $1 "}"}' | \
        jq -s -c '.' 2>/dev/null || echo '[]'
    )

        # Debug: Imprimir raw_result para verificar seu conteúdo
    echo "DEBUG: raw_result = $raw_result"
    # Garantir que raw_result é um array JSON válido
    if [[ -z "$raw_result" || "$raw_result" == "null" ]]; then
        raw_result='[]'
    fi

    # Construir o JSON final
    jq -n \
        --arg descricao "Análise de caminhos fora do escopo do projeto" \
        --argjson level "${level:-0}" \
        --argjson recursive "$( [[ "$recursive" == "true" ]] && echo true || echo false )" \
        --arg pwd "$pwd" \
        --argjson result "$raw_result" \
        '{
            descricao: $descricao,
            context: {
                level: $level,
                recursive: $recursive,
                pwd: $pwd
            },
            result: $result
        }'
}
project_ls() {
    local target="${1:-.}"          # Default to current directory.
    local recursive="${2:-true}"    # Default to recursive listing.
    local mode="$3"

    # Remove trailing slash for consistency.
    target="${target%/}"

    # Resolve target relative to $PWD.
    targetTerminal=$(realpath --relative-to="$PWD" "$target")
    
    # Check if the target exists.
    if [[ ! -e "$target" ]]; then
        echo "Error: Target '$target' does not exist."
        return 1
    fi
    (        
        # Get visible files and directories.
        local visible_files=$(project_resources_visible "$target" "$recursive" "$mode")

        # Adjust output to be relative to $PWD.
        visible_files=$(echo "$visible_files" | sed "s|^$PWD/||")

        # Output the results.
        echo "$visible_files"
    )
}

project_permissions_base_json_podes_apage_este() {
    local target_dir="${1:-.}"
    local recursive="${2:-true}"
    
    # Normalize the target directory path
    local abs_target=$(realpath "$target_dir" 2>/dev/null || echo "$target_dir")

    # Check if the target path is a file or directory
    if [[ -f "$abs_target" ]]; then
        # Process as a single file
        resources=("$abs_target")
    elif [[ -d "$abs_target" ]]; then
        # Process as a directory
        resources=$(project_ls "$abs_target" "flat" | tr '\n' ' ')
    else
        echo "ERROR: Target path does not exist or is invalid: $abs_target" >&2
        return 1
    fi

    local results=()

    for resource in $resources; do
        # Skip empty lines
        [[ -z "$resource" ]] && continue

        # Normalize the path to ensure consistency
        local abs_resource=$(realpath "$abs_target/$resource" 2>/dev/null || echo "$resource")

        # Check if the resource exists
        if [[ ! -e "$abs_resource" ]]; then
            results+=("$(jo resource="$resource" error="file_not_found" permissions=null)")
            continue
        fi

        # Get all stat info
        if stat_info=$(stat -c "%a|%U|%G|%F|%u|%g|%s|%y|%n" "$abs_resource" 2>/dev/null); then
            IFS='|' read -r perms owner group type uid gid size modified name <<< "$stat_info"
            
            # Calculate symbolic permissions
            user_r=$(( (perms & 400) > 0 ))
            user_w=$(( (perms & 200) > 0 ))
            user_x=$(( (perms & 100) > 0 ))
            group_r=$(( (perms & 040) > 0 ))
            group_w=$(( (perms & 020) > 0 ))
            group_x=$(( (perms & 010) > 0 ))
            other_r=$(( (perms & 004) > 0 ))
            other_w=$(( (perms & 002) > 0 ))
            other_x=$(( (perms & 001) > 0 ))

            # Build JSON with raw permissions
            results+=("$(jo \
                resource="$resource" \
                permissions=$(jo \
                    octal="$perms" \
                    symbolic="$(printf "%s%s%s" \
                        "$([[ $user_r -eq 1 ]] && echo "r" || echo "-")" \
                        "$([[ $user_w -eq 1 ]] && echo "w" || echo "-")" \
                        "$([[ $user_x -eq 1 ]] && echo "x" || echo "-")" \
                    )$(printf "%s%s%s" \
                        "$([[ $group_r -eq 1 ]] && echo "r" || echo "-")" \
                        "$([[ $group_w -eq 1 ]] && echo "w" || echo "-")" \
                        "$([[ $group_x -eq 1 ]] && echo "x" || echo "-")" \
                    )$(printf "%s%s%s" \
                        "$([[ $other_r -eq 1 ]] && echo "r" || echo "-")" \
                        "$([[ $other_w -eq 1 ]] && echo "w" || echo "-")" \
                        "$([[ $other_x -eq 1 ]] && echo "x" || echo "-")" \
                    )" \
                    breakdown=$(jo \
                        user=$(jo read=$user_r write=$user_w execute=$user_x) \
                        group=$(jo read=$group_r write=$group_w execute=$group_x) \
                        other=$(jo read=$other_r write=$other_w execute=$other_x)
                    )
                ) \
                owner=$(jo uid="$uid" name="$owner") \
                group=$(jo gid="$gid" name="$group") \
                type="$type" \
                size="$size" \
                modified="${modified%.*}" \
                inode=$(stat -c "%i" "$abs_resource" 2>/dev/null)
            )")
        else
            results+=("$(jo resource="$resource" error="stat_failed" permissions=null)")
        fi
    done

    # Output as JSON array
    if [[ ${#results[@]} -eq 0 ]]; then
        echo "[]" | jq .
    else
        printf '[%s]\n' "$(IFS=,; echo "${results[*]}")" | jq .
    fi
}
project_permissions_base_json() {
    local target_dir="${1:-.}"
    local recursive="${2:-true}"
    
    # Normalize the target directory path
    local abs_target=$(realpath "$target_dir" 2>/dev/null || echo "$target_dir")

    # Check if the target path is a file or directory
    if [[ -f "$abs_target" ]]; then
        resources=("$abs_target")
    elif [[ -d "$abs_target" ]]; then
        resources=$(project_ls "$abs_target" "flat" | tr '\n' ' ')
    else
        echo "ERROR: Target path does not exist or is invalid: $abs_target" >&2
        return 1
    fi

    local results=()

    for resource in $resources; do
        [[ -z "$resource" ]] && continue

        # Normalize the path to ensure consistency
        local abs_resource=$(realpath "$abs_target/$resource" 2>/dev/null || echo "$resource")

        # Check if the resource exists
        if [[ ! -e "$abs_resource" ]]; then
            results+=("$(jo resource="$resource" error="file_not_found" permissions=null)")
            continue
        fi

        # Get all stat info
        if stat_info=$(stat -c "%a|%U|%G|%F|%u|%g|%s|%y|%n" "$abs_resource" 2>/dev/null); then
            IFS='|' read -r perms owner group type uid gid size modified name <<< "$stat_info"
            
            # Calculate symbolic permissions
            user_r=$(( (perms & 400) > 0 ))
            user_w=$(( (perms & 200) > 0 ))
            user_x=$(( (perms & 100) > 0 ))
            group_r=$(( (perms & 040) > 0 ))
            group_w=$(( (perms & 020) > 0 ))
            group_x=$(( (perms & 010) > 0 ))
            other_r=$(( (perms & 004) > 0 ))
            other_w=$(( (perms & 002) > 0 ))
            other_x=$(( (perms & 001) > 0 ))

            symbolic_perms=$(printf "%s%s%s%s%s%s%s%s%s" \
                "$([[ $user_r -eq 1 ]] && echo "r" || echo "-")" \
                "$([[ $user_w -eq 1 ]] && echo "w" || echo "-")" \
                "$([[ $user_x -eq 1 ]] && echo "x" || echo "-")" \
                "$([[ $group_r -eq 1 ]] && echo "r" || echo "-")" \
                "$([[ $group_w -eq 1 ]] && echo "w" || echo "-")" \
                "$([[ $group_x -eq 1 ]] && echo "x" || echo "-")" \
                "$([[ $other_r -eq 1 ]] && echo "r" || echo "-")" \
                "$([[ $other_w -eq 1 ]] && echo "w" || echo "-")" \
                "$([[ $other_x -eq 1 ]] && echo "x" || echo "-")")

            # Build JSON with raw permissions
            results+=("$(jo \
                resource="$resource" \
                permissions=$(jo \
                    octal="$perms" \
                    symbolic="$symbolic_perms" \
                    breakdown=$(jo \
                        user=$(jo read=$user_r write=$user_w execute=$user_x) \
                        group=$(jo read=$group_r write=$group_w execute=$group_x) \
                        other=$(jo read=$other_r write=$other_w execute=$other_x)
                    )
                ) \
                owner=$(jo uid="$uid" name="$owner") \
                group=$(jo gid="$gid" name="$group") \
                type="$type" \
                size="$size" \
                modified="${modified%.*}" \
                inode=$(stat -c "%i" "$abs_resource" 2>/dev/null)
            )")
        else
            results+=("$(jo resource="$resource" error="stat_failed" permissions=null)")
        fi
    done

    # Output as JSON array
    if [[ ${#results[@]} -eq 0 ]]; then
        echo "[]" | jq .
    else
        printf '[%s]\n' "$(IFS=,; echo "${results[*]}")" | jq .
    fi
}
project_permissions_asis_json() {
    local target="${1:-.}"
    local recursive="$2"

    # Generate base JSON
    local base=$(project_permissions_base_json "$target" "$recursive") || {
        echo "ERROR: Failed to generate base JSON" >&2
        return 1
    }
    
    # Check if base is a valid JSON array
    if ! echo "$base" | jq -e '. | type == "array"' >/dev/null 2>&1; then
        echo "ERROR: Invalid JSON output from base function" >&2
        echo "DEBUG: Base output was: $base" >&2
        return 1
    fi
    
    local missing_groups=()
    
    # Process each resource and build enriched array
    local enriched_json=$(echo "$base" | jq -c '.[]' | while IFS= read -r resource_json; do
        local resource=$(echo "$resource_json" | jq -r '.resource // empty')
        local group_name=$(echo "$resource_json" | jq -r '.group.name // empty')
        
        local users_json="[]"
        
        if [[ -z "$resource" ]]; then
            echo "WARNING: Missing resource field in JSON object" >&2
            continue
        fi
        
        if [[ -z "$group_name" ]] || [[ "$group_name" == "null" ]]; then
            # Log missing group info to stderr
            echo "WARNING: No group information for: $resource" >&2
            missing_groups+=("$resource")
        else
            local group_members=$(getent group "$group_name" 2>/dev/null | cut -d: -f4)
            
            if [[ -n "$group_members" ]]; then
                users_json=$(echo "$group_members" | tr ',' '\n' | while read -r member; do
                    local uid=$(id -u "$member" 2>/dev/null)
                    if [[ -n "$uid" ]]; then
                        echo "{\"uid\": $uid, \"name\": \"$member\"}"
                    fi
                done | jq -s '.')
            fi
        fi
        
        echo "$resource_json" | jq -c --argjson users "$users_json" '
            .group.users = $users
        '
    done | jq -s '.')
    
    # Output warnings if any
    if [[ ${#missing_groups[@]} -gt 0 ]]; then
        echo "WARNING: ${#missing_groups[@]} resources missing group information" >&2
    fi
    
    echo "$enriched_json" | jq .
}

project_permissions_tracker() {
    local target="${1:-.}"
    local recursive="${2:-true}"
    local expected_uid="${3:-2501}"
    local expected_gid="${4:-2500}"
    local expected_perms="${5:-750}"

    # Generate base JSON
    local asis
    asis=$(project_permissions_asis_json "$target" "$recursive") || {
        echo "ERROR: Failed to generate base JSON" >&2
        return 1
    }

    # Check if the output is a valid JSON array
    if ! echo "$asis" | jq -e 'type == "array"' >/dev/null 2>&1; then
        echo "ERROR: Invalid JSON output from base function" >&2
        echo "DEBUG: Base output was: $asis" >&2
        return 1
    fi

    # Process each resource in the array and wrap the output in an array
    echo "$asis" | jq --arg eu "$expected_uid" \
        --arg eg "$expected_gid" \
        --arg ep "$expected_perms" '
        
        # Mindfulness: accept current state
        def current: {
            uid: .owner.uid,
            gid: .group.gid,
            perms: .permissions.octal,
            owner: .owner.name,
            group: .group.name,
            resource: .resource
        };
        
        # Clarity: define expected state
        def expected: {
            uid: ($eu | tonumber),
            gid: ($eg | tonumber),
            perms: $ep
        };
        
        # Awareness: notice differences
        def differences($c; $e): {
            uid: ($c.uid != $e.uid),
            gid: ($c.gid != $e.gid),
            perms: ($c.perms != $e.perms)
        };
        
        # Action: what needs to change
        def fix_commands($r; $e): {
            chown: ("sudo chown " + ($e.uid | tostring) + ":" + ($e.gid | tostring) + " \"" + $r + "\""),
            chmod: ("sudo chmod " + $e.perms + " \"" + $r + "\"")
        };
        
        # Wisdom: is there work to do?
        def needs_fix($d): ($d.uid or $d.gid or $d.perms);
        
        # Iterate over each resource and wrap the results in an array
        map({
            target: .resource,
            expected: expected,
            current: current,
            diff: differences(current; expected),
            needs_fix: needs_fix(differences(current; expected)),
            fix_commands: fix_commands(.resource; expected)
        })
    '
}

##### TESTE IT WITH CAREFULL. 
project_delegate_execute() {
    local target="${1:-.}"

    local delegate_uid=2501  #
    local delegate_gid=2500
    
    echo "=== Delegating GID $delegate_gid to UID $delegate_uid for: $target ==="
    
    # 1. Add delegate user to group
    local delegate_name=$(getent passwd "$delegate_uid" | cut -d: -f1)
    if [[ -n "$delegate_name" ]]; then
        echo "Adding $delegate_name (UID $delegate_uid) to group GID $delegate_gid..."
        sudo usermod -a -G "$delegate_gid" "$delegate_name"
    fi
    
    # 2. Change group ownership
    echo "Changing group ownership to GID $delegate_gid..."
    sudo chgrp "$delegate_gid" "$target"
    
    # 3. Set permissions (owner: rwx, group: r-x, others: ---)
    echo "Setting permissions to 750..."
    sudo chmod 750 "$target"
    
    # 4. Show result
    echo -e "\n=== Result ==="
    stat -c "File: %n\nOwner: %U (UID %u)\nGroup: %G (GID %g)\nPermissions: %a (%A)" "$target"
    
    # 5. Track who has access now
    echo -e "\n=== Users with access ==="
    local group_members=$(getent group "$delegate_gid" | cut -d: -f4 | tr ',' '\n')
    echo "Group $delegate_gid members:"
    echo "$group_members" | sed 's/^/  - /'
    
    echo -e "\nOwner: $(stat -c '%U' "$target")"
}

