#!/bin/bash
# ../devops/bash_tool_sensor.sh

set +e

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ This is a library and should be sourced, not run directly."  >&2
    return 1
fi


#!/bin/bash
# Versão corrigida - combina jo com jq para escapar argumentos
core__tool_() {
    local tool="${1}"
    shift
    local arguments=("$@")
    
    # Escapa argumentos corretamente usando jq
    local args_json=$(printf '%s\n' "${arguments[@]}" | jq -R . | jq -s .)
    echo  $args_json | jq .

    # Sistema context
    local system_context=$(jo \
        hostname="$(hostname 2>/dev/null || echo 'unknown')" \
        os="$(uname -o 2>/dev/null || uname -s 2>/dev/null || echo 'unknown')" \
        kernel="$(uname -r 2>/dev/null || echo 'unknown')" \
        shell="$(basename "${SHELL}" 2>/dev/null || echo 'unknown')" \
        pid="$$" \
        parent_pid="${PPID}" \
        timestamp="$(date -Iseconds 2>/dev/null || date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)" \
        cwd="$(pwd 2>/dev/null || echo 'unknown')" \
        user="${USER:-$(whoami 2>/dev/null || echo 'unknown')}"
    )
    
    # Tool context - args já vem escapado pelo jq
    local tool_context=$(jo \
        cmd="${tool}" \
        args="$args_json" \
        function="${FUNCNAME[0]}" \
        script="${BASH_SOURCE[0]}" \
        line="${BASH_LINENO[0]}"
    )
    
    # Executa comando
    local stdout_file=$(mktemp)
    local stderr_file=$(mktemp)
    
    if [[ ${#arguments[@]} -eq 0 ]]; then
        "${tool}" > "$stdout_file" 2> "$stderr_file"
    else
        "${tool}" "${arguments[@]}" > "$stdout_file" 2> "$stderr_file"
    fi
    local exit_code=$?
    
    local stdout=$(cat "$stdout_file" 2>/dev/null)
    local stderr=$(cat "$stderr_file" 2>/dev/null)
    
    rm -f "$stdout_file" "$stderr_file"
    
    # Output com jo e jq combinados
    if [[ $exit_code -eq 0 ]]; then
        jo \
            status="success" \
            exit_code=0 \
            stdout="$(echo "$stdout" | jq -Rs .)" \
            tool="$tool_context" \
            system="$system_context"
    else

        echo "$stdout" | jq -Rs .
        echo "$stderr" | jq -Rs .

        jo \
            status="error" \
            exit_code="$exit_code" \
            cmd="$tool" \
            args="$args_json" \
            stdout="$(echo "$stdout" | jq -Rs .)" \
            stderr="$(echo "$stderr" | jq -Rs .)" \
            tool="$tool_context" \
            system="$system_context" \
            diagnosis=$(jo \
                cmd_exists=$(command -v "$tool" >/dev/null 2>&1 && echo "true" || echo "false") \
                cmd_path="$(command -v "$tool" 2>/dev/null || echo 'not found')" \
                shell_context="${BASH_SUBSHELL:-0}"
            )
    fi
}

core__tool_() {
    local tool="${1}"
    shift
    local arguments=("$@")
    
    # Escapa argumentos
    local args_json=$(printf '%s\n' "${arguments[@]}" | jq -R . | jq -s .)
    
    # System context - usando apenas jq
    local system_context=$(jq -n \
        --arg hostname "$(hostname 2>/dev/null || echo 'unknown')" \
        --arg os "$(uname -o 2>/dev/null || uname -s 2>/dev/null || echo 'unknown')" \
        --arg kernel "$(uname -r 2>/dev/null || echo 'unknown')" \
        --arg shell "$(basename "${SHELL}" 2>/dev/null || echo 'unknown')" \
        --arg pid "$$" \
        --arg parent_pid "$PPID" \
        --arg timestamp "$(date -Iseconds 2>/dev/null || date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)" \
        --arg cwd "$(pwd 2>/dev/null || echo 'unknown')" \
        --arg user "${USER:-$(whoami 2>/dev/null || echo 'unknown')}" \
        '{hostname: $hostname, os: $os, kernel: $kernel, shell: $shell, pid: ($pid|tonumber), parent_pid: ($parent_pid|tonumber), timestamp: $timestamp, cwd: $cwd, user: $user}'
    )
    
    # Executa comando
    local stdout_file=$(mktemp)
    local stderr_file=$(mktemp)
    
    if [[ ${#arguments[@]} -eq 0 ]]; then
        "${tool}" > "$stdout_file" 2> "$stderr_file"
    else
        "${tool}" "${arguments[@]}" > "$stdout_file" 2> "$stderr_file"
    fi
    local exit_code=$?
    
    local stdout=$(cat "$stdout_file" 2>/dev/null)
    local stderr=$(cat "$stderr_file" 2>/dev/null)
    
    rm -f "$stdout_file" "$stderr_file"
    
    # Output com jo (agora sem argumentos problemáticos)
    if [[ $exit_code -eq 0 ]]; then
        jo \
            status="success" \
            exit_code=0 \
            stdout="$(echo "$stdout" | jq -Rs .)" \
            tool="$(jo cmd="$tool" args="$args_json" function="${FUNCNAME[0]}" script="${BASH_SOURCE[0]}" line="${BASH_LINENO[0]}")" \
            system="$system_context"
    else
        jo \
            status="error" \
            exit_code="$exit_code" \
            cmd="$tool" \
            args="$args_json" \
            stdout="$(echo "$stdout" | jq -Rs .)" \
            stderr="$(echo "$stderr" | jq -Rs .)" \
            tool="$(jo cmd="$tool" args="$args_json" function="${FUNCNAME[0]}" script="${BASH_SOURCE[0]}" line="${BASH_LINENO[0]}")" \
            system="$system_context"
            return 1
            ### dispen
            diagnosis=$(jo \
                cmd_exists=$(command -v "$tool" >/dev/null 2>&1 && echo "true" || echo "false") \
                cmd_path="$(command -v "$tool" 2>/dev/null || echo 'not found')" \
                shell_context="${BASH_SUBSHELL:-0}")
    fi
}


# Debug
core__tool_debug() {
    echo "DEBUG: Executing: $*" >&2
    core__tool_ "$@"
}

core__tool_try() {
    local result
    result=$(core__tool_ "$@")
    if echo "$result" | jq -e '.status == "error"' >/dev/null 2>&1; then
        return 1
    fi
    echo "$result" | jq -r '.stdout'
}

core__tool_is_error() {
    local result="$1"
    echo "$result" | jq -e '.status == "error"' >/dev/null 2>&1
}

# Helper functions
core__tool_data() {
    local response="$1"
    if echo "$response" | jq -e '.status == "success"' >/dev/null 2>&1; then
        if echo "$response" | jq -e '.stdout' >/dev/null 2>&1; then
            echo "$response" | jq -r '.stdout'
        else
            echo "$response"
        fi
    else
        return 1
    fi
}


core__tool_is_success() {
    local response="$1"
    echo "$response" | jq -e '.status == "success"' >/dev/null 2>&1
}


test__trail_tool(){
    output=$(core__tool_require "cat" "/etc/passwd")
    output=$(core__tool_try "ls" "/maybe/missing") || echo "File not found"
}


test__core__tool_ls1() {
    # Run a successful command
    result=$(core__tool_ "ls" "-la" "/tmp")
    if core__tool_is_error "$result"; then
        echo "Error occurred:"
        echo "$result" | jq '.stderr'
    else
        data=$(core__tool_data "$result")
        echo "Success: $data"
    fi
}
test__core__tool_ls2() {
    # Run a failing command
    result=$(core__tool_ "ls" "/nonexistent")
    if core__tool_is_error "$result"; then
        echo "Command failed:"
        echo "$result" | jq -r '.stderr'
        echo "Exit code: $(echo "$result" | jq -r '.exit_code')"
    fi
}
test__core__tool_grep1() {
    # Run with custom tool
    result=$(core__tool_ "grep" "-r" "pattern" "/some/path")

    # Chain operations
    if core__tool_is_success "$(core__tool_ "test" "-f" "/etc/passwd")"; then
        echo "File exists"
    fi
}
test__core__tool_stat1() {
    # Capture and process
    response=$(core__tool_ "stat" "--format=%U" "/etc/passwd")
    if ! core__tool_is_error "$response"; then
        owner=$(core__tool_data "$response")
        echo "Owner: $owner"
    fi   
}

core__tool_debug() {
    local tool="${1}"
    shift
    local arguments=("$@")
    
    echo "DEBUG: Executing: $tool ${arguments[*]}" >&2
    core__tool_ "$tool" "${arguments[@]}"
}
