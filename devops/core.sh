#!/bin/bash
# ../devops/core.sh

set +e

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ This is a library and should be sourced, not run directly."  >&2
    return 1
fi

export DEVOPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DEVOPS_DIR_NAME=$(basename $DEVOPS_DIR)
export DEVOPS_CORE_SCRIPT=$(basename ${BASH_SOURCE[0]})
export DEVOPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DEVOPS_ENV_FILE="$DEVOPS_DIR/.env"


echo "$DEVOPS_DIR_NAME:" >&2
echo " - DEVOPS_DIR: $DEVOPS_DIR" >&2
echo " - DEVOPS_CORE_SCRIPT: $DEVOPS_CORE_SCRIPT" >&2
echo "pwd: $(pwd)" >&2


# --- HELPERS ---
# require_vars for console cleaner results. only display missings

# will trace from require_* functions to source
export TRACE_STEPS=10
export REQ_STATUS_OK="OK   "
export REQ_STATUS_UNDEFINED="UNDEF"
export REQ_STATUS_NOT_FIL="!FIL "
export REQ_STATUS_NOT_DIR="!DIR "
export REQ_STATUS_EMPTY="EMPTY"
export REQ_STATUS_MISS="MISS "
export REQ_STATUS_STOP="STOP "
export REQ_STATUS_FAIL="FAIL "
export REQ_STATUS_ERROR="ERROR "

require_vars() {
    local _type="var" 
    local vars=("$@")
    local missing=()
    for var in "${vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing+=("$var")          
            debug_required_type_name "$_type" "$var" "$REQ_STATUS_UNDEFINED"             
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        # Joins the array with commas and prints one line
        #echo "❌ missing required vars: $(IFS=,; echo "${missing[*]}")" >&2
        return 1
    fi

    return 0
}
export -f require_vars
show_vars() {
    local vars=("$@")
    local missing=()
    local count=0

    [[ $DEBUG == "true" ]] && echo "--- [ Debug: Variáveis de Lançamento ] ---" >&2
    for var in "${vars[@]}"; do
        # Expansão indireta: vai buscar o valor do nome contido em $var
        local value="${!var}"
        
        if [ -z "$value" ]; then
            echo "❌ $var = [VAZIA / MISSING]" >&2
            missing+=("$var")
        else
            echo "$var=\"$value\"" >&2
            ((count++))
        fi
    done
    [[ $DEBUG == "true" ]] && echo "------------------------------------------" >&2

    # Se houver variáveis em falta, avisa o utilizador e interrompe
    if [ ${#missing[@]} -ne 0 ]; then
    #    echo "🚨 ERRO CRÍTICO: As seguintes variáveis não estão definidas:" >&2
        return 1 # Indica falha
    fi

    return 0 # Tudo OK
}
require_binaries() {
    local _type="binary"
    
    for b in "$@"; do        
        if command -v "$b" >/dev/null 2>&1; then
            # Optional: Log success if you want a verbose trace
            # debug_required_var "$b" "OK"
            continue
        else
            # Error Case
            #echo -e "\e[31m❌ Error:\e[0m Binary '$b' is not installed." >&2            
            # Using a descriptive status
            debug_required_type_name "$_type" "$b" "$REQ_STATUS_MISS"
            return 1
        fi
    done
}
export -f require_binaries
require_devops_assets() {
    require_vars DEVOPS_DIR || return 1
    local curr_dir=$(pwd)
    local _type="$1"
    shift
    local ret=0
    
    # Check if we are in the right place
    if [[ "$curr_dir" != "$DEVOPS_DIR"* ]]; then
        echo -e "\e[31m❌ [Error] Current directory is not inside DEVOPS_DIR\e[0m" >&2
        return 1
    fi

    local __asset_names=("$@") 
    for item in "${__asset_names[@]}"; do
        local path_val _name infer_nature="UNK " 
        local _status=$REQ_STATUS_OK  # Default to OK
        local owner_info="n/a"
        local rel_path

        # 1. Resolve Variable or Literal
        if [[ -n "${!item+x}" ]]; then
            path_val="${!item}"; _name="$item"
        else
            path_val="$item"; _name="Literal"
        fi

        # 2. Status and Nature Check
        if [[ -z "$path_val" ]]; then
            _status=$REQ_STATUS_EMPTY; ret=1
            rel_path="n/a"
        elif [[ ! -e "$path_val" ]]; then
            _status=$REQ_STATUS_MISS; ret=1
            rel_path="$path_val"
        else
            # Determine nature (SYML, DIR, EXEC, KDBX, etc.)
            if [[ -L "$path_val" ]]; then infer_nature="SYML"
            elif [[ -d "$path_val" ]]; then infer_nature="DIR "
            elif [[ -f "$path_val" ]]; then
                if [[ -x "$path_val" ]]; then infer_nature="EXEC"
                elif [[ "$path_val" == *.kdbx ]]; then infer_nature="KDBX"
                elif [[ "$path_val" == *.yml || "$path_val" == *.yaml ]]; then infer_nature="CONF"
                elif [[ "$path_val" == *.env* ]]; then infer_nature="ENVS"
                else infer_nature="FILE"; fi
            fi

            # Type Validation
            if [[ "$_type" == "file" && ! -f "$path_val" ]]; then
                _status="$REQ_STATUS_NOT_FIL"; ret=1
            elif [[ "$_type" == "folder" && ! -d "$path_val" ]]; then
                _status="$REQ_STATUS_NOT_DIR"; ret=1
            fi

            rel_path=$(realpath --relative-to="$curr_dir" "$path_val" 2>/dev/null || echo "$path_val")
            owner_info=$(stat -c "%U:%G %a" "$path_val" 2>/dev/null || echo "n/a")
        fi        

        # 3. Trigger Trace only on failure
        if [[ "$_status" != "$REQ_STATUS_OK" ]]; then
            # We call the debugger directly
            debug_required_type_name "$_type" "$_name" "$_status"
            continue
        fi

        # Output terminal line    
        #echo -e "✅ $_type $_name [./$rel_path] [$owner_info] | [$infer_nature"] >&2     
    done

    return $ret
}
stack_trace() {
    [[ $DEBUG != "true" ]] && return 0
    echo "--- Stack Trace ---"
    for i in "${!FUNCNAME[@]}"; do
        stack_trace_idx $i
    done
}
stack_trace_idx() {
    [[ $DEBUG != "true" ]] && return 0
    local idx=$1
    local max_idx=$((${#FUNCNAME[@]} - 1))

    # 1. Validate Input (Is it a number?)
    if [[ ! "$idx" =~ ^[0-9]+$ ]]; then
        echo "[Error]: Index '$idx' is not a valid non-negative integer."
        return 1
    fi

    # 2. Validate Boundaries (Is it within the stack?)
    if (( idx > max_idx )); then
        echo "[Error]: Stack depth is only $max_idx. Index $idx is out of bounds."
        return 1
    fi

    # 3. Extract metadata
    local func="${FUNCNAME[$idx]}"
    local source="${BASH_SOURCE[$idx]}"
    
    # Logic: BASH_LINENO[idx] is where FUNCNAME[idx] was CALLED from.
    # To see where we ARE at level $idx, we look at the 'current' line of that level.
    local line="${BASH_LINENO[$idx-1]}"

    # Formatting the output
    echo "Level [$idx]: ${func}() call ${source}:${line:-top_level}"
}
core_relative_path2() {
    local the_file="$1"
    # Se o ficheiro não existir ou realpath falhar, mantém o original
    realpath --relative-to="$PWD" "$the_file" 2>/dev/null || echo "$the_file"
}

## usage file line case: corelink_file "envfile" "./env" 4
## usage file search lines case: corelink_file "envfile" "./env" debug_link_file
debug_link_file() {
    local link_name="$1"
    local file_path="$2"
    shift 2 # Remove link_name e file_path dos argumentos
    
    # Validação de requisitos (assumindo que require_vars existe no teu env)
    require_vars link_name file_path || return 1

    _search_file_lines() {
        local file_path="$1"
        local pattern="$2"
        
        if [[ ! -f "$file_path" ]]; then return 1; fi
        if [[ -z "$pattern" ]]; then return 1; fi
        local matching_lines
        matching_lines=$(grep -n "$pattern" "$file_path" | cut -d: -f1)
        echo $matching_lines
    }

    local first_arg="$1"
    local rel_path=$(core_relative_path2 $file_path)
    
    # 1. Caso: Argumento é Numérico (Linha fixa)
    if [[ "$first_arg" =~ ^[0-9]+$ ]]; then
        local line="$first_arg"
        printf "  - \e[1;32m%-30s\e[0m -> \e[1;34m%s\e[0m\n" \
            "${link_name}" "$rel_path:$line"    
            
    # 2. Caso: Argumento é Padrão de Busca
    elif [[ -x first_arg ]]; then
        local search_pattern="$first_arg"


        # Supõe que _search_file_lines devolve uma lista de números de linha
        # Exemplo interno: local lines=($(grep -n "$search_pattern" "$file_path" | cut -d: -f1))
        local lines=($(_search_file_lines  "$file_path" "$search_pattern" ))
        
        printf "  - \e[1;32m%-20s\e[0m search [pattern: %s])-> \e[1;34m%s\e[0m \n" \
            "${link_name}" "$search_pattern"  "$file_path"     

        for line in "${lines[@]}"; do
            printf "    -> \e[1;34m%s:%s\e[0m\n" \
                "$file_path" "$line"   
        done
    else
        printf "  - \e[1;32m%-20s\e[0m -> \e[1;34m%s\e[0m \n" \
            "${link_name}" "$file_path"     
    fi
}

debug_required_type_name() {
    local _type="$1"
    local _name="$2"
    local _status="$3"
    local step=${4:-1}
    
    [[ $DEBUG != "true" ]] && {
        #[[ $DEBUG != "false" ]] &&  
        echo "$_type $_name $_status"
        return 0        
    }

    _map_function__file_line() {
        local func_name=$1
        # Ativa debug estendido localmente para obter linha e arquivo
        shopt -s extdebug
        local info
        info=$(declare -F "$func_name")
        shopt -u extdebug

        if [[ -n "$info" ]]; then
            # O output de declare -F com extdebug é: "nome_funcao linha arquivo"
            local line_no
            local file_path
            read -r _ line_no file_path <<< "$info"
            
            local rel_path
            rel_path=$(core_relative_path2 "$file_path")
            
            echo "function:\"$func_name\" [${rel_path}:${line_no}]"
        else
            echo "function:\"$func_name\" [NOT FOUND]" >&2
            return 1
        fi
    }
    # 1. Mapeamento Visual (Status e Cores)
    _map_type_name__status() {        
        local _type="$1"
        local _name="$2"
        local _status="$3"


        # Definição de Cores ANSI (Bold para melhor leitura)
        local R="\e[1;31m" # Red
        local Y="\e[1;33m" # Yellow
        local C="\e[1;36m" # Cyan
        local G="\e[1;32m" # Green
        local B="\e[1;34m" # Blue
        local N="\e[0m"    # Reset

        _map_type_name__value() {
            local _type="$1"
            local _name="$2"
            
            # Validação interna simples para evitar recursividade com require_vars
            if [[ -z "$_type" || -z "$_name" ]]; then
                echo "error:\"_map_type_name__value\" [missing arguments]" >&2
                return 1
            fi

            # Indireção segura: busca o valor da variável cujo nome está em _name    
            local _more=""

            case "$_type" in
                file|folder|device|location)
                    local _value="${!_name:-}"
                    # Encurta caminhos para facilitar a leitura no terminal
                    local rel_path
                    rel_path=$(core_relative_path2 "$_value")
                    _more=" [${rel_path}]"
                    ;;
                var|env)
                    # Mostra o valor real (cuidado com variáveis gigantes aqui)
                    local _value="${!_name:-}"
                    _more="=${_value}"
                    ;;
                ns_resolve)
                    # Mostra o valor real (cuidado com variáveis gigantes aqui)
                    _more="" ### the _name is the value
                    ;;
                secret|keepass|mem|token|pass)
                    # Mascaramento de dados sensíveis
                    _more="=********"
                    ;;
                function)
                    local origin
                    origin=$(_map_function__file_line "$_name")
                    _more=" [origin: ${origin#*\" }] " # Extrai apenas o [arquivo:linha]
                    ;;
                *)
                    # Fallback amigável para tipos não mapeados
                    _more=" [type:$_type]"
                    local _value="${!_name:-}"
                    _more=" [${_value}]"
                    ;;
            esac

            # printf é mais robusto que echo para strings com caracteres especiais
            printf '%s:"%s"%s\n' "$_type" "$_name" "$_more"
        }

        # CORREÇÃO: Usar $_type (com underscore)
        local _type_name_rep
        _type_name_rep=$(_map_type_name__value "$_type" "$_name")

        local _msg=""
        case "$_status" in
            "$REQ_STATUS_MISS")    
                _msg="${R}❌ ${_type_name_rep}${N} [${Y}${_status}${N}]" ;;
            
            "$REQ_STATUS_EMPTY")   
                _msg="${Y}⚠️ ${_type_name_rep}${N} [${Y}${_status}${N}]" ;;
            
            "$REQ_STATUS_NOT_FILL") 
                _msg="${R}🚫 ${_type_name_rep}${N} [${Y}${_status}${N}]" ;;
            
            "$REQ_STATUS_NOT_DIR")  
                _msg="${R}📂 ${_type_name_rep}${N} [${Y}${_status}${N}]" ;;
            
            "$REQ_STATUS_STOP")    
                _msg="${C}🛑 ${_type_name_rep}${N} [${Y}${_status}${N}]" ;;
            
            "$REQ_STATUS_UNDEFINED") 
                _msg="${Y}❓ ${_type_name_rep}${N} [${Y}${_status}${N}]" ;;
            
            "$REQ_STATUS_OK")       
                _msg="${G}✅  ${_type_name_rep}${N} [${G}${_status}${N}]" ;;

            *)                     
                _msg="${B}ℹ️  ${_type_name_rep}${N} [${Y}${_status}${N}]" ;;
        esac

        # Imprime com quebra de linha no stderr
        echo -e "$_msg" >&2
    }
    _map_type_name__status "$_type" "$_name" "$_status"

    # 2. Stack Trace Dinâmico com Offset
    if [[ "${TRACE_STEPS:-0}" -gt 0 ]]; then
        echo -e "\e[1;30m   [ Stack Trace (Depth: $TRACE_STEPS) ]\e[0m" >&2
        
        for (( i=1; i <= TRACE_STEPS; i++ )); do
            local func="${FUNCNAME[$i]}"
            local file="${BASH_SOURCE[$i]}"
            
            local call_line="${BASH_LINENO[$((i-1))]}"
                        
            [[ -z "$func" ]] && break
            
            # --- Lógica de Offset ---
            # Se não for o 'main', tentamos descobrir onde a função começa
            local display_line="$call_line"
            if [[ "$func" != "main" ]]; then
                local start_line
                # Ativamos extdebug apenas para este comando
                # local efect is some how new to me. !emportant
                
                shopt -s extdebug
                local func_info
                func_info=$(declare -F "$func")
                shopt -u extdebug
                start_line=$(echo "$func_info" | awk '{print $2}')

                #local real_file="$(realpath ${file})"
                #local funcs=$(core_fn_json "$real_file" "$func" 2> /dev/null | jq .)
                #show_vars file real_file call_line funcs || return 1
                #start_line=$(echo "$funcs" | jq -r '.[] | .line')

                # Se a linha de chamada é 1, significa que é relativa ao ficheiro/função
                # Calculamos a linha absoluta: Início da função + (linha interna - 1)
                if [[ "$call_line" -eq 1 ]]; then
                     display_line=$((start_line))
                fi
            fi

            local rel_path
            rel_path=$(core_relative_path2 "$file")
            
            local prefix="      "
            [[ $i -eq $step ]] && prefix="  \e[1;33m->\e[0m "

            printf "%b Level [%d]: %-20s \e[1;34m%s:%s\e[0m\n" \
                "$prefix" "$i" "${func}()" "$rel_path" "$display_line" >&2
        done
    fi
    echo "" >&2
}
# Wrappers para facilitar o uso:
require_files()     { require_devops_assets "file" "$@"; }
require_locations() { require_devops_assets "folder" "$@"; }
require_devices()   { require_devops_assets "device" "$@"; }

