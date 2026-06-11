
#!/bin/bash

# Exit on error
# set -e

set +e

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ This is a library and should be sourced, not run directly."  >&2
    echo "     Try: source ./$(realpath --relative-to="$PWD" "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
    return 1 2> /dev/null || exit 1
fi

# Parse arguments (-L for max depth, -F for enabling col2)
parse_args() {
    local args=("$@")                # Capture all arguments as an array
    local max_depth="3"            # Default max depth
    local enable_col2_ln="true"     # Default: second column file disabled
    local enable_col2_file="false"   # Default: second column file disabled
    local enable_col2_folder="false" # Default: second column directory disabled
         

    # Iterate through arguments
    for ((i = 0; i < ${#args[@]}; i++)); do
        case "${args[i]}" in
            -L)
                # Set max depth (next argument)
                if [[ $((i + 1)) -lt ${#args[@]} ]]; then
                    max_depth="${args[i + 1]}"
                    ((i++)) # Skip the next argument
                else
                    echo "❌ Error: Missing value for -L flag."
                    return 1
                fi
                ;;
            -f)
                # Enable second column file
                enable_col2_file="true"
                ;;
            -l)
                # Enable second column ln
                enable_col2_ln="true"
                ;;
                        
            -d)
                # Enable second column
                enable_col2_folder="true"
                ;;
            *)
                # Ignore unknown arguments
                ;;
        esac
    done

    # Output parsed values
    echo "$max_depth"
    echo "$enable_col2_ln"
    echo "$enable_col2_folder"
    echo "$enable_col2_file"
}

# tree_ln com limite de profundidade
tree_ln() {
    local path="${1:-.}"
    shift

    # Parse arguments
    local parsed_args=$(parse_args "$@")
    if [[ $? -ne 0 ]]; then
        exit 1
    fi

    # Extract parsed values
    local max_depth=$(echo "$parsed_args" | sed -n '1p')            # First line: max_depth
    local enable_col2_ln=$(echo "$parsed_args" | sed -n '2p')       # Second line: enable_col2_ln
    local enable_col2_folder=$(echo "$parsed_args" | sed -n '3p')    # Second line: enable_col2_folder
    local enable_col2_file=$(echo "$parsed_args" | sed -n '4p')     # Second line: enable_col2_file

    echo "Parsed arguments:" 
    echo "  Max Depth: $max_depth"
    echo "  Enable Col2: $enable_col2_file"

    # Remove trailing slash if present
    path="${path%/}"
    
    if [[ ! -d "$path" ]]; then
        echo "❌ Error: '$path' is not a valid directory."
        return 1
    fi
    
    declare -A _visited_ln
   
    _recursive_ln() {
        local P="$1"
        local level="$2"
        local indent="$3"
        
        # Check max depth
        if [[ $level -gt $max_depth ]]; then
            echo "${indent}  ⏸️  (depth limit $max_depth reached)"
            return
        fi
        
        local real_path=$(readlink -f "$P" 2>/dev/null || echo "$P")
        
        if [[ -n "${_visited_ln[$real_path]}" ]]; then
            echo "${indent}  🔄 (already visited)"
            return
        fi
        
        _visited_ln["$real_path"]=1
        
        for item in "$P"/*; do
            [[ ! -e "$item" ]] && continue
                        
            local name=$(basename "$item")
            local rel_path=$(realpath --relative-to="$PWD" "$item" 2>/dev/null || echo "$item")            
              if [[ -L "$item" ]]; then
                local target=$(readlink -f "$item" 2>/dev/null)                
                if [ $enable_col2_folder == true ]; then
                    TREE_C1_RATIO=3 tree_item_output "$indent" "🔗 $name" "$rel_path → $target"                    
                else
                    TREE_C1_RATIO=3 tree_item_output "$indent" "🔗 $name" "$rel_path → $target"
                fi                                
                
                if [[ -d "$target" ]]; then
                    _recursive_ln "$target" $((level + 1)) "$indent  "
                fi
            elif [[ -d "$item" ]]; then                
                if [ $enable_col2_folder == true ]; then
                    TREE_C1_RATIO=3 tree_item_output "$indent" "📂 $name/" "$rel_path"
                else
                    TREE_C1_RATIO=3 tree_item_output "$indent" "📂 $name/"
                fi                                
                _recursive_ln "$item" $((level + 1)) "$indent  "
            else                
                if [ $enable_col2_file == true ]; then
                    TREE_C1_RATIO=3 tree_item_output "$indent" "📄 $name" "$rel_path"
                else
                    TREE_C1_RATIO=3 tree_item_output "$indent" "📄 $name" 
                fi
                #echo "${indent}  📄 $name ${padding}[$rel_path]"
            fi
        done
    }
    echo ""
    echo "🌲 tree_ln: $path (max depth: $max_depth)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📦 $(basename $(realpath "$path"))/ "
    _recursive_ln "$path" 1 "  "
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}


# Helper function to format output with fixed alignment
tree_item_output() {
    # Get terminal width dynamically
    local terminal_width=$(tput cols)
    TREE_C1_RATIO=${TREE_C1_RATIO:-3}
    local div_screen=$((terminal_width / TREE_C1_RATIO))
    unset TREE_C1_RATIO

    # Input parameters
    local C1_indent="$1"         # Indentation string
    local C1_name="$2"          # Name of the item (with icon)
    local C2_rel_path="$3"      # Relative path (optional)

    # Combine ${C1_indent} and ${C1_name}
    local C1_value="${C1_indent}${C1_name}"

    # Truncate C1_value if it exceeds half the screen width
    if [[ ${#C1_value} -gt $div_screen ]]; then
        C1_value="${C1_value:0:$((div_screen - 3))}..."
    fi

    # Print output with or without the second column
    if [[ -n "${C2_rel_path}" ]]; then
        local padding_length=$((div_screen - ${#C1_value}))
        printf "%s%*s[%s]\n" "$C1_value" "$padding_length" "" "$C2_rel_path"
    else
        printf "%s\n" "$C1_value"
    fi
}
# Convenience aliases
alias tl='tree_ln'
alias tlwp='tl ~/workspace/PLAN -L 3 -f'
alias tlcp='tl ~/.config/containers/systemd -L 3 -f'
alias tlcs='tl ~/.config/systemd/user -L 3 -f'