require_functions() {    
    local _type="function" 
    local missing=0    
    for f in "$@"; do
        if ! declare -F "$f" >/dev/null; then            
            #echo "❌ Error: Required function '$f' is not defined." >&2
            debug_required_type_name "$_type" "$f" "$REQ_STATUS_UNDEFINED"
            missing=1
            continue
        fi
        
        #debug_required_function "$f" $REQ_STATUS_OK
    done

    if [ $missing -ne 0 ]; then
        echo "🛑 Missing Script function dependencies." >&2
        return 1
    fi
    return 0
}
export -f require_functions

require_single_script_function() {
    local ref=${1}
    local _client_script=${!ref}
    local func="$2"
    
    # Validação silenciosa do script, mas erro ruidoso se falhar
    [[ -z "$_client_script" ]] && { echo "❌ Erro: Referência $_client_script vazia." >&2; return 1; }
  
    local func_json
    # Captura o objeto JSON da função específica
    func_json=$(core_fn_json "$_client_script" "$func" 2> /dev/null | \
                jq -r --arg f "$func" '.[] | select(.function == $f)')

    if [[ -z "$func_json" ]]; then
        # Output de Erro alinhado
        printf "  \e[1;31m󰅙󰅙\e[0m Missing: \e[1;33m%-30s\e[0m \e[1;30m-> [%s]\e[0m\n" "$func" "$(core_relative_path2 $_client_script)" >&2
        return 1
    else
        # Extração de dados puros do JSON
        local f_line=$(echo "$func_json" | jq -r '.line')
        local f_path=$(echo "$func_json" | jq -r '.script')
        
        # Output de Sucesso com colunas fixas e link clicável
        # %-30s garante que o nome da função ocupe sempre 30 espaços, alinhando as setas
        LABEL=${LABEL:-"✅\e[0m Found:  "}
        printf "  \e[1;32m${LABEL} \e[1;34m%-30s\e[0m \e[1;90m->\e[0m \e[4;36m%s:%s\e[0m\n" "${func}()" "$f_path" "$f_line" >&2
        return 0
    fi
}

#### nvidia
nvidia_egl_json_file() {
    local paths=(
        "/usr/share/glvnd/egl_vendor.d/10_nvidia.json"
        "/etc/glvnd/egl_vendor.d/10_nvidia.json"
    )
    for p in "${paths[@]}"; do
        [ -f "$p" ] && echo "$p" && return 0
    done
    return 1
}
# valida mountpoint -q "/mnt/ssd980"
check_main_mount() {
    if ! mountpoint -q "/mnt/ssd980"; then
        echo "ERROR: SSD 980 não está montado em /mnt/ssd980"
        exit 1
    fi
}
export -f check_main_mount

# Usage in your flow:
# echo "Provider backup-provider updated" | color -w "backup-provider" -c green


require_container_running() {
    local _type="container"
    local -a missing_list=() # Array para nomes dos containers que falharam

    # Função interna para checar estado via Docker Inspect
    require_single_container_running() {
        local _name="$1"      
        local _state="$2"  
        
        local status
        status=$(docker inspect -f "{{.State.$_state}}" "$_name" 2>/dev/null)
        local exit_code=$?
        
        [[ $exit_code -ne 0 ]] && {           
            return 2 # MISS (Não existe)
        }
        [[ "$status" == "true" ]] && return 0 # OK
        return 1 # STOP (Existe mas não está no estado)
    }

    for _var_name_ in "$@"; do
        # Pega o valor da variável (ex: se passar 'IMMICH_SERVER', pega 'immich-server')
        local container_name=${!_var_name_}
        
        require_single_container_running "$container_name" "Running"
        local res=$?

        if [[ $res -eq 2 ]]; then
            missing_list+=("$container_name") 
            debug_required_type_name "$_type" "$container_name" "$REQ_STATUS_MISS"
        elif [[ $res -eq 1 ]]; then
            missing_list+=("$container_name")  
            debug_required_type_name "$_type" "$container_name" "$REQ_STATUS_STOP"
        fi
    done

    # Verifica se o array tem elementos
    if [[ ${#missing_list[@]} -gt 0 ]]; then
        echo -e "\n🛑 Error: ${#missing_list[@]} ${_type}(s) are not running." >&2
        return 1
    fi
    return 0
}
export -f require_container_running



# nslookup host name, logic return 1 if dns resolve it else 0
require_ns_resolve() {
    local _type="ns_resolve"
    local -a missing=()   # Declarar explicitamente como array
    local _target_ip="${TARGET_IP:-}" 

    require_ns_single_lookup_resolve() {
        local _host="$1"
        local _ip="$2"
        local ns_output
        require_vars _host
        # 1. Tenta resolver o host (com timeout de 3s)
        ns_output=$(timeout 3 nslookup "$_host" 2>&1)
        local exit_code=$?

        # 2. Verifica falha de resolução (NXDOMAIN, etc)
        if [[ $exit_code -ne 0 ]] || echo "$ns_output" | grep -iqE "NXDOMAIN|can't find|servfail"; then
            return 1 
        fi

        # 3. Verifica IP específico (usando \b para garantir match exato do IP)
        if [[ -n "$_ip" ]]; then
            if ! echo "$ns_output" | grep -qE "\b${_ip}\b"; then
                echo "⚠️  DNS Mismatch: $_host resolved, but not to $_ip" >&2
                return 1
            fi
        fi

        return 0
    }
    for f in "$@"; do
        local ns_value="${!f}"
        
        if ! require_ns_single_lookup_resolve "$ns_value" "$_target_ip"; then            
            debug_required_type_name "$_type" $ns_value "$REQ_STATUS_ERROR"   
            return 1      
            missing+=("$ns_value")  
        fi
    done

    # CORREÇÃO AQUI: Verifica o TAMANHO do array
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "🛑 DNS Resolution Failed for: ${missing[*]}" >&2
        return 1
    fi
    
    return 0
}

core_resolve_file() {
    require_vars DEVOPS_DIR DEVOPS_DIR_NAME DEVOPS_CORE_SCRIPT
    
    local default_file="$DEVOPS_DIR/$DEVOPS_CORE_SCRIPT"
    local _input_file="${1:-$default_file}"

    # 1. TRATAMENTO DE SEGURANÇA: Corta tudo à esquerda inclusive o último ../
    if [[ "$_input_file" == *"../"* ]]; then
        echo "⚠️ [CLEANUP] Stripping relational path (../) from input..." >&2
        
        # Isto funciona como o .split('../').pop() do NodeJS:
        # O operador ##*../ remove a maior correspondência possível que termine em ../ vinda da esquerda.
        _input_file="${_input_file##*../}"
        
        echo "   Cleaned to: $_input_file" >&2
    fi

    # 2. LIMPEZA DE ./ (Null Relation Path)
    # Removemos o prefixo ./ se existir, ou extraímos o que vem depois de /./
    local _devops_file="$_input_file"
    _devops_file="${_devops_file#./}"    # Limpa ./ no início
    _devops_file="${_devops_file##*/./}" # Limpa /./ no meio da string

    # 3. Prevenção de duplicação do DEVOPS_DIR
    _devops_file="${_devops_file#$DEVOPS_DIR/}"

    local _found_path=""

    # --- Lógica de busca (Mantida a tua estrutura original) ---
    if [[ -f "$DEVOPS_DIR/$_devops_file" ]]; then
        _found_path="$DEVOPS_DIR/$_devops_file"
    elif [[ -f "./$DEVOPS_DIR_NAME/$_devops_file" ]]; then
        _found_path="$(pwd)/$DEVOPS_DIR_NAME/$_devops_file"
    else
        local _search_path=$(realpath "$(pwd)/..")
        for i in {1..3}; do
            if [[ -f "$_search_path/$DEVOPS_DIR_NAME/$_devops_file" ]]; then
                _found_path="$_search_path/$DEVOPS_DIR_NAME/$_devops_file"
                break
            fi
            _search_path=$(realpath "$_search_path/..")
        done
    fi

    # 4. VALIDAÇÃO FINAL (Realpath)
    if [[ -n "$_found_path" ]]; then
        local _abs_found=$(realpath "$_found_path")
        local _abs_devops=$(realpath "$DEVOPS_DIR")

        if [[ "$_abs_found" == "$_abs_devops"* ]]; then
            echo "$_abs_found"
            return 0
        fi
    fi

    echo "❌ [ERROR] File $_devops_file not found in $DEVOPS_DIR" >&2
    return 1
}
export -f core_resolve_file
# from ../.env. 
# DOMAIN="home2500.local"
# PUBLIC_SERVICES_LIST="traefik vault auth whoami mailcrab pihole backup"
detect_active_interface() {
    # 1. Tenta usar a variável do .env, senão tenta detetar a interface da rota default
    local target_name="${NETWORK_INTERFACE}"
    
    # Se NETWORK_INTERFACE não estiver definida, procura a interface da rota padrão
    if [ -z "$target_name" ] || [ "$target_name" = "default" ]; then
        target_name=$(ip route | grep '^default' | awk '{print $5}' | head -n1)
    fi

    # 2. Valida se a interface existe e está "UP"
    if [ -n "$target_name" ] && ip link show "$target_name" >/dev/null 2>&1; then
        # Verifica se tem um IP atribuído (está realmente ativa)
        if ip addr show "$target_name" | grep -q "inet "; then
            echo "$target_name"
            return 0
        fi
    fi

    >&2 echo "❌ Interface '$target_name' not found or has no IPv4 address."
    return 1
}
detect_active_ipv4() {        
    # Chama a função original e captura o resultado (stdout)
    # Redirecionamos o stderr para /dev/null para evitar mensagens duplicadas se desejar
    local interface=$(detect_active_interface)
    
    # Verifica se a função anterior falhou
    if [ $? -ne 0 ] || [ -z "$interface" ]; then
        return 1
    fi

    # Extrai o IP da interface retornada
    local ip_address=$(ip -4 addr show "$interface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)

    if [ -z "$ip_address" ]; then
        >&2 echo "❌ No IPv4 address found for $interface"
        return 1
    fi

    echo "$ip_address"
}
detect_active_ipv6() {
    local interface=$(detect_active_interface)
    # Procuramos o endereço inet6 com escopo 'link' (local)
    local ip=$(ip -6 addr show "$interface" | grep "scope link" | awk '{print $2}' | cut -d'/' -f1 | head -n1)
    
    if [[ -z "$ip" ]]; then
        # Se não houver link-local, tentamos qualquer IPv6 global
        ip=$(ip -6 addr show "$interface" | grep "inet6" | grep -v "fe80" | awk '{print $2}' | cut -d'/' -f1 | head -n1)
    fi
    
    echo "$ip"
}

core_desired_domain_names_json() {
    local enable_ipv6="${ENABLE_IPV6:-false}"
    require_functions detect_active_ipv4 detect_active_ipv6

    local proxy_ipv4="$(detect_active_ipv4)"
    local proxy_ipv6="$(detect_active_ipv6)"
    
    require_vars proxy_ipv4 || return 1 # IPv4 é obrigatório
    
    jq -n \
        --arg names "$SORTED_DESIRED_NAMES" \
        --arg ipv4 "$proxy_ipv4" \
        --arg ipv6 "$proxy_ipv6" \
        --argjson use_v6 "$enable_ipv6" '
        $names 
        | split(",") 
        | map(select(length > 0)) 
        | map(
            {host: ., address: $ipv4},
            (select($use_v6 == true and ($ipv6 | length > 0)) | {host: ., address: $ipv6})
        )
    '
}
docker_container_network_json() {
    local container_name="${1:-whoami}"
    require_vars container_name
    local network_json=$(docker inspect -f '{{json .}}' "${container_name}" 2>/dev/null)
    if [[ -z "$network_json" || "$network_json" == "null" ]]; then
        echo "❌ Container '$container_name' not found or has no network settings." >&2
        return 1
    fi
    echo $network_json | jq 
}

docker_container_name_ip() {
    local container_name="$1"
    local network_name="${INTERNAL_DOMAIN:-app-network}" # Fallback para app-network se vazio
    
    DEBUG=false require_vars container_name network_name || return 1
    
    local _ip
    # Filtramos especificamente pela rede que nos interessa para evitar IPs colados (com timeout)
    _ip=$(timeout 3 docker inspect -f "{{with index .NetworkSettings.Networks \"$network_name\"}}{{.IPAddress}}{{end}}" "${container_name}" 2>/dev/null)
    
    local ipv4_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    
    if [[ -z "$_ip" || ! $_ip =~ $ipv4_regex ]]; then
        echo "⚠️  [NETWORK] IP inválido ou container '$container_name' não está na rede '$network_name': '${_ip:-EMPTY}'" >&2
        return 1
    fi    

    echo "$_ip"
}
# Versão para ver portas INTERNAS do container (mesmo sem mapeamento -p)

docker_container_name_ports() {
    local container_name="$1"
    local port_idx="$2" 
    
    # 1. Extração via Go Template (mais eficiente que múltiplos pipes)
    # Pegamos as chaves (portas) de NetworkSettings.Ports ou Config.ExposedPorts (com timeout)
    local raw_ports
    raw_ports=$(timeout 3 docker inspect -f '
        {{- $p := .NetworkSettings.Ports -}}
        {{- if not $p }}{{ $p = .Config.ExposedPorts }}{{ end -}}
        {{- range $k, $v := $p }}{{ $k }} {{ end -}}' "$container_name" 2>/dev/null)

    # 2. Limpeza com Bash puro (mais rápido que chamar sed/xargs)
    # Remove "/tcp" e "/udp" e normaliza espaços
    local clean_ports="${raw_ports//\/tcp/}"
    clean_ports="${clean_ports//\/udp/}"
    clean_ports=$(echo $clean_ports) # xargs-like trim

    if [[ -z "$clean_ports" ]]; then
        return 1
    fi

    # 3. Lógica de Retorno usando Array nativo
    local -a port_array=($clean_ports)
    
    # Se não houver índice, retorna a lista completa
    if [[ -z "$port_idx" ]]; then
        echo "${port_array[*]}"
    else
        # Verifica se o índice é válido
        if [[ $port_idx -ge ${#port_array[@]} ]]; then
            echo "⚠️  [NETWORK] Port index $port_idx out of bounds for $container_name (found ${#port_array[@]})" >&2
            return 1
        fi
        echo "${port_array[$port_idx]}"
    fi
}
docker_container_name_ip_port() {
    local container_name="$1"
    local target_port="$2"
    
    require_vars container_name

    # 1. Obter o IP
    local _ip
    _ip=$(docker_container_name_ip "$container_name")
    [[ $? -ne 0 ]] && return 1

    # 2. Lógica de Porto: Manual vs Auto-Discovery
    local _port
    if [[ -n "$target_port" ]]; then
        # Modo Manual (Override)
        _port="$target_port"
        echo "⚠️  [NETWORK] Usando porto forçado: $_port (para $container_name)" >&2
    else
        # Modo Auto-Discovery
        local _raw_port
        _raw_port=$(docker inspect -f '{{range $p, $conf := .NetworkSettings.Ports}}{{$p}}{{break}}{{end}}' "$container_name" 2>/dev/null)
        
        # Fallback para Config caso container parado
        if [[ -z "$_raw_port" ]]; then
            _raw_port=$(docker inspect -f '{{range $p, $conf := .Config.ExposedPorts}}{{$p}}{{break}}{{end}}' "$container_name" 2>/dev/null)
        fi
        
        _port="${_raw_port%%/*}"
    fi

    # 3. Validação final
    if [[ -z "$_port" || ! "$_port" =~ ^[0-9]+$ ]]; then
        echo "❌ [NETWORK] Nenhum porto válido detetado ou especificado para '$container_name'" >&2
        return 1
    fi

    echo "${_ip}:${_port}"
}
docker_container_name_ip_port() {
    local container_name="$1"
    local target_port="$2" # Opcional: Forçar porta ou índice
    
    require_vars container_name || return 1

    # 1. Obter o IP (Reutiliza lógica de validação/rede)
    local _ip
    _ip=$(docker_container_name_ip "$container_name") || return 1

    # 2. Obter a Porta
    local _port
    if [[ -n "$target_port" && "$target_port" =~ ^[0-9]+$ && "$target_port" -gt 10 ]]; then
        # Se for um número de porta válido (ex: 8080), usamos direto
        _port="$target_port"
    else
        # Caso contrário, usamos a auto-descoberta (índice 0 se target_port for vazio ou não-numérico)
        local idx="${target_port:-0}"
        # Garantir que se passarmos "0" ou nada, ele tenta a primeira porta disponível
        [[ ! "$idx" =~ ^[0-9]+$ ]] && idx=0
        
        _port=$(docker_container_name_ports "$container_name" "$idx")
        
        if [[ $? -ne 0 ]]; then
            echo "❌ [NETWORK] Falha na auto-descoberta de porta para '$container_name'" >&2
            return 1
        fi
    fi

    # 3. Retorno Formatado
    echo "${_ip}:${_port}"
}
docker_app_network_json() {
    require_vars "INTERNAL_DOMAIN"

    # 1. Get all running container IDs
    local containers=$(docker ps -q)
    [[ -z "$containers" ]] && { echo "[]"; return 0; }

    # 2. Inspect and transform directly to JSON objects
    docker inspect $containers | jq -r --arg int_dom "$INTERNAL_DOMAIN" '
        [
            .[] | 
            # Select only containers connected to the internal network
            select(.NetworkSettings.Networks[$int_dom] != null) | 
            {
                # Extract the IP and the Name (removing leading slash)
                address: .NetworkSettings.Networks[$int_dom].IPAddress,
                host: ((.Name | sub("^/"; "")) + "." + $int_dom)
            }
        ]
    '
}

require_service_redirect_auth() {
    local _type="https:oidc"
    local -a missing_list=()
    
    require_single_service_redirect_auth() {        
        require_vars "DOMAIN"    
        local _service="$1"
        local expected_auth_url="https://auth.${DOMAIN}"
        local service_url="https://${_service}.${DOMAIN}"
        
        # 1. Capturamos SEM seguir redirects (-L) para ver o primeiro hop
        local first_response
        first_response=$(curl -I -s -k -m 5 "$service_url" -w "%{http_code} %{redirect_url}" -o /dev/null)
        local exit_status=$?

        if [[ $exit_status -ne 0 ]]; then
            return 2 # Falha de rede/DNS/Timeout
        fi

        local first_code=$(echo "$first_response" | cut -d' ' -f1)
        local first_redirect=$(echo "$first_response" | cut -d' ' -f2)

        # 2. Se redirectou, verificar se é para auth.$DOMAIN
        # Redirect = 301, 302, 303, 307, 308
        if [[ "$first_code" =~ ^(301|302|303|307|308)$ ]]; then
            # Verificar se o redirect vai para auth.$DOMAIN
            if [[ "$first_redirect" == "$expected_auth_url"* ]] || \
               [[ "$first_redirect" == "${expected_auth_url%:*}"* ]]; then
                return 0 # PROTECTED - Redirect para Authentik
            fi
        fi

        # 3. Seguir redirects para verificar destino final (para apps com OIDC nativo)
        local final_response
        final_response=$(curl -I -s -L -k -m 5 "$service_url" -w "%{http_code} %{url_effective}" -o /dev/null)
        local final_code=$(echo "$final_response" | cut -d' ' -f1)
        local final_url=$(echo "$final_response" | cut -d' ' -f2)

        # CASO B: 401 exige autenticação
        if [[ "$final_code" == "401" ]]; then
            return 0 # PROTECTED (Exige auth)
        fi

        # CASO C: Se final_url é auth.$DOMAIN (RedirectAuth funcionou)
        if [[ "$final_url" == "$expected_auth_url"* ]]; then
            return 0 # PROTECTED
        fi

        return 1 # EXPOSED (Entrou direto sem passar pelo Authentik)
    }

    for service_name in "$@"; do        
        # Ignora argumentos vazios ou números perdidos (evita o erro de integer)
        [[ -z "$service_name" || "$service_name" =~ ^[0-9]+$ ]] && continue

        require_single_service_redirect_auth "$service_name"
        local res=$?

        if [[ $res -ne 0 ]]; then
            local status_code="$REQ_STATUS_MISS"
            [[ $res -eq 1 ]] && status_code="$REQ_STATUS_FAIL"
            
            debug_required_type_name "$_type" "$service_name" "$status_code" 2        
            missing_list+=("$service_name")  
        else
            echo "✅ $service_name is protected by Authentik." >&2
        fi
    done

    if [[ ${#missing_list[@]} -gt 0 ]]; then
        echo "🛑 Warning: ${#missing_list[@]} services are EXPOSED or unreachable!" >&2
        return 1
    fi
    
    return 0
}

require_http_status_ok() {
    local _type="HTTP_STATUS"
    local -a missing_list=()
    local http_status_ok_pattern="^(20[0-9]|30[0-2]|307|308)$" # 200s e Redirects comuns
    local http_status_proxy_err="^(502|503|504|404)$"

    require_single_url_status_ok() {    
        local target_url="$1"
        # -I: Headers | -s: Silent | -L: Follow Redirects | -k: Insecure | -m 5: Timeout
        # Formato de saída: "CODE|IP|URL"
        local response
        response=$(curl -I -s -L -k -m 5 "$target_url" -w "%{http_code}|%{remote_ip}|%{url_effective}" -o /dev/null)
        local curl_exit_status=$?

        if [ $curl_exit_status -ne 0 ]; then
            echo "❌ [NETWORK ERROR] Curl failed for $target_url (Code: $curl_exit_status)" >&2
            return 1 # Erro de conexão (DNS, Timeout, etc)
        fi

        # Parsing seguro usando o separador |
        local http_code=$(echo "$response" | cut -d'|' -f1)
        local remote_ip=$(echo "$response" | cut -d'|' -f2)
        local destination=$(echo "$response" | cut -d'|' -f3)

        # Validação de padrões usando Regex [[ =~ ]]
        if [[ "$http_code" =~ $http_status_proxy_err ]]; then
            echo "⚠️  [PROXY ERR] $target_url is offline (HTTP $http_code via $remote_ip)" >&2
            return 2
        elif [[ ! "$http_code" =~ $http_status_ok_pattern ]]; then
            echo "⚠️  [WARN] $target_url status $http_code not in OK pattern" >&2
            return 3
        fi

        echo "✅ [OK] $target_url ($http_code) -> $destination" >&2
        echo "$response" # Retorna a string para captura se necessário
        return 0
    }

    # Se não houver argumentos, usa o default
    local urls=("${@}")

    for var_name in "${urls[@]}"; do        
        local url=${!var_name}
        [ -z "$url" ] && continue
        status=$(require_single_url_status_ok "$url" 2>&1)
        local retcode=$?
        if [ $retcode -ne 0 ]; then
            missing_list+=("$url")
            #show_vars url _type status
            # Aqui podes chamar a tua função de debug personalizada
            debug_required_type_name "$_type" "url" "$status" 2
        fi
    done

    if [[ ${#missing_list[@]} -gt 0 ]]; then
        echo "🛑 Failure: ${#missing_list[@]} URL(s) failed health check." >&2
        return 1
    fi
    
    return 0
}

wait4_http_url_ready(){
    local url="${1}"
    local max_attempts="${2:-20}" 
    local attempt=1
    local _wait=1 
    local start_time=$(date +%s)
    require_vars url max_attempts _wait || return 1
    echo "⏳ Waiting for: $url" >&2
    printf "   State: " >&2 # Inicia a linha de progresso

    while [ $attempt -le $max_attempts ]; do
        # Executa silenciando tudo
        core_http_url_status "$url" >/dev/null 2>&1
        local is_ok=$?

        # Define o caractere baseado no código de saída
        local char="."
        case $is_ok in
            0)   char="✅" ;; # Sucesso: Tudo pronto!
            7)   char="🔌" ;; # Connection Refused (Porta fechada)
            28)  char="🕒" ;; # Timeout (Rede lenta/DNS)
            246) char="🔐" ;; # Permission/Locked (Recurso bloqueado ou sem acesso)
            502) char="🧱" ;; # Bad Gateway (Traefik ON, App OFF)
            503) char="🚧" ;; # Service Unavailable (Sobrecarregado)
            404) char="🔍" ;; # Not Found (Rota não mapeada)
            *)   char="❌" ;; # Outros erros ($is_ok)
        esac

        printf "%s" "$char" >&2 # Imprime o símbolo sem pular linha

        if [ $is_ok -eq 0 ]; then
            local duration=$(( $(date +%s) - start_time ))
            echo -e "\n🚀 [READY] Stabilized in ${duration}s!" >&2
            return 0
        fi

        if [ $attempt -eq $max_attempts ]; then
            echo -e "\n🛑 [TIMEOUT] Failed after $max_attempts attempts." >&2
            return 1
        fi

        sleep $_wait
        if [ $_wait -lt 3 ]; then ((_wait++)); fi
        ((attempt++))
    done
}
core_http_url_status(){    
    local url="${1}"
    require_vars url 
    
    # Definição dos padrões de status
    local http_status_ok_pattern="^(20[0-9]|30[0-2]|307|308)$"
    local http_status_proxy_err="^(502|503|504|404)$"

    # Formato de saída JSON para o curl
    local write_out_format='{"http_code":"%{http_code}","remote_ip":"%{remote_ip}","url_effective":"%{url_effective}","time_total":"%{time_total}"}'

    local response
    response=$(curl -I -s -L -k -m 5 "$url" -w "$write_out_format" -o /dev/null)
    local curl_exit_status=$?

    # 1. Erro de Conectividade (DNS, Timeout, Recusa de Conexão)
    if [ $curl_exit_status -ne 0 ]; then
        echo "❌ [ERROR] Network/Curl failure (Exit: $curl_exit_status) for $url" >&2
        return $curl_exit_status
    fi

    # Extração do status via JQ
    local http_code=$(echo "$response" | jq -r '.http_code')

    # 2. Validação via Regex: Sucesso ou Redirect
    if [[ "$http_code" =~ $http_status_ok_pattern ]]; then
        echo "✅ [OK] $url responded with $http_code" >&2
        echo $response | jq -c -e
        return 0
    fi

    # 3. Validação via Regex: Erros de Proxy/Aplicação
    if [[ "$http_code" =~ $http_status_proxy_err ]]; then
        echo "⚠️  [WARN] Service Unreachable (HTTP $http_code) at $url" >&2
        echo $response | jq -c -e
        return $http_code # Indica falha funcional
    fi

    # 4. Caso genérico (Outros 4xx ou 5xx não mapeados)
    echo "❓ [UNKNOWN] Unexpected status $http_code for $url" >&2
    echo $response | jq -c -e
    return $http_code
}


# helpfull to kill pihole ip when is captur eby other app or container
docker_container_kill_ip() {
    local target_ip="$1"
    local expected_name="$2" # Opcional: só mata se o nome coincidir
    
    if [[ -z "$target_ip" ]]; then
        echo "❌ [ERROR] Nenhum IP fornecido." >&2
        return 1
    fi

    echo "🔍 Procurando ocupante do IP: $target_ip..." >&2

    # 1. Localizar ID e Nome num único comando (evita múltiplos inspects)
    # Usamos grep com $ para garantir que o IP termina exatamente ali (evita 172.28.0.6 vs 172.28.0.60)
    local target_data
    target_data=$(docker inspect $(docker ps -aq) --format='{{.Id}} {{.Name}} {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null | grep -w "$target_ip" | head -n1)

    if [[ -n "$target_data" ]]; then
        local c_id=$(echo "$target_data" | awk '{print $1}')
        local c_name=$(echo "$target_data" | awk '{print $2}' | sed 's/\///')

        echo "🔪 Encontrado container: $c_name ($c_id)" >&2

        # Se passámos um nome esperado, validamos antes de matar
        if [[ -n "$expected_name" && "$expected_name" != "$c_name" ]]; then
            echo "⚠️ [SKIP] O IP $target_ip está em uso por '$c_name', mas esperava-se '$expected_name'. Não vou matar." >&2
            return 1
        fi

        # 2. Limpeza agressiva
        # Tenta desconectar de todas as redes primeiro para soltar o endpoint
        local networks=$(docker inspect "$c_id" --format='{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}')
        for net in $networks; do
            docker network disconnect -f "$net" "$c_id" 2>/dev/null || true            
        done

        docker rm -f "$c_id" >/dev/null
        echo "✅ Container $c_name removido e redes desconectadas." >&2
        sleep 1
    else
        echo "✅ Nenhum container Docker ativo ou parado a usar o IP $target_ip." >&2
        
        # 3. Fallback: Interface órfã no Host
        # Procura em interfaces veth ou bridges
        local iface=$(ip -o addr show | grep -w "$target_ip" | awk '{print $2}')
        if [[ -n "$iface" ]]; then
            echo "⚠️ Interface órfã detectada no Kernel ($iface). A limpar..." >&2
            sudo ip link set "$iface" down 2>/dev/null
            sudo ip link delete "$iface" 2>/dev/null
        fi
    fi
}
export -f docker_container_kill_ip


# >>>>> devops service secret recover
_get_service_secret_path() {    
    local input_path="$1"  
    local temp="${input_path%/}"
    local trimed_path="${temp#/}"

    local segments=$(echo "$trimed_path" | tr -s '/' '\n' | wc -l)
    if [[ "$segments" -lt 2 ]]; then
        echo "❌ [ERROR] Formato inválido: '$input_path'" >&2
        echo "   Uso correto: 'servico/CHAVE' (ex: authentik/AUTHENTIK_KEY)" >&2
        echo "   Uso correto: 'servico/partition/CHAVE' (ex: authentik/appRole/<uuid>)" >&2
        echo "                                          (ex: authentik/appRole/<secret>)" >&2
        return 1
    fi

    local service_nsp="${trimed_path%/*}"
    local secret_name="${trimed_path##*/}"

    require_vars input_path service_nsp secret_name || return 1

    local secret_providers
    { 
        # significa que secret provider value will be defined:
        #  - by defining PROVIDER_SELECT before invoke _put_service_secret_path
        #  - core .env SECRET_PROVIDERS
        #  - or static value AKA Ordem de tentativa: Memória -> Vault -> KeePass
        secret_providers="${PROVIDER_SELECT:-${SECRET_PROVIDERS:-"mem vault keepass"}}"
        unset PROVIDER_SELECT

    }   

    require_vars secret_providers || return 1
    ### the value
    local current_val=""

    # --- Funções Internas de Recuperação ---

    _fetch_mem_provider() {
        echo "fetching mem" >&2 
        local mem_service_path=$(core_secret_mapper_mem "$service_nsp" "$secret_name")
        
        if [[ -f "$mem_service_path" ]]; then
            current_val=$(cat "$mem_service_path")
            [[ -n "$current_val" ]] && return 0
        fi
        return 1
    }
    _fetch_vault_provider() {
        echo "fetching vault" >&2 
        local vault_service_path=$(core_secret_mapper_vault "$service_nsp" "$secret_name")
        if ! declare -f vault_get_secret >/dev/null; then
            source "$(core_resolve_file "vault/vault_lib.sh")" > /dev/null 2>&1
        fi
        local _dir="$(dirname $vault_service_path)"
        echo "vault_get_secret \"$_dir\" \"$secret_name\""
        current_val=$(vault_get_secret "$_dir" "$secret_name" 2>/dev/null)

        [[ -n "$current_val" ]] && return 0
        return 1
    }
    
    _fetch_keepass_provider() {    
        echo "fetching keepass" >&2   
        local keepass_service_path=$(core_secret_mapper_keepass "$service_nsp" "$secret_name")
        require_vars keepass_service_path || return 1

        source "$(core_resolve_file "vault/keepass.sh")"
        ## QA:OK list (group||folder) (entry||file)
        # show_vars keepass_service_path && kp ls "$(dirname "/$keepass_service_path")" || return 1

        current_val=$(kp_get_entry_value "$keepass_service_path")
        ## QA:OK show_vars current_val || return 1
        [[ -n "$current_val" ]] || return 1
        return 0
    }

    # --- Execução do Loop de Descoberta ---
    for provider in $secret_providers; do
        local func="_fetch_${provider}_provider"
        if declare -f "$func" >/dev/null; then
            if $func; then
                echo "🔓 '$secret_name' obtido via ${provider^^}" >&2
                break # Encontrou o valor, sai do loop
            fi
        fi
    done

    # --- Fallback: Auto-Provisionamento Guiado ---
    if [[ -z "$current_val" ]]; then
        echo "🎲 CRITICAL: Segredo $input_path não encontrado. PROVIDER_SELECT=\"$secret_providers\"." >&2
        echo "PROVIDER_SELECT=\"$secret_providers\" core_secret_service_get  \"$service_nsp/$secret_name\" " >&2        
        local new_val=$(openssl rand -base64 32)
        echo -e "\n💡 Sugestão para criar o segredo $secret_name:" >&2
        echo "----------------------------------------------------------------" >&2
        echo "PROVIDER_SELECT=\"$secret_providers\" core_secret_service_put  \"$service_nsp/$secret_name\" \"$new_val\"  " >&2        
        echo "----------------------------------------------------------------\n" >&2
        return 1
    fi

    # --- Finalização e Export ---
    if [[ -n "$current_val" ]]; then
        if [[ "$(sanitize_var_name $secret_name)" != "$secret_name" ]]; then
            ### is not variable. do not export
            return 0
        fi 
        echo "[export $secret_name len: ${#current_val}]" >&2        
        export "$secret_name"="$current_val"
        return 0
    else
        echo "❌ [FATAL] Não foi possível obter ou gerar o segredo $secret_name" >&2
        return 1
    fi
}
core_secret_service_get() {
    local input_path="$1"   
    # 3. Execução
    _get_service_secret_path "$input_path"
}
export -f core_secret_service_get
core_secret_service_put() {
    local input_path="$1"    
    local secret_val="$2"   

    require_vars input_path || return 1    
    _put_service_secret_path "$input_path" "$secret_val"
}
export -f core_secret_service_put

core_secret_runtime_delete() {
    # 1. Requisitos de segurança
    [[ -z "$MEM_ROOT_DIR" ]] && { echo "❌ ERRO: MEM_ROOT_DIR não definida!"; return 1; }
    [[ "$MEM_ROOT_DIR" == "/" ]] && { echo "❌ ERRO: Proteção contra suicídio acionada!"; return 1; }

    local input_path="$1"
    local target="$MEM_ROOT_DIR/$input_path"

    # 2. Validação de existência
    if [[ ! -e "$target" ]]; then
        echo "ℹ️  Aviso: '$input_path' não existe em runtime://. Nada a fazer."
        return 0
    fi

    # 3. Proteção Extra: Garantir que o target está DENTRO do MEM_ROOT_DIR
    if [[ "$(readlink -f "$target")" != "$(readlink -f "$MEM_ROOT_DIR")"* ]]; then
        echo "❌ ERRO: Tentativa de apagar fora do RUNTIME_ROOT permitido!"
        return 1
    fi

    echo "🧹 Destruição segura: runtime://$input_path"

    # 4. Abordagem Única para Ficheiro ou Pasta
    if [[ -d "$target" ]]; then
        # Destrói todos os ficheiros dentro do diretório recursivamente antes de apagar a pasta
        find "$target" -type f -exec shred -u -n 1 {} +
        rm -rf --one-file-system "$target"
    else
        # Destrói apenas o ficheiro específico
        shred -u -n 1 "$target"
    fi

    echo "✅ Removido com sucesso de $MEM_ROOT_DIR."
}
core_secret_mem_delete() {
    # 1. Requisitos de segurança (inline ou externa)
    [[ -z "$MEM_ROOT_DIR" ]] && { echo "❌ ERRO: MEM_ROOT_DIR não definida!"; return 1; }
    [[ "$MEM_ROOT_DIR" == "/" ]] && { echo "❌ ERRO: Proteção contra suicídio acionada!"; return 1; }

        require_functions core_secret_mapper_mem || return 1

    local input_path="$1"  
    local secret_val="$2"
    # validate
    local temp="${input_path%/}"
    local trimed_path="${temp#/}"
    require_vars input_path trimed_path || return 1
    local segments=$(echo "$trimed_path" | tr -s '/' '\n' | wc -l)

    local service_nsp="${trimed_path%/*}"
    local secret_name="${trimed_path##*/}"

    # Proceed with logic...
    require_vars secret_name service_nsp || return 1

    local target="$MEM_ROOT_DIR/$service_nsp/$secret_name"

    # 2. Validação de existência
    if [[ ! -e "$target" ]]; then
        echo "ℹ️  Aviso: '$input_path' não existe em $target . Nada a fazer."
        return 0
    fi

    # 3. Proteção Extra: Garantir que o target está DENTRO do MEM_ROOT_DIR
    # Impede que "../../../etc/passwd" seja apagado
    if [[ "$(readlink -f "$target")" != "$(readlink -f "$MEM_ROOT_DIR")"* ]]; then
        echo "❌ ERRO: Tentativa de apagar fora do ROOT permitido!"
        return 1
    fi

    echo "🧹 Destruição segura: $target"

    # 4. A Abordagem Única (The "Nuke" Approach)
    # - Se for ficheiro: Shred e Remove.
    # - Se for diretório: Shred em todos os ficheiros internos e remove a árvore.
    
    if [[ -d "$target" ]]; then
        # Destrói todos os ficheiros dentro do diretório recursivamente
        find "$target" -type f -exec shred -u -n 1 {} +
        # Remove a estrutura de pastas
        rm -rf --one-file-system "$target"
    else
        # Destrói apenas o ficheiro específico
        shred -u -n 1 "$target"
    fi

    echo "✅ Removido com sucesso."
}

core_secret_export2_env_vars() {   
    local service_nsp="${1}"
    shift 
    # Agora $@ contém APENAS os nomes das secrets (ex: REDIS_PASSWORD IMMICH_SECRET)
    local VARS_TO_PROCESS=("$@") 

    # Validamos primeiro
    require_vars MEM_ROOT_DIR DEVOPS_DIR || { echo "???" >&2; return 1; }

    local service_nsp=$(sanitize_path_name "$service_nsp")
    
    echo "VARS: ${VARS_TO_PROCESS[@]}"
    show_vars service_nsp || return 1

    # Mapeia o caminho no /run/user/$UID/home2500/*
    local _APP_SECRET_ENV
    _APP_SECRET_ENV="$(core_secret_mapper_mem "$service_nsp" ".secret")"    
    ## _MEM_X_DIR || the secrey path not yet the secret content
    local _MEM_X_DIR="$(dirname "$_APP_SECRET_ENV")"
        
    mkdir -p "$_MEM_X_DIR" || return 1

    echo "🏗️  Preparing secrets for $service_nsp issue..." >&2
    echo "📥 Injecting secrets from \"mem\"..." >&2
    
    # Criamos o ficheiro (limpa se já existir)
    echo "# $service_nsp/.secret file - $(date)" > "$_APP_SECRET_ENV"    
    echo "# $DOMAIN" >> "$_APP_SECRET_ENV"

    local val_content
    for var_name in "${VARS_TO_PROCESS[@]}"; do
        if PROVIDER_SELECT="mem" _get_service_secret_path "$service_nsp/$var_name" 2> /dev/null; then
            val_content="${!var_name}"
            
            case "$var_name" in
                DB_PASS|DB_URL)
                    val_content=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$val_content")
                    ;;
            esac
            
            echo "${var_name}=${val_content}" >> "$_APP_SECRET_ENV"
            echo "   ✅ Added $service_nsp/$var_name" >&2 > /dev/null
        else
            echo "   ❌ Failed to fetch secret: $service_nsp/$var_name" >&2
            return 1
        fi        
    done

    chmod 600 "$_APP_SECRET_ENV"
    echo "📍 Generated .secret path: $_APP_SECRET_ENV" >&2
}
core_secret_load_vars() {   
    local ARGS=("$@")
    
    # Validação de requisitos de infra
    require_vars MEM_ROOT_DIR DEVOPS_DIR || { 
        echo "❌ core_secret_load_vars: Variáveis de ambiente globais em falta." >&2
        return 1 
    }

    local target_provider=${PROVIDER_SELECT:-mem}
    echo "🏗️  Preparing secrets injection..." >&2

    for spec in "${ARGS[@]}"; do
        # Parsing da string: provider://namespace/var_name
        # Usando substituição de padrões do Bash
        local proto_rest="${spec%%://*}"        # Extrai 'keepass'
        local rest="${spec#*://}"               # Extrai 'authentik/VAR_NAME'
        local var_name="${rest##*/}"            # Extrai 'VAR_NAME' (última parte)
        local service_nsp="${rest%/*}"          # Extrai 'authentik' (parte do meio)
        
        # Sanitização
        service_nsp=$(sanitize_path_name "$service_nsp")
        local xprovider="$proto_rest"

        echo "📥 Fetching [$xprovider] -> $service_nsp/$var_name..." >&2


        # 1. Tentar primeiro o 'mem' (cache/performance)
        local val_content=""
        if PROVIDER_SELECT="$target_provider" core_secret_service_get "$service_nsp/$var_name" 2> /dev/null; then
            # Assume-se que core_secret_service_get popula uma variável global ou local 'value' 
            # ou a variável com o próprio nome $var_name
            val_content="${!var_name}"            
        else
            show_vars xprovider service_nsp var_name || return 1
            # 2. Se não estiver em mem, tenta o provider específico definido no argumento
            if ! PROVIDER_SELECT="$xprovider" core_secret_service_get "$service_nsp/$var_name"; then
                echo "   ❌ Failed to fetch secret from $xprovider: $service_nsp/$var_name" >&2
                return 1
            else    
                val_content="${!var_name}"
                PROVIDER_SELECT="$target_provider" core_secret_service_put "$service_nsp/$var_name" "$val_content" >/dev/null 2>&1
            fi
        fi        
        # 3. Extração do valor
          
        if [[ -z "$val_content" ]]; then
            echo "   ⚠️  Warning: Secret $var_name is empty!" >&2
        fi

        # 4. Escrita no .secret
        #echo "${var_name}=${val_content}" >> "$_APP_SECRET_ENV"
        #echo "   ✅ Loaded $var_name" >&2
    done

    echo "🚀 All secrets loaded into provider mem" >&2
    return 0
}
# Mapeia o caminho interno do KeePass (Estrutura de Pastas)

core_secret_mapper_keepass () {
    local service_ns="$1" 
    local secret_name="$2"     
    require_vars KEEPASS_ROOT_DIR service_ns secret_name || return 1
    echo "$KEEPASS_ROOT_DIR/$service_ns/$secret_name"
}
core_secret_mapper_mem () {
    local service_ns="$1" 
    local secret_name="$2"     
    require_vars MEM_ROOT_DIR service_ns secret_name || return 1
    echo "$MEM_ROOT_DIR/$service_ns/$secret_name"
}
core_secret_mapper_vault () {
    local service_ns="$1" 
    local secret_name="$2"     
    require_vars VAULT_ROOT_DIR service_ns secret_name || return 1
    echo "$VAULT_ROOT_DIR/$service_ns/$secret_name"
}



_put_service_secret_path() {
    local input_path="$1"  
    local secret_val="$2"
    # validate
    local temp="${input_path%/}"
    local trimed_path="${temp#/}"
    require_vars input_path trimed_path || return 1
    local segments=$(echo "$trimed_path" | tr -s '/' '\n' | wc -l)
    if [[ "$segments" -lt 2 ]]; then
        echo "❌ [ERROR] Formato inválido: '$input_path'" >&2
        echo "   Uso correto: 'servico/CHAVE' (ex: authentik/AUTHENTIK_KEY)" >&2
        echo "   Uso correto: 'servico/partition/CHAVE' (ex: authentik/appRole/<uuid>)" >&2
        echo "                                          (ex: authentik/appRole/<secret>)" >&2
        return 1
    fi

    local service_nsp="${trimed_path%/*}"
    local secret_name="${trimed_path##*/}"

    local secret_providers
    { 
        # significa que secret provider value will be defined:
        #  - by defining PROVIDER_SELECT before invoke _put_service_secret_path
        #  - core .env SECRET_PROVIDERS
        #  - or working static value
        secret_providers="${PROVIDER_SELECT:-${SECRET_PROVIDERS:-"mem vault keepass"}}"
        unset PROVIDER_SELECT
    }   

    if [[ -z "$secret_val" ]]; then
        echo "❌ [PUT ERROR] Valor vazio para o path $input_path. Abortado." >&2
        return 1
    fi
     
    # Mapeamento de caminhos em cada serviço
    local keepass_service_path=$(core_secret_mapper_keepass "$service_nsp" "$secret_name")
    local vault_service_path=$(core_secret_mapper_vault "$service_nsp" "$secret_name")
    local mem_service_path=$(core_secret_mapper_mem "$service_nsp" "$secret_name")

    require_vars secret_name service_nsp \
        vault_service_path \
        keepass_service_path \
        mem_service_path || return 1

    # --- Definições das Funções de Armazenamento ---
    
    _store_mem_secret() {
        echo "💾 [MEM] Fazendo cache de $secret_name..." >&2
        local mem_service_path=$(core_secret_mapper_mem "$service_nsp" "$secret_name")

        local service_dir="$(dirname $mem_service_path)"           
        mkdir -p "$service_dir"
        chmod 700 "$service_dir"

        mkdir -p "$(dirname "$mem_service_path")"
        echo "$secret_val" > "$mem_service_path"
        chmod 600 "$mem_service_path"
    }
        
    _store_vault_secret() {
        if ! declare -f vault_save_secret >/dev/null; then
             source "$(core_resolve_file "vault/vault_lib.sh")" > /dev/null 2>&1
        fi

        if ! is_sealed; then
            echo "🔒 [VAULT] Salvando $secret_name em $vault_service_path..." >&2
            local _dir=$(dirname $vault_service_path)
            if ! VAULT_SKIP_VERIFY=true vault_save_secret "$_dir" "$secret_name" "$secret_val" 2>/dev/null; then
                echo "⚠️  [VAULT] Falha na escrita em $vault_service_path." >&2
                return 1
            fi
        fi
    }

    _store_keepass_secret(){
        if ! declare -f kp >/dev/null; then
            source "$(core_resolve_file "vault/keepass.sh")" > /dev/null 2>&1
        fi               

        echo "📓 [KEEPASS] Persistindo $secret_name..." >&2
        if ! kp_save_entry "$keepass_service_path" "$secret_val"; then
            echo "❌ [FATAL] Erro ao gravar novo segredo no KeePass!" >&2
            return 1
        fi
    }

    # --- Execução Dinâmica ---
    # O loop 'for provider in $list' divide a string por espaços automaticamente
    # show_vars secret_providers
    for provider in $secret_providers; do
        local func_name="_store_${provider}_secret"
        if declare -f "$func_name" >/dev/null; then
            $func_name || echo "⚠️  Provider $provider falhou, mas continuando..." >&2
        else
            echo "❓ Provider desconhecido: $provider" >&2
        fi
    done

    # --- Passo C: Injeção no Ambiente Atual ---

    if [[ "$(sanitize_var_name $secret_name)" != "$secret_name" ]]; then
        ### is not variable. do not export
        return 0
    fi    

    echo "✅ [EXPORT] $secret_name (length: ${#secret_val})" >&2
    export "$secret_name"="$secret_val"
    return 0
}


core_transform_inject_env_file_vars() {
    local env_file="${1:-".env"}"
    local match_prefix="${2}" # diz ao regex: "comece no início da linha"
    local replace_prefix="${3}"
    # Substituí * por .* para funcionar corretamente no Regex do Bash
    local match_prefix_exceptions="${4:-ENV.*}"

    require_vars env_file || return 1    

    if [[ ! -f "$env_file" ]]; then
        echo "⚠️  [WARN] Ficheiro $env_file não encontrado." >&2
        return 1
    fi

    echo -e "📦 Extraindo variáveis $(core_relative_path2 $env_file) 
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
# to<type representation>: toPascalCase
to_pascal_case() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed -r 's/(^|_)([a-z])/\U\2/g'
}
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
ask_provision() {
    local _type="$1"
    require_vars VAULT_TOKEN  # Usa a tua função de validação

    # 1. Validação de Asset
    [[ -z "$_type" ]] && { echo "❌ Erro: tipo de provisao não especificado."; return 1; }

    # 2. Vault Policy Lookup (O "Coração" da Segurança)
    # Verificamos se o token atual possui a política necessária
    local token_policies
    token_policies=$(vault token lookup -format=json 2>/dev/null | jq -r '.data.policies[]')
    
    if ! echo "$token_policies" | grep -q "app-steward-policy"; then
        echo "🚫 [SEGURANÇA] O VAULT_TOKEN não possui a política 'app-steward-policy'." >&2
        echo "⚠️  Operação de $_type negada por falta de privilégios no Vault." >&2
        return 1
    fi

    # 3. Proteção Anti-Automação (Interactive Only)
    if [[ ! -t 0 ]]; then
        echo "🚫 [SEGURANÇA] ask_provision em modo não-interativo. Bloqueado." >&2
        return 1
    fi    

    # 4. Interface de Confirmação
    echo -e "\n⚠️  ATENÇÃO: Estás prestes a iniciar o provisionamento de: \033[1;33m$_type\033[0m"
    read -p "Confirma a operação? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Abortado pelo utilizador. Nenhuma alteração efetuada."
        return 1
    fi

    echo "🔥 Autorização concedida. Iniciando $_type..."
    return 0
}
ask_nuke() {
    local asset="$1"
    
    # 1. Validação de Requisito: O Asset deve ser declarado
    [[ -z "$asset" ]] && { echo "❌ Erro: Asset não especificado para destruição."; return 1; }

    # 2. Proteção Anti-Automação (Non-Interactive Mode)
    # [ -t 0 ] verifica se o Standard Input (stdin) é um terminal (TTY)
    if [[ ! -t 0 ]]; then
        echo "🚫 [SEGURANÇA] ask_nuke invocado em modo não-interativo. Operação bloqueada por proteção de Asset." >&2
        return 1
    fi

    echo -e "\n☢️  [ALERTA MÁXIMO] INICIANDO DESTRUIÇÃO DE ASSET: **$asset**"
    echo "------------------------------------------------------------"
    echo "⚠️  Esta operação é IRREVERSÍVEL."
    echo "⚠️  Todos os dados associados a '$asset' serão APAGADOS permanentemente."
    echo "------------------------------------------------------------"

    # 3. Desafio de Confirmação (Prompt Ativo)
    # Em vez de apenas y/n, pedimos o nome do asset para confirmar intenção real
    local confirm
    read -p "❓ Para confirmar a destruição total de '$asset', escreva o nome do asset: " confirm
    echo

    if [[ "$confirm" != "$asset" ]]; then
        echo "❌ Confirmação falhou. O nome introduzido não coincide com '$asset'."
        echo "❌ Operação abortada por segurança."
        return 1
    fi

    # 4. Confirmação Final (Y/N)
    read -p "❗ ÚLTIMO AVISO: Tens a certeza absoluta? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Abortado no último segundo. Nada foi destruído."
        return 1
    fi

    echo "🔥 Autorização concedida. Iniciando destruição de $asset..."
    return 0
}


test____________________________() {
    (
        ### dynamic
        
        local what_CARNAVAL="/mnt/ssd980/Projects/nextjs-app-template/devops/fotos"    
        require_locations "what_CARNAVAL"

        ### static
        local ABS_PATH="fotos"
        require_locations ABS_PATH

        local A="$(realpath "$what_CARNAVAL/tool.sh")"
        require_files A

        #test_debug_required    
        what_CARNAVAL="/mnt/ssd980/Projects/nextjs-app-template/devops/fotos"    
        require_locations "what_CARNAVAL"
        A="$(realpath "$what_CARNAVAL/../core.sh")"
        require_files A
    )
}
#### CONTEXT FILE TOOL

core_search_file_json() {    
    local _file="${1}"
    shift
    local _term="${1}"
    shift
    local filterKVS=("$@") 
    
    require_vars _file _term || return 1
    [[ ! -f "$_file" ]] && return 1

    local rel_path=$(realpath --relative-to="$PWD" "$_file" 2>/dev/null || echo "$_file")

    local ret
    ret=$(grep -niE "$_term" "$_file" | \
        while IFS=: read -r line_num line_content; do
            # Calcula a coluna (index do termo na linha)
            # O awk aqui procura o offset do termo ignorando case (tolower)
            local col_num
            col_num=$(echo "$line_content" | awk -v t="${_term,,}" '{print index(tolower($0), t)}')

            # Passamos a linha para o sed processar name/value
            echo "$line_num|$col_num|$line_content"
        done | \
        sed -E 's/^([0-9]+)\|([0-9]+)\|[[:space:]]*([^:]+):?[[:space:]]*(.*)$/\1|\2|\3|\4/' | \
        jq -Rn --arg sc "$rel_path" --arg term "$_term" '
            [ inputs | split("|") | 
            {
                file: $sc, 
                line: (.[0]|tonumber),
                col: (.[1]|tonumber),
                name: .[2], 
                value: .[3],
                match_location: (if .[2] | test($term; "i") then "name" else "value" end)
            }
            ]
        ')
    # 2. Lógica de Filtro L2 (Exclusão/Refinamento)
    if [[ ${#filterKVS[@]} -eq 0 ]]; then
        echo "$ret" | jq -c '.'
    else
        # 1. Construir dinamicamente a query do JQ
        local jq_filter="."
        local kv key val
        
        # Iteramos pelos valores do array (ou índices se preferires)
        for kv in "${filterKVS[@]}"; do
            # 1. 'key' é tudo ANTES do primeiro '='
            key="${kv%%=*}"
            
            # 2. 'val' é tudo DEPOIS do primeiro '='
            val="${kv#*=}"
            
            # Debug para validação
            # show_vars key val
            
            # 3. Construção da query JQ
            # .["key"] permite acessar campos dinâmicos no objeto JSON
            jq_filter+=" | map(select( .[\"$key\"] | tostring | test(\"$val\"; \"i\") ))"
        done

        # 2. Executar uma única vez
        echo "$ret" | jq -c "$jq_filter"
    fi
}

require_search_file() {
    local ref=${1}
    local _file=${!ref}
    shift
    local term="${1}"
    shift
    local filterKVS=("$@") 

    # 1. Validação de Referência
    [[ -z "$_file" ]] && { echo "❌ Erro: Referência $_file vazia." >&2; return 1; }
    [[ ! -f "$_file" ]] && { echo "❌ Erro: Ficheiro não encontrado." >&2; return 1; }
  
    local _json
    _json=$(core_search_file_json "$_file" "$term" "${filterKVS[@]}" 2> /dev/null)

    # 2. Verificação de conteúdo (JSON vazio ou nulo)
    if [[ -z "$_json" ]] || [[ "$_json" == "[]" ]]; then
        printf "  \e[1;31m󰅙 \e[0m Missing: \e[1;33m%-30s\e[0m \e[1;30m-> [%s]\e[0m\n" \
            "$term" "$(realpath --relative-to="$PWD" "$_file")" >&2
        return 1
    fi

    # 3. Processamento eficiente (Stream do JQ para o Bash)
    # Extraímos os campos separados por | para ler tudo numa única passagem
    
    local label="${LABEL:-"✅ Found:  "}"
    
    # Processamento via Process Substitution para performance
    while IFS="|" read -r f_path f_line f_col f_type f_name f_value; do
        
        # Lógica para decidir o que mostrar como "contexto"
        local context_val
        if [[ "$f_type" == "name" ]]; then
            context_val="$f_name"
        else
            context_val="$f_value"
        fi

        # Link clicável: file:line:col
        # Ordem dos placeholders:
        # 1. %b (label) 
        # 2. %-10s (tipo: name/value)
        # 3. %-20s (contexto/termo)
        # 4. %s:%s:%s (link completo)
        printf " \e[1;32m%b \e[1;30m[%-5s]\e[0m \e[1;34m%-25s\e[0m \e[1;90m->\e[0m \e[4;36m%s:%s:%s\e[0m\n" \
            "$label" \
            "$f_type" \
            "$context_val" \
            "$f_path" \
            "$f_line" \
            "$f_col" >&2

    done < <(echo "$_json" | jq -r '.[] 
        | "\(.file)|\(.line)|\(.col)|\(.match_location)|\(.name)|\(.value)"
    ')
    return 0
}

####  CONTEXT EXEC TOOL 
core_fn_json() {
    local script_file="${1:-${BASH_SOURCE[0]}}"
    local filter="${2:-"."}"   # L1: Seleção primária
    local filterL2="${3:-""}"  # L2: Refinamento (Regex JQ)
    
    [[ ! -f "$script_file" ]] && return 1

    # --- Lógica do Regex L1 (Bash) ---
    local regex_filter
    if [[ -z "$filter" ]] || [[ "$filter" == "." ]] || [[ "$filter" == "*" ]]; then
        regex_filter=".*"
    elif [[ "$filter" =~ [\|] ]]; then
        regex_filter="^(${filter//\*/.*})$"
    else
        regex_filter="^${filter//\*/.*}$"
    fi

    local rel_path=$(realpath --relative-to="$PWD" "$script_file" 2>/dev/null || echo "$script_file")

    # --- Processamento ---
    local ret
    ret=$(
        grep -nE '^[[:space:]]*(function[[:space:]]+|[[:alnum:]_-]+[[:space:]]*\(\))' "$script_file" | \
        sed -E "s/^([0-9]+):[[:space:]]*(function[[:space:]]+)?/\\1:/" | \
        sed -E "s/:([[:alnum:]_-]+).*/:\\1/" | \
        while IFS=: read -r line_num func_name; do
            if [[ "$func_name" =~ $regex_filter ]]; then
                jq -nc --arg sc "$rel_path" --arg fn "$func_name" --arg ln "$line_num" \
                    '{script: $sc, function: $fn, line: ($ln|tonumber)}'
            fi
        done
    )
    # >>>>>> responder . when to filter. how to filter
    {
        ## the optional response filter L2
        if [[ -z "$filterL2" ]]; then
            echo $ret | jq -sc .
        else
            #show_vars filterL2
            local filtered_ret
            filtered_ret=$(
                echo "$ret" | jq -s --arg l2 "^${filterL2}$" '
                    map(select(
                        (.function | test($l2) | not)                         
                    ))
                '
            )
            echo $filtered_ret | jq -c '.'
        fi
    } 
}

core_fn_sort_json() {    
    local script_file="${1:-${BASH_SOURCE[0]}}"
    local rules_generator="${2:-core_fn_sort_weights}"
    local match_filter="${3:-"*"}"
    local match_filterL2="${4:-""}"
        
    # 1. Obter os dados e forçar a conversão para ARRAY usando -s
    local catalog_data
    catalog_data=$(core_fn_json "$script_file" "$match_filter" "$match_filterL2" | jq -c '.')
    local rules_data
    rules_data=$("$rules_generator" | jq -c '.')

    #show_vars rules_data catalog_data
    #echo $catalog_data | jq '.'

    # 2. Processar - Usamos --argjson para segurança total (evita problemas com caracteres especiais)
    local RESP_L1=$(
        jq -n \
            --argjson catalog "$catalog_data" \
            --argjson rules "$rules_data" '
            ($catalog // []) as $catalog |
            ($rules // []) as $valid_rules |

            $catalog | map(
                . as $f |
                (
                    # Prioridade por peso (weight)
                    ($valid_rules | sort_by(.weight) | map(
                        . as $rule |
                        (if $rule.prefix == "." then ".*" 
                        else 
                            ($rule.prefix | gsub("\\."; "\\.") | gsub("\\*"; ".*"))
                        end) as $rgx |
                        
                        # Match inteligente: âncora no início se não houver pipes ou wildcards genéricos
                        select($f.function | test(
                            if ($rule.prefix | contains("|") or $rule.prefix == ".") then $rgx 
                            else "^" + $rgx 
                            end
                        ))
                    ) | first // {cat: "MISC", weight: 99}) as $m |
                    
                    . + { "cat": $m.cat, "_r": $m.refine ,"_w": $m.weight }
                )
            )
            | sort_by(._w, .function)
            | {
                "total": length,
                "by_category": (if length > 0 then group_by(.cat) | sort_by(.[0]._w) | map({key: .[0].cat, value: .[0]._w}) | from_entries else {} end),
                "by_category2": (if length > 0 then 
                    group_by(.cat) 
                    | sort_by(.[0]._w) 
                    | map({
                        key: .[0].cat, 
                        value: { 
                            "count": length, 
                            "weight": .[0]._w 
                        }
                    }) 
                    | from_entries 
                else {} end),
                "functions": map(del(.weight))
            }
        ' | jq -c .
    )

    echo "$RESP_L1" | jq -c \
    --arg Lsearch "$match_filter" \
    --arg Lrefine "$match_filterL2" \
    '. | {
        "total": .total,
        "search": $Lsearch,
        "refine": $Lrefine,
        "by_category": .by_category,
        "by_category2": .by_category2,
        "functions": .functions
    }'
    ### @todo filter L2 function name
}

core_fn_sort_weights() {
    local rules_json
    rules_json=$(cat <<-'EOF'
[
    {"prefix": "core_desired_*|desired_*", "refine": "", "weight": 10, "cat": "CORE-NAMES"},
    {"prefix": "core_secret_*|_store_*|_fetch*|*_secret_path",  "weight": 23, "cat": "CORE-SECRET"},
    {"prefix": "core_fn_*",  "weight": 24, "cat": "CORE-CATALOG"},
    {"prefix": "core_*|wait4*", "refine": "", "weight": 29, "cat": "CORE-OTHER"},    
    {"prefix": "require_*", "weight": 30, "cat": "ASSERT"},
    {"prefix": "debug_*|stack_*|show_*|_search_file_lines", "refine": "", "weight": 64, "cat": "DEBUG"},
    {"prefix": "check_*",   "weight": 40, "cat": "RUNTIME"},
    {"prefix": "cr_*",      "weight": 41, "cat": "RUNTIME"},
    {"prefix": "docker_*",  "weight": 50, "cat": "INFRA"},
    {"prefix": "nvidia_*",  "weight": 51, "cat": "INFRA"},
    {"prefix": "ask_*",     "weight": 60, "cat": "INTERACT"},
    {"prefix": "*functions*|*_fn_*", "weight": 65, "cat": "DEV"},
    {"prefix": "dev_*|detect_*|sanitize_*|to_*",     "weight": 70, "cat": "DEV"},
    {"prefix": "_*",        "weight": 80, "cat": "INTERNAL"},    
    {"prefix": ".",         "weight": 90, "cat": "MISC"}
]
EOF
)
    # Mantive o output como ARRAY (removendo o .[] no fim) conforme o teu último exemplo
    echo "$rules_json" | jq -c '
        map(. + {refine: (.refine // "")}) 
        | sort_by(.weight, .prefix) 
    '
}

core_fn_catalog() {
    local script_file="${1:-${BASH_SOURCE[0]}}"
    local rules_generator="${2:-"core_fn_sort_weights"}"
    
    local catalog_data
    catalog_data=$(core_fn_sort_json "$script_file" "$rules_generator" | jq -c .)

    echo "$catalog_data" | jq -r '"Total: \(.total) functions\n"'

    local -a orderCatalog
    mapfile -t orderCatalog < <(echo "$catalog_data" | jq -r '.by_category | to_entries[] | .key')

    local -a acum_names=()
    local ctotal search_str refine_str         
    
    for cat in "${orderCatalog[@]}"; do      
        
        ctotal=$(echo "$catalog_data" | jq -r --arg cat "$cat" '.by_category[$cat]')
        [[ $ctotal -eq 0 ]] && continue

        search_str=$("$rules_generator" | jq -r --arg cat "$cat"  '
            .[] | select(.cat == $cat) | .prefix
        ' | paste -sd "|" - | tr -s '|' | sed 's/^|//;s/|$//')

        refine_str=$("$rules_generator" | jq -r --arg cat "$cat"  '
            .[] | select(.cat == $cat) | .refine
        ' | paste -sd "|" - | tr -s '|' | sed 's/^|//;s/|$//')
                
        printf "[%15s] functions: %3d | Prefixes: [%s] Refine: [%s]\n" "$cat" "$ctotal" "$search_str" "$refine_str"

        local filterL2="|"
        [[ -n "$refine_str" && "$refine_str" != '""' ]] && filterL2+="${refine_str}|"            
        
        if [[ ${#acum_names[@]} -gt 0 ]]; then    
            local temp_s=$(printf "|%s" "${acum_names[@]}")
            filterL2+="${temp_s:1}|"             
        fi
        
        filterL2=$(echo "$filterL2" | tr -s '|' | sed 's/^|//;s/|$//')
        
        local part_catalog
        part_catalog=$(core_fn_sort_json "$script_file" "$rules_generator" "$search_str" "$filterL2" | jq -c .)

        local -a fn_names
        mapfile -t fn_names < <(echo "$part_catalog" | jq -r '.functions[]?.function // empty')        
        [[ ${#fn_names[@]} -gt 0 ]] && acum_names+=("${fn_names[@]}")

        echo "------------------------------------------------------------"
        echo "$part_catalog" | jq -r '
            .functions[] |
            "  - \u001b[1;32m\(.function)()\u001b[0m -> \u001b[1;34m\(.script):\(.line)\u001b[0m"
        '     
        echo ""
    done
}
list_functions() {
    local script_file="$1"
    local filter="${2:-"*"}"
    # Chamamos a nossa versão JSON, filtramos com jq e imprimimos de forma visual
    core_fn_json "$script_file" "$filter" 2> /dev/null | jq -r '.[] | "\(.function) \(.script) \(.line)"' | \
    while read -r func_name rel_path line_num; do
        # Aqui replicamos a tua formatação visual original
        #printf "  - \e[1;32m%-30s\e[0m -> \e[1;34m%s:%s\e[0m\n" \
        debug_link_file \
                    "${func_name}()" "$rel_path" "$line_num"
    done | sort

}


list_sorted_functions2() {
    local script_file="${1:-${BASH_SOURCE[0]}}"
   

    # ✅ Call ONCE and store in variable
    local json_output
    json_output=$(core_fn_sort_json "$script_file" )

    # Print summary header
    echo -e "\e[1m=== Functions in $(basename "$script_file") ===\e[0m"
    echo "$json_output" | jq -r '"Total: \(.total) functions"'
    echo "$json_output" | jq -r '.by_category | to_entries | sort_by(.key) | .[] | "  \(.key): \(.value)"'
    echo ""

    # Print formatted list
    echo "$json_output" | jq -r '
        .functions[] | 
        "  - \u001b[1;32m\(.function)()\u001b[0m -> \u001b[1;34m\(.script):\(.line)\u001b[0m \u001b[2;37m[\(.cat)]\u001b[0m"
    '
}

core_load_requirements() {
    ## export devops .env vars
    require_locations DEVOPS_DIR || return 1
    require_files DEVOPS_ENV_FILE || return 1
    core_transform_inject_env_file_vars "$DEVOPS_ENV_FILE"

    desired_domain_names_generate() {
        require_vars DOMAIN PUBLIC_SERVICES_LIST
        
        local list_items=(${PUBLIC_SERVICES_LIST})
        local processed_names=()

        # Adicionamos >&2 no final dos echos
        echo "🌐 Processing Public Services..." >&2

        for name in "${list_items[@]}"; do 
            #echo "  -> Expected: ${name}.${DOMAIN}" >&2
            processed_names+=("${name}.${DOMAIN}")
        done

        export SORTED_DESIRED_NAMES=$(printf "%s\n" "${processed_names[@]}" | sort -u | paste -sd "," -)   
        export PUBLIC_SERVICES=("${processed_names[@]}")
    }
    desired_domain_names_generate # > /dev/null 2>&1

    export DOMAIN="${DOMAIN:-"home2500.local"}"
    export INTERNAL_DOMAIN="${INTERNAL_DOMAIN:-"app-network"}"

    export PUBLIC_SERVICES_LIST="$PUBLIC_SERVICES_LIST"
    export AUTHENTIK_ADMIN_USER=${AUTHENTIK_ADMIN_USER,-"akadmin"}
    export VAULT_PKI_CN=${VAULT_PKI_CN-"home2500.local"}
    export VAULT_ROOT_CA_NAME=${VAULT_ROOT_CA_NAME,"root-home2500"}
    export NETWORK_INTERFACE="$NETWORK_INTERFACE"

    export TRUSTED_CA_FILE="$DEVOPS_DIR/trusted-ca.pem"
        
    export KEEPASS_ROOT_DIR="vault" 
    export VAULT_ROOT_DIR="secret"
    export MEM_ROOT_DIR="/run/user/$UID/home2500"
   
    require_locations MEM_ROOT_DIR || {
        mkdir -p "$MEM_ROOT_DIR"
        chmod 700 "$MEM_ROOT_DIR"
    }

    # used to extract filtered logs
    #core_desired_domain_names_json 
    export SERVICES_PIPE=$(printf "|%s" "${PUBLIC_SERVICES[@]}" | sed 's/^|//')

    ### the PROVIDER_SELECT variable must not be exported. please. why ? cause it is used to switch "secret service" selection 007
    unset PROVIDER_SELECT 
    show_vars DOMAIN \
        INTERNAL_DOMAIN \
        PUBLIC_SERVICES_LIST \
        AUTHENTIK_ADMIN_USER \
        VAULT_PKI_CN \
        VAULT_ROOT_CA_NAME \
        SERVICES_PIPE \
        MEM_ROOT_DIR \
        KEEPASS_ROOT_DIR \
        VAULT_ROOT_DIR \
        NETWORK_INTERFACE \
        TRUSTED_CA_FILE
}
unset SKIP_ROOT_SCRIPT_CODE
if [[ ! -t 1 && ! -t 2 ]]; then    
    # Estamos em "Silent Mode" (source > /dev/null 2>&1)
    # Podemos pular comandos visuais pesados como o stack_trace()
    SKIP_ROOT_SCRIPT_CODE=true
fi
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    # Opcional: Inicia core_load_requirements semnpre que em script esteja em mode source
    core_load_requirements
    
    # Camada de Interatividade para o Vault
    if [[ "$SKIP_ROOT_SCRIPT_CODE" != "true" ]]; then
        
        #require_vars VAULT_CACERT      
        echo "core_fn_catalog"
        
    else
        echo "⚠️  Non-interactive mode: skipping token validation." >&2
    fi

fi