#!/bin/bash
# Filename: ../../devops/pihole/./pihole_lib.sh

# Top of pihole_lib.sh
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ This is a library and should be sourced, not run directly." >&2
    return 1
fi


PIHOLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo $PIHOLE_DIR >&2

# Load the file
set -a
__core=$(realpath "$PIHOLE_DIR/../core.sh") 
__keepass=$(realpath "$PIHOLE_DIR/../vault/keepass.sh") 
source  "$__core"  > /dev/null 2>&1
source  "$__keepass"  > /dev/null 2>&1

set +a

# Convert the string into a Bash Array
echo "PUBLIC_SERVICES ALL=${PUBLIC_SERVICES[@]}" >&2

echo "PUBLIC_SERVICES COUNT=${#PUBLIC_SERVICES[@]}" >&2
echo "PUBLIC_SERVICES ALL=${PUBLIC_SERVICES[@]}" >&2
echo "DOMAIN=$DOMAIN" >&2
echo "INTERNAL_DOMAIN=$INTERNAL_DOMAIN" >&2

DEBUG=false require_vars "PUBLIC_SERVICES" "DOMAIN" "INTERNAL_DOMAIN"

## hard coded 4 now
export PIHOLE_CONTAINER_NAME="pihole"
export PIHOLE_DNS_IP="$(detect_active__ipv4)" ### NOT USED ANY MORE :) (PIHLO) "172.20.0.2"
export PIHOLE_URL="http://$PIHOLE_DNS_IP:8080"
export PIHOLE_SPARK_DNS=("1.1.1.1" "8.8.8.8")

DEBUG=false require_vars \
    "PUBLIC_SERVICES" "DOMAIN" "INTERNAL_DOMAIN" \
    PIHOLE_CONTAINER_NAME PIHOLE_DNS_IP 
    #PIHOLE_URL


# Internal Function: Captures both Body and Status Code

__handler_run() {
    local actionx="$1"
    shift
    local argsx=("$@") 

    if ! declare -f "$actionx" >/dev/null; then
        echo "❌ Missing handler fn: $actionx" >&2
        return 1
    fi

    # If there is piped data, feed it; otherwise just run.
    # We avoid res=$(...) to ensure environment variables (SID) persist.
    if [[ ${#pipe_values[@]} -gt 0 ]]; then
        printf "%s\n" "${pipe_values[@]}" | "$actionx" "${argsx[@]}"
    else
        "$actionx" "${argsx[@]}"
    fi
    
    return $?
}

ph_api(){
    local cmd="$1" # test(), open|close|dns|password
    cmd="${cmd##*(_)}"         
    cmd="${cmd%%*(_)}"
    shift
    local args=("$@") 

    

    # 1. Captura o STDIN (pipe) para um array, se existir
    local pipe_values=()
    if [[ ! -t 0 ]]; then
        mapfile -t pipe_values
    fi

    api__close_() {
        if [ -n "$X_FTL_SID" ]; then
            curl -s -k -X DELETE "$PIHOLE_URL/api/auth" -H "X-FTL-SID: $X_FTL_SID" >/dev/null >&2
            echo "✅ Logout! SID: $X_FTL_SID" >&2
            unset X_FTL_SID        
        fi
        api__password_ cleanup
        kp close 2> /dev/null  || echo "is closed" >&2
    }

    api__open_() {    
        kp open && api__password_ restore #|| kp test        
    }
    api__auth_() {                        
        
        
        require_vars "PIHOLE_URL" || return 1
        
        local max_attempts=${2:-2}
        local attempt=1
        local wait_time=0.5  # segundos entre tentativas

        debug=false 
        require_containers_ready PIHOLE_CONTAINER_NAME || return 1

        local web_api_pw=$(
            if PROVIDER_SELECT="mem" core_secret_service_get "pihole/WEB_API_PASSWORD" > /dev/null 2>&1; then           
                echo "$WEB_API_PASSWORD"
            fi                
        )
        
        if ! require_vars web_api_pw; then
            echo "missing password. 
            run: 
                ph api open" >&2
            return 1
        fi

        echo "🔐 Attempting to authenticate with Pi-hole at $PIHOLE_URL..." >&2
        ##local web_api_pw="$1"; require_vars web_api_pw || return 1
        __get_sid() {
            local password="$1"
            require_vars password || return 1
            # We use -L to follow redirects and -i to ensure we get the full picture
            local response=$(curl -s -k -X POST "$PIHOLE_URL/api/auth" \
                -H "Content-Type: application/json" \
                -d "{\"password\": \"$password\"}" \
                -w "\n%{http_code}")
            curl_status=$?

            if [ $curl_status -ne 0 ]; then
                return $curl_status # Or just return $curl_status
            fi
            #show_vars response 
            local http_code=$(echo "$response" | tail -n1)
            local body=$(echo "$response" | sed '$d' | jq .)
            
            # Debug: uncomment the next line if you still have issues
            # echo "DEBUG: Code: $http_code Body: $body" >&2
            if [ "$http_code" == "200" ]; then
                local sid=$(echo "$body" | jq -r '.session.sid // empty')
                if [ -n "$sid" ]; then
                    echo "$sid"
                    return 0
                fi
            else
                local message=$(echo "$body" | jq -r '.session.message // empty')
                echo "$http_code $message" >&2
                return $http_code
            fi
        }

        while [ $attempt -le $max_attempts ]; do
            local sid_result
            
            sid_result=$(__get_sid "$web_api_pw" 2>/dev/null)
            sid_result=$(__get_sid "$web_api_pw")
            local status=$?

            if [ $status -eq 0 ] && [ -n "$sid_result" ]; then
                export X_FTL_SID="$sid_result"
                echo "✅ Authenticated! SID: $X_FTL_SID" >&2
                return 0
            fi

            # Se for 401, a password está errada. Não vale a pena tentar 5 vezes.
            if [ $status -eq 401 ]; then
                echo "❌ Error 401: Password mismatch. Check your keepass." >&2
                return 401
            fi

            # Caso contrário (Erro 145, Connection Refused, etc)
            echo "⚠️  Attempt $attempt/$max_attempts failed (Status: $status). Retrying in ${wait_time}s..." >&2
            sleep $wait_time
            ((attempt++))
        done

        echo "❌ Critical: Pi-hole API failed to respond after $max_attempts attempts." >&2
        return 1
    }
    api__password_(){
        local action="$1" # test(), password(disable|rotate|restore), auth()          
        action="${action##*(_)}"         
        action="${action%%*(_)}"
        shift
        local argsx=("$@") 

        __password__set_()  {
            local PIHOLE_API_PASSWORD="${1}"

            local res
            if res=$(require_containers_ready PIHOLE_CONTAINER_NAME); then
                # 2. Execução no container
                if docker exec pihole pihole setpassword "$PIHOLE_API_PASSWORD" ; then                                                   
                    echo "🔐 Pi-hole v6: Web Password updated" >&2                    
                    unset X_FTL_SID       
                    #show_vars PIHOLE_API_PASSWORD          
                    return 0
                fi
                echo "❌ Pi-hole: Failed to set pihole password." >&2
                return 1
            else
                echo "erro - $res" >&2
                return 1
            fi
        }
        _password__cleanup_() {
            core_secret_mem_delete  "pihole/WEB_API_PASSWORD"
        }
        _password__get_() {
            (
                if PROVIDER_SELECT="mem" core_secret_service_get "pihole/WEB_API_PASSWORD"; then
                    return 0
                else
                    if PROVIDER_SELECT="keepass" core_secret_service_get "pihole/WEB_API_PASSWORD"; then
                        #show_vars WEB_API_PASSWORD
                        PROVIDER_SELECT="mem" core_secret_service_put "pihole/WEB_API_PASSWORD" "$WEB_API_PASSWORD" 
                        return 0
                    fi
                    return 1        
                fi                        
            )                                  
        }
        _password__rotate_() {
            # 1. Geração local (silenciosa) || or nao ?
            kp test || return 1
            local NEW_PASS
            NEW_PASS=$(openssl rand -base64 24)
            echo "🔐 Pi-hole v6: Rotating Web Password..." >&2
            __password__set_ "$NEW_PASS" && (
                PROVIDER_SELECT="mem" core_secret_service_put "pihole/WEB_API_PASSWORD" "$NEW_PASS" 
                PROVIDER_SELECT="keepass" core_secret_service_put "pihole/WEB_API_PASSWORD" "$NEW_PASS" 
            )
        }
        _password__disable_() { 
            kp open || return 1
            echo "🔓 Pi-hole: Removing internal password for Authentik SSO..." >&2
            # No Pi-hole v6, uma string vazia remove a necessidade de login web
            __password__set_ "" || return 1
        }        
        _password__restore_() { 
            echo "🔓 Pi-hole: Resporing service secret..." >&2
            kp open && (
                if PROVIDER_SELECT="keepass" core_secret_service_get "pihole/WEB_API_PASSWORD"; then
                    __password__set_ "$WEB_API_PASSWORD"
                    PROVIDER_SELECT="mem" core_secret_service_put "pihole/WEB_API_PASSWORD" "$WEB_API_PASSWORD" 
                fi
            )
        }


        # ok it seams show_vars action
        if [[ -z "$action" ]]; then
            echo "Usage: $action ${argsx[@]} ..." >&2
            return 1
        fi
        echo "$action_handler ${argsx[@]}"
        __handler_run "_password__${action}_" "${argsx[@]}"   
    }
    api__dns_() {
        local action="$1" # get_records clear_records add remove
        action="${action##*(_)}"         
        action="${action%%*(_)}"
        shift
        local argsx=("$@")         
        
        if ! require_vars X_FTL_SID; then
            echo "🔐 Not authenticated" >&2
            api__auth_ || return 1
        fi

        _dns__get_records_() {
            # Capturamos o output da primeira função            
            local raw_json=$(
                local raw_json=$(curl -s -X GET "$PIHOLE_URL/api/config/dns/hosts" \
                    -H "sid: $X_FTL_SID")
                echo "$raw_json" | jq '.config.dns.hosts'   
            )
            
            # Processamos com jq e fazemos ECHO (não return)
            echo "$raw_json" | jq -r 'map(split(" ") | {address: .[0], host: .[1]})'
        }   
        _dns__clear_records_() {
            echo "🧹 A iniciar limpeza total via remoção individual..." >&2
            
            # 1. Carrega os hosts num array (lidando corretamente com quebras de linha)
            local records=()
            mapfile -t records < <(ph_api dns get_records | jq -r '.[] | .host')

            local total=${#records[@]}

            # 2. Verifica se o array está vazio
            if [[ $total -eq 0 ]]; then
                echo "✅ Pi-hole já está limpo."
                return 0
            fi

            echo "📦 Encontrados $total registos para remover." >&2

            # 3. Iteração sobre o array com contador
            local count=0
            for host in "${records[@]}"; do
                [[ -z "$host" ]] && continue
                ((count++))
                
                # Feedback visual de progresso [1/15]
                echo -n "[$count/$total] ♻️  A remover: $host... " >&2
                
                # Chamada da API
                if ph_api dns remove "$host" > /dev/null 2>&1; then
                    echo "✅" >&2
                else
                    echo "❌ Falhou" >&2
                fi
                
                # Pequena pausa para evitar estresse na API v6 (opcional)
                # sleep 0.05
            done
            
            echo "✨ Limpeza concluída com sucesso ($total registos)."
        }
        _dns__expected_records_() {
            local resolver_name="$PIHOLE_CONTAINER_NAME.$INTERNAL_DOMAIN"
            local resolver_ipv4="$(detect_active__ipv4)" 
            local resolver_ipv6="$(detect_active__ipv6)" 
            # Combine the Public Proxy-based records and the Direct Internal container records
            jq -n \
                --argjson public "$(core_desired_domain_names_json | jq -c .)" \
                --argjson internal "$(docker_app_network_json | jq -c  .)" \
                --arg h "$resolver_name" \
                --arg v4 "$resolver_ipv4" \
                --arg v6 "$resolver_ipv6" '
                    ($public + $internal + [{host: $h, address: $v4},{host: $h, address: $v6}])                     
                    | sort_by(.host)
                '
        }
        _dns__add_() {
            local ip="$1"
            local host="$2"
            local target_host="$host" # Para manter compatibilidade com seu echo

            if [[ -z "$ip" || -z "$host" ]]; then
                >&2 echo "❌ Error: IP and Hostname required."
                return 1
            fi

            # Encode seguro para a URL
            local encoded_entry=$(echo "${ip} ${host}" | sed 's/ /%20/g')

            # Captura HTTP Status e Body separadamente
            local tmp_body=$(mktemp)
            local http_status=$(curl -s -o "$tmp_body" -w "%{http_code}" -X PUT \
                "$PIHOLE_URL/api/config/dns/hosts/$encoded_entry" \
                -H "sid: $X_FTL_SID" \
                -H "Accept: application/json")

            local response=$(cat "$tmp_body")
            rm -f "$tmp_body"

            # Validação Cruzada: Aceita 200 (OK) ou 201 (Created)
            if [[ "$http_status" -ge 200 && "$http_status" -lt 300 ]]; then
                # Se for 201 e o corpo tiver o 'took', o FTL v6 processou corretamente
                if echo "$response" | jq -c -e '.' >&2; then
                    return 0
                fi
            fi

            # Se chegou aqui, algo falhou. Retornamos o erro para ser capturado pelo sync.
            >&2 echo "❌ HTTP $http_status | API: $response"
            return 1
        }


        _dns__remove_() {
            local target_host="$1"
            [[ -z "$target_host" ]] && return 1
            # 1. Procurar o registo exato (IP + HOST) para construir a URL
            local records=$(_dns__get_records_ | jq -r --arg h "$target_host" '.[] | select(.host == $h) | "\(.address) \(.host)"')

            if [[ -n "$records" ]]; then
                echo "$records" | while read -r entry; do
                    echo "🗑️  Removendo via URL: $entry"
                    
                    # 2. Encode rigoroso: o espaço deve ser %20
                    local encoded_entry=$(echo "$entry" | sed 's/ /%20/g')
                    
                    local resp=$(curl -s -X DELETE "${PIHOLE_URL}/api/config/dns/hosts/${encoded_entry}" \
                        -H "sid: $X_FTL_SID" \
                        -H "accept: application/json")

                    # 3. Validar se sumiu
                    if [[ $? -eq 0 ]]; then
                        echo "✅ Sucesso na remoção de $target_host"
                    else
                        echo "❌ Falha no curl para $target_host"
                    fi
                done
            else
                echo "ℹ️  Host $target_host não encontrado."
            fi
        }

        _dns__sync_() {        
            local expected_json=$(_dns__expected_records_)
            local asis_json=$(_dns__get_records_)
            local ipv4_host=$(detect_active__ipv4)
            local ipv6_host="$(detect_active__ipv6)"
            
            # --- 1. Cálculo de Diferenças (Lógica Preservada e Eficiente) ---
            
            # Identifica o que remover: está no Pi-hole mas não está no esperado (ou IP mudou)
            local need_remove_list=$(jq -n --argjson asis "$asis_json" --argjson exp "$expected_json" -r '
                $asis | map(select(. as $a | 
                    ($exp | any(.host == $a.host and .address == $a.address) | not)
                )) | .[] | "\(.host)|\(.address)"
            ')

            # Identifica o que adicionar: está no esperado mas não no Pi-hole (ou IP mudou)
            local need_new_list=$(jq -n --argjson asis "$asis_json" --argjson exp "$expected_json" -r '
                $exp | map(select(.address != "")) | map(select(. as $e | 
                    ($asis | any(.host == $e.host and .address == $e.address) | not)
                )) | .[] | "\(.host)|\(.address)"
            ')

            # --- 1. Remoções ---
            local -a remove_arr=()
            mapfile -t remove_arr <<< "$need_remove_list"
            if [[ ${#remove_arr[@]} -gt 0 && -n "${remove_arr[0]}" ]]; then
                echo "🧹 Limpando (${#remove_arr[@]}):"
                for record in "${remove_arr[@]}"; do
                    local host="${record%|*}"
                    # Executa em silêncio e mostra apenas o resultado compacto
                    local status
                    _dns__remove_ "$host" > /dev/null 2>&1 && \
                        echo "  - 🗑️  Removido: $host" || \
                        echo "  - ❌ Falha: $host"                    
                done
            fi

            # --- 2. Adições (Onde estava o ruído) ---
            local -a new_arr=()
            mapfile -t new_arr <<< "$need_new_list"
            if [[ ${#new_arr[@]} -gt 0 && -n "${new_arr[0]}" ]]; then
                echo "🚀 Sincronizando (${#new_arr[@]}):"
                for record in "${new_arr[@]}"; do
                    local host="${record%|*}"
                    local ip="${record#*|}"
                    
                    # Formatação compacta: Domínio -> IP [Status]
                    printf "  - ➕ %-35s -> %-15s " "$host" "$ip"
                    local status
                    #show_vars ip ipv4_host ipv6_host
                    if _dns__add_ "$ip" "$host"; then
                        echo "[OK]"
                    else
                        echo "[${status:-"FALHOU"}]"
                    fi
                done
            else
                echo "✨ Tudo atualizado."
            fi

        }

        #### ACTION arguments. what context nest am i?? ph api dns sync
        # ok it seams show_vars action
        if [[ -z "$action" ]]; then
            echo "Usage: $action ${argsx[@]} ..." >&2
            return 1
        fi
        echo "$action_handler ${argsx[@]}"
        __handler_run "_dns__${action}_" "${argsx[@]}"   
    } 
    
    ## handle api (password[restore|rotate|disable],auth) action         
    require_functions \
        api__dns_ \
        api__password_ \
        api__auth_ \
        api__open_ \
        api__close_|| return 1

    if [[ -z "$cmd" ]]; then
        echo "Usage: ph_api <cmd> <arg> ..." >&2
        return 1
    fi

    echo -n "ph api ${cmd} ${args[@]} => " >&2
    __handler_run "api__${cmd}_" "${args[@]}" 
}

##### OS integration
os_resolvers() {
    local cmd="$1" # get set
    cmd="${cmd##*(_)}"         
    cmd="${cmd%%*(_)}"
    shift
    local args=("$@") 

    if [[ -z "$cmd" ]]; then
        echo "Usage: os_resolver <cmd> <arg> ..." >&2
        return 1
    fi

    local os_resolv_file="/etc/resolv.conf"
    require_files os_resolv_file

    _get__nameservers_() {
        local resolvers=()

        # Verifica se o ficheiro existe
        if [[ ! -f "$os_resolv_file" ]]; then
            echo "⚠️  Warning: $os_resolv_file not found." >&2
            return 1
        fi

        # 1. Filtra linhas que começam com 'nameserver'
        # 2. Remove o prefixo 'nameserver '
        # 3. Remove comentários (depois de # ou ;) e espaços em branco
        # 4. Lê para o array
        while read -r ip; do
            if [[ -n "$ip" ]]; then
                resolvers+=("$ip")
            fi
        done < <(grep '^nameserver' "$os_resolv_file" | awk '{print $2}' | sed 's/[#;].*//' | xargs)

        # Se o array estiver vazio, algo está errado na config do OS
        if [[ ${#resolvers[@]} -eq 0 ]]; then
            echo "❌ No valid nameservers found in $os_resolv_file" >&2
            return 1
        fi

        # Exporta ou imprime conforme a sua necessidade de uso
        # Para scripts: echo "${resolvers[@]}"
        # Para uso interno: declare -g NAMESERVER_ARRAY=("${resolvers[@]}")
        echo "${resolvers[@]}"
    }

    _set__nameservers_() {
        local os_resolv_file="/etc/resolv.conf"
        local backup_file="$os_resolv_file.bak"
        
        if [[ $# -eq 0 ]]; then
            echo "❌ Error: No resolvers provided." >&2
            return 1
        fi

        # 1. Backup e Preparação
        sudo cp "$os_resolv_file" "$backup_file" 2>/dev/null || true
        local temp_resolv=$(mktemp)

        # 2. Construir o novo conteúdo
        # Preservar options e search, remover nameservers antigos
        grep -E '^search|^options' "$os_resolv_file" 2>/dev/null > "$temp_resolv" || true
        
        for ip in "$@"; do
            local clean_ip=$(echo "$ip" | sed 's/[^0-9.]//g') # Extrai apenas o IP
            if [[ -n "$clean_ip" ]]; then
                echo "nameserver $clean_ip" >> "$temp_resolv"
            fi
        done

        # 3. Takeover Total
        echo "🛡️ Locking down $os_resolv_file..." >&2
        
        # Se for link, quebra o link para virar arquivo real
        [[ -L "$os_resolv_file" ]] && sudo rm "$os_resolv_file"
        
        # Tenta remover o atributo caso já exista
        sudo chattr -i "$os_resolv_file" 2>/dev/null || true
        
        # Escrita atômica
        cat "$temp_resolv" | sudo tee "$os_resolv_file" > /dev/null
        
        # Bloqueio final Imutável
        sudo chattr +i "$os_resolv_file"
        
        rm -f "$temp_resolv"

        echo "✅ Success. Current state:"
        grep '^nameserver' "$os_resolv_file" | sed 's/^/   -> /'
    }

        ## handle api (password[restore|rotate|disable],auth) action         
    require_functions \
        _get__nameservers_ \
        _set__nameservers_ || return 1

    #echo "ph_api __handler_run api__${cmd}_" "${args[@]}" 
    __handler_run "_${cmd}__nameservers_" "${args[@]}" 
}


ph() {
    local cmd="$1" # test(), password(disable|rotate|restore), auth()
    cmd="${cmd##*(_)}"         
    cmd="${cmd%%*(_)}"
    shift
    local args=("$@") 
    

    # 1. Captura o STDIN (pipe) para um array, se existir
    local pipe_values=()
    if [[ ! -t 0 ]]; then
        mapfile -t pipe_values
    fi

    inst__reboot_() {
        (
            cd $PIHOLE_DIR            
            inst__down_ && inst__up_
        )
    }

    inst__down_() {
        (
            cd $PIHOLE_DIR            
            docker compose down --remove-orphans             
            get_ftl__real_PID 
            ps -ax | grep pihole-FTL
            kill $(get_ftl__real_PID)
            inst__disable_          
        )
    }

    inst__up_() {
        (
            cd $PIHOLE_DIR            
            #docker_container_kill_ip "$PIHOLE_DNS_IP"
            docker compose up -d
            inst__enable_
        )
    }

    inst__enable_() {
        libvirt_dns_default__ip() {
            # Verifica se o comando 'virsh' está disponível
            if ! command -v virsh &> /dev/null; then
                return 1
            fi

            # Extrai o IP da rede padrão
            local ip
            ip=$(sudo virsh net-dumpxml default 2>/dev/null | grep -oP "(?<=<ip address=[\"'])[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+")

            # Verifica se o IP foi encontrado
            if [[ -z "$ip" ]]; then
                return 1
            fi

            # Retorna o IP
            echo "$ip"
            return 0
        }
        # 1. Obter resolvers atuais como um array
        # Usamos parênteses para forçar a saída num array bash
        local dns_ip=$(libvirt_dns_default__ip)
        ###local unbound_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' unbound)
        local cur_resolvers=($(os_resolvers get))
        
        # 2. Lógica de Verificação:
        # Condição A: O primeiro resolver NÃO é o IP do Pi-hole
        # Condição B: Existe mais do que um resolver (queremos exclusividade)
        if [[ "${cur_resolvers[0]}" != "$dns_ip" ]] || [[ ${#cur_resolvers[@]} -ne 1 ]]; then
            echo "Updating system resolvers to point exclusively to ip ($dns_ip)..."
            os_resolvers set "$dns_ip"
        else
            echo "✅ System resolvers are already optimized: ${cur_resolvers[0]}"
        fi       
    }

    inst__disable_() {
         ### enable external system dns resolve        
        os_resolvers set "${PIHOLE_SPARK_DNS[@]}"
    }

    inst__health___replace_for_other_more_informed_entity() {
        _validate_docker_resolver_ip() {
            local _RRIP="$1"   # ref resolver ip
            local _RIP="${!_RRIP}" # resolver ip
            local daemon_file="/etc/docker/daemon.json"

            #require_files daemon_file
            #how_vars _RRIP _RIP daemon_file
            # Verifica se o arquivo existe e pode ser lido
            if [ ! -r "$daemon_file" ]; then
                >&2 echo "❌ Error: Cannot read $daemon_file. Check permissions or if file exists."
                return 1
            fi

            # Simplificação do jq:
            # any(.dns[]; . == $ip) verifica se qualquer elemento do array .dns é igual a $ip
            if jq -e --arg ip "$PIHOLE_DNS_IP" 'any(.dns[]; . == $ip)' "$daemon_file" > /dev/null 2>&1; then
                return 0
            else
                >&2 echo "❌ Error: PIHOLE_DNS_IP ($PIHOLE_DNS_IP) not found in $daemon_file dns list."
                return 1
            fi
        }
        _validate_podman_resolver_ip() {
            local _RRIP="$1"   # ref resolver ip
            local _RIP="${!_RRIP}" # resolver ip
            local resolv_conf="/etc/resolv.conf"

            # Verifica se o arquivo existe e pode ser lido
            if [ ! -r "$resolv_conf" ]; then
                >&2 echo "❌ Error: Cannot read $resolv_conf. Check permissions or if file exists."
                return 1
            fi

            # Verifica se o IP do resolvedor está presente no /etc/resolv.conf
            if grep -q "nameserver $_RIP" "$resolv_conf"; then
                return 0
            else
                >&2 echo "❌ Error: PIHOLE_DNS_IP ($_RIP) not found in $resolv_conf nameserver list."
                return 1
            fi
        }        
        local oci_provider=$(container_provider)
        
        DEBUG=false require_containers_ready PIHOLE_CONTAINER_NAME || return 1
        #inst__api_ auth || return 2
        ##### OS INTEGRATION
        local cur_resolvers=($(os_resolvers get))
        if [[ ${#cur_resolvers[@]} -eq 1 ]] && [[  "${cur_resolvers[0]}" == "$PIHOLE_DNS_IP" ]] ; then
            echo "✔ pihole $PIHOLE_DNS_IP is set as host dns resolver" >&2
        else
            echo "WARN: pihole $PIHOLE_DNS_IP is not the host dns resolver" >&2
        fi 

        ##### DOCKER INTEGRATION
        if _validate_${oci_provider}_resolver_ip PIHOLE_DNS_IP; then
            echo "✔ pihole $PIHOLE_DNS_IP is set as docker dns resolver" >&2
        else
            echo "WARN: pihole $PIHOLE_DNS_IP is not the docker dns resolver" >&2
        fi 
        
        ##### END INTEGRATION


        # 3. Check do KeePass (kp)
        local terror
        if ! terror=$(kp test 2>&1); then
            echo "❌ Error (KeePass): $terror" >&2
            return 1
        fi
        echo "✔ KeePass: PASS" >&2

        # 4. Check da API do Pi-hole (ph api auth)
        local api_error
      
        # Capturamos a saída e verificamos o exit code simultaneamente
        if api_error=$(ph api auth 2>&1); then
            echo "✔ API: Authenticated" >&2
            return 0
        else
            echo "❌ Error (Pi-hole API): $api_error" >&2
            return 1
        fi

        
    }

    inst__provider_() {
        _validate_resolver_ip() {
            local resolver_file="$1"  # Caminho do arquivo de configuração
            local resolver_ip="$2"    # IP do resolvedor
            local method="$3"         # Método de validação (jq ou grep)

            if [ ! -r "$resolver_file" ]; then
                >&2 echo "❌ Error: Cannot read $resolver_file. Check permissions or if file exists."
                return 1
            fi

            case "$method" in
                jq)
                    if jq -e --arg ip "$resolver_ip" 'any(.dns[]; . == $ip)' "$resolver_file" > /dev/null 2>&1; then
                        return 0
                    else
                        >&2 echo "❌ Error: Resolver IP ($resolver_ip) not found in $resolver_file dns list."
                        return 1
                    fi
                    ;;
                grep)
                    if grep -q "nameserver $resolver_ip" "$resolver_file"; then
                        return 0
                    else
                        >&2 echo "❌ Error: Resolver IP ($resolver_ip) not found in $resolver_file nameserver list."
                        return 1
                    fi
                    ;;
                *)
                    >&2 echo "❌ Error: Unsupported validation method ($method)."
                    return 1
                    ;;
            esac
        }

        
        # Detecta o provedor de contêineres
        local oci_provider=$(container_provider)
        if [ "$oci_provider" == "unsupported" ]; then
            >&2 echo "❌ Error: Unsupported container provider detected."
            return 1
        fi

        ##### OCI PROVIDER INTEGRATION. I know is not module oriented yet, is case oriented with my convertion study.
        case "$oci_provider" in
            docker)
                if _validate_resolver_ip "/etc/docker/daemon.json" "$PIHOLE_DNS_IP" "jq"; then
                    echo "✔ pihole $PIHOLE_DNS_IP is set as docker dns resolver" >&2
                else
                    echo "WARN: pihole $PIHOLE_DNS_IP is not the docker dns resolver" >&2
                fi
                ;;
            podman)
                if _validate_resolver_ip "/etc/resolv.conf" "$PIHOLE_DNS_IP" "grep"; then
                    echo "✔ pihole $PIHOLE_DNS_IP is set as podman dns resolver" >&2
                else
                    echo "WARN: pihole $PIHOLE_DNS_IP is not the podman dns resolver" >&2
                fi
                ;;
            *)
                >&2 echo "❌ Error: Unsupported OCI provider ($oci_provider)."
                return 1
                ;;
        esac
    }

    inst__health_() {
        # Função genérica para validar o resolvedor DNS
        
        # Verifica se os contêineres estão prontos
        DEBUG=false require_containers_ready PIHOLE_CONTAINER_NAME || {
            >&2 echo "❌ Error: Required containers are not ready."
            return 1
        }

        ##### OS INTEGRATION
        local cur_resolvers=($(os_resolvers get))
        if [[ ${#cur_resolvers[@]} -eq 1 ]] && [[ "${cur_resolvers[0]}" == "$PIHOLE_DNS_IP" ]]; then
            echo "✔ pihole $PIHOLE_DNS_IP is set as host dns resolver" >&2
        else
            echo "WARN: pihole $PIHOLE_DNS_IP is not the host dns resolver" >&2
        fi


        ##### END INTEGRATION

        # 3. Check do KeePass (kp)
        local terror
        if ! terror=$(kp test 2>&1); then
            echo "❌ Error (KeePass): $terror" >&2
            return 1
        fi
        echo "✔ KeePass: PASS" >&2

        # 4. Check da API do Pi-hole (ph api auth)
        local api_error
        if api_error=$(ph api auth 2>&1); then
            echo "✔ API: Authenticated" >&2
            return 0
        else
            echo "❌ Error (Pi-hole API): $api_error" >&2
            return 1
        fi
    }

    inst__api_() {
        local action="$1" # test(), password(disable|rotate|restore), auth()          
        shift
        local argsx=("$@") 

        if [[ -z "$action" ]]; then
            echo "Usage: api ${argsx[@]} ..." >&2
            return 1
        fi
        ph_api "${action}" "${argsx[@]}"       
    }

    # seams to works root full, not root less
    inst__renice_() {
        local _PID
        if _PID=$(get_ftl__real_PID "pihole-FTL"); then
            echo "FTL PID: $_PID"
            
            # Tenta com sudo (rootful) ou sem (rootless)
            if command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
                sudo renice -n -10 -p "$_PID" 2>/dev/null || \
                    echo "⚠️  renice falhou mesmo com sudo (rootless?)"
            else
                renice -n -10 -p "$_PID" 2>/dev/null || \
                    echo "⚠️  renice falhou - CAP_SYS_NICE necessário"
            fi
            
            # Mostra o nice atual
            ps -o pid,ni,comm -p "$_PID" 2>/dev/null
        else
            echo "❌ pihole-FTL não encontrado"
            return 1
        fi
    }
    require_functions \
        inst__health_ \
        inst__enable_ \
        inst__disable_ \
        inst__reboot_ \
        inst__up_ \
        inst__renice_ \
        inst__api_ \
        inst__down_ || return 1

    if [[ -z "$cmd" ]]; then
        echo "Usage: ph <cmd> <arg> ..." >&2
        return 1
    fi

    #echo "ph_api __handler_run api__${cmd}_" "${args[@]}" 
    __handler_run "inst__${cmd}_" "${args[@]}" 
}

ph_test() {
    local traefik_ip="$(docker_app_network_proxy_ip)"
    local _DIR_NAME="backup"

    # usage test test 
    if ph_api auth; then
        echo "Session Active."
        # Corrected: Adding the IP addresses
        #ph_api dns add "$traefik_ip" "$_DIR_NAME.local"
        #ph_clear_dns_records
        ph_pi dns get_records 
        ph_api logout
    else
        echo "Failed to prepare Pi-hole session."
        return 1
    fi
}



container_provider() {
    local provider="unknown"
    local exit_code=0

    # Verifica se o Docker está instalado e em execução (não um alias para Podman)
    if command -v docker >/dev/null 2>&1 && ! alias docker >/dev/null 2>&1; then
        provider="docker"        
        exit_code=0
    # Verifica se o Podman está instalado e em execução
    elif command -v podman >/dev/null 2>&1 && ! alias podman >/dev/null 2>&1; then
        provider="podman"
        exit_code=0
    else
        # Caso nenhum provedor conhecido seja detectado
        provider="unsupported"
        return 1
    fi

    if $provider info | grep "$provider" >/dev/null 2>&1; then
        echo "Detected container provider: $provider" >&2
        echo $provider
        return $exit_code
    fi
    
    return 1
}
ph_os_integration() {    
    container_provider || return 1

    #    install_chrony_if_not_present_ || return 1
   
    os_ntp_sync || return 1
    ph disable || return 1
    ph enable || return 1    
}


install_chrony_if_not_present_() {
    # Verifica se chrony já está instalado
    if ! command -v chronyd >/dev/null; then
        echo "chrony is not installed. Proceeding with installation..."

        # Detecta o gerenciador de pacotes e instala chrony
        if command -v apt >/dev/null; then
            echo "Using apt to install chrony..."
            if ! apt install chrony -y 2>/dev/null; then
                echo "Failed to install chrony using apt. Superuser privileges may be required."
                echo "Please run the following commands manually:"
                echo "  sudo apt install chrony"
                return 1
            fi
        elif command -v dnf >/dev/null; then
            echo "Using dnf to install chrony..."
            if ! dnf install chrony -y 2>/dev/null; then
                echo "Failed to install chrony using dnf. Superuser privileges may be required."
                echo "Please run the following commands manually:"
                echo "  sudo dnf install chrony"
                return 1
            fi
        elif command -v pacman >/dev/null; then
            echo "Using pacman to install chrony..."
            if ! pacman -S chrony --noconfirm 2>/dev/null; then
                echo "Failed to install chrony using pacman. Superuser privileges may be required."
                echo "Please run the following commands manually:"
                echo "  sudo pacman -S chrony"
                return 1
            fi
        elif command -v zypper >/dev/null; then
            echo "Using zypper to install chrony..."
            if ! zypper install chrony -y 2>/dev/null; then
                echo "Failed to install chrony using zypper. Superuser privileges may be required."
                echo "Please run the following commands manually:"
                echo "  sudo zypper install chrony"
                return 1
            fi
        else
            echo "Package manager not found. Please install chrony manually."
            return 1
        fi

        echo "chrony installed successfully."
    else
        echo "chrony is already installed. Skipping installation."
    fi

    # Verifica se o serviço chronyd está habilitado e iniciado
    if ! systemctl is-enabled chronyd >/dev/null 2>&1; then
        echo "Enabling chronyd service..."
        if ! systemctl enable chronyd 2>/dev/null; then
            echo "Failed to enable chronyd. Superuser privileges may be required."
            echo "Please run the following command manually:"
            echo "  sudo systemctl enable chronyd"
            return 1
        fi
    fi

    if ! systemctl is-active chronyd >/dev/null 2>&1; then
        echo "Starting chronyd service..."
        if ! systemctl start chronyd 2>/dev/null; then
            echo "Failed to start chronyd. Superuser privileges may be required."
            echo "Please run the following command manually:"
            echo "  sudo systemctl start chronyd"
            return 1
        fi
    fi

    echo "chrony is installed, enabled, and running successfully."
    return 0
}
## integration of NTP sync (for a user (1000), running rootless pods in sync). 
## very IMPORTANT to dns DATA generation/*DATA TIME nature rules. 
os_ntp_sync() {
    # Verifica se o Docker está em modo rootless
    # Verifica se o sistema já está sincronizado via NTP
    if command -v timedatectl >/dev/null && timedatectl show | grep -q "NTPSynchronized=yes"; then
        echo "Host clock is already synchronized via NTP."
        return 0
    fi

    # Tenta habilitar NTP sem sudo, se possível
    if command -v timedatectl >/dev/null; then
        if timedatectl set-ntp true 2>/dev/null; then
            echo "NTP synchronization enabled successfully."
            return 0
        else
            echo "Failed to enable NTP synchronization. Superuser privileges may be required."
        fi
    fi

}

get_ftl__real_PID() {
    local name="${1:-pihole-FTL}"  # The name of the process to search for (e.g., "pihole-FTL")
    
    # Use pgrep to find the PID of the actual process (not the grep or shell wrapper)
    local real_pid=$(pgrep -f "/usr/bin/${name} no-daemon" | tail -n 1)

    # Check if a PID was found
    if [ -n "$real_pid" ]; then
        echo "$real_pid"
        return 0
    else
        echo "Error: No running process found for '$name'." >&2
        return 1
    fi
}

ph_sort_weights() {
    local rules_json
    rules_json=$(cat <<-'EOF'
[
  {
    "prefix": "os_*|*nameservers*",    
    "weight": 10,
    "cat": "PIHOLE-OS-INTEGRATION"
  },
  {
    "prefix": "ph_api|api__*|*dns*|*password*|*auth*|*sid",    
    "weight": 12,
    "cat": "PIHOLE-API-MANAGEMENT"
  },
  {
    "prefix": "*_catalog|*_sort_weights",
    "weight": 14,
    "cat": "PIHOLE-CATALOG"
  },
  {
    "prefix": "ph|inst__*|*enable*|*disable*|*reboot*|*up*|*down*|*health*|*docker*",
    "weight": 15,
    "cat": "PIHOLE-CLI"
  },  
  
  {
    "prefix": ".",
    "refine": "",
    "weight": 90,
    "cat": "MISC"
  }
]
EOF
)
    echo "$rules_json" | jq -c '
        map(. + {refine: (.refine // "")}) 
        | sort_by(.weight, .prefix) 
    '
}

ph_fn_catalog() {
    core_fn_catalog "${BASH_SOURCE[0]}" "ph_sort_weights" 
}

container_provider_json() {
    local provider="unknown"
    local socket_path=""
    local socket_type="unknown"
    local mode="unknown"
    local docker_host="${DOCKER_HOST:-not set}"
    local caps_nice_works=false
    local sock_accessible=false
    
    # Processa DOCKER_HOST
    if [[ -n "$DOCKER_HOST" ]]; then
        socket_path="${DOCKER_HOST#unix://}"
        socket_path="${socket_path#tcp://}"
        socket_path="${socket_path#ssh://}"
        socket_path="${socket_path#http://}"
        socket_path="${socket_path#https://}"
        socket_path="${socket_path%%\?*}"
        
        if [[ "$DOCKER_HOST" == unix://* ]]; then
            socket_type="unix"
            if [[ -S "$socket_path" ]]; then
                sock_accessible=true
                
                # ⭐ PRIMEIRO: Detecta provider pelo PATH do socket
                case "$socket_path" in
                    *podman*) provider="podman" ;;
                    *docker*) provider="docker" ;;
                esac
                
                # ⭐ SEGUNDO: Confirma via API (opcional, só refina)
                local info_json
                if info_json=$(curl -s --max-time 2 --unix-socket "$socket_path" http://v1.41/info 2>/dev/null); then
                    if echo "$info_json" | grep -qi podman; then
                        provider="podman"
                    elif echo "$info_json" | grep -qi docker; then
                        # Só muda para docker se NÃO for socket podman
                        [[ "$socket_path" != *podman* ]] && provider="docker"
                    fi
                fi
            fi
        elif [[ "$DOCKER_HOST" == tcp://* ]] || [[ "$DOCKER_HOST" == ssh://* ]]; then
            socket_type="remote"
            provider="remote"
        fi
    else
        docker_host="not set"
        # ⭐ Detecta sockets padrão - prioridade ao socket real
        if [[ -S "/run/user/${UID}/podman/podman.sock" ]]; then
            socket_path="/run/user/${UID}/podman/podman.sock"
            socket_type="unix"
            provider="podman"
            sock_accessible=true
        elif [[ -S "/run/podman/podman.sock" ]]; then
            socket_path="/run/podman/podman.sock"
            socket_type="unix"
            provider="podman"
            sock_accessible=true
        elif [[ -S "/var/run/docker.sock" ]]; then
            socket_path="/var/run/docker.sock"
            socket_type="unix"
            provider="docker"
            sock_accessible=true
        fi
    fi
    
    # ⭐ Detecta modo baseado no SOCKET primeiro!
    if [[ "$socket_path" == /run/user/* ]]; then
        mode="rootless"
    elif [[ "$socket_path" == /run/podman/* ]] && [[ "$socket_path" != /run/user/* ]]; then
        mode="rootful"
    elif [[ "$provider" == "podman" ]] && command -v podman &>/dev/null; then
        # Fallback para podman info
        if podman info 2>/dev/null | grep -qi "rootless: true"; then
            mode="rootless"
        else
            mode="rootful"
        fi
    elif [[ "$provider" == "docker" ]]; then
        mode="rootful"
    elif [[ "$provider" == "remote" ]]; then
        mode="remote"
    fi
    
    # Determina CAP_SYS_NICE
    case "$provider:$mode" in
        podman:rootless) caps_nice_works=false ;;
        podman:rootful)  caps_nice_works=true ;;
        docker:*)        caps_nice_works=true ;;
        remote:*)        caps_nice_works=true ;;
        *)               caps_nice_works=false ;;
    esac
    
    # ⭐ Detecta que comando o utilizador está realmente a usar
    local user_command=""
    local alias_info=""
    
    if alias docker 2>/dev/null | grep -q podman; then
        alias_info="docker→podman"
        user_command="podman (via docker alias)"
    elif command -v docker &>/dev/null; then
        user_command="docker"
    elif command -v podman &>/dev/null; then
        user_command="podman"
    fi
    
    # Constrói JSON
    jq -n \
        --arg provider "$provider" \
        --arg user_command "$user_command" \
        --arg alias_info "$alias_info" \
        --arg docker_host "$docker_host" \
        --arg socket_path "$socket_path" \
        --arg socket_type "$socket_type" \
        --arg mode "$mode" \
        --argjson sock_accessible "$sock_accessible" \
        --argjson caps_nice_works "$caps_nice_works" \
        '{
            provider: $provider,
            user_command: $user_command,
            aliases: $alias_info,
            docker_host: $docker_host,
            socket: {
                path: $socket_path,
                type: $socket_type,
                accessible: $sock_accessible
            },
            mode: $mode,
            capabilities: {
                CAP_SYS_NICE_works: $caps_nice_works
            }
        }'
}
print_json___ident_bash_style() {
    local json_input="$1"

    [ -z "$json_input" ] && json_input=$(cat)

    echo "$json_input" | jq -r '
        def flatten(prefix):
            to_entries[] |
            if .value | type == "object" then
                # Constrói o novo prefixo com o nome do campo atual
                (. as $parent | .value | flatten(if prefix == "" then $parent.key else prefix + "." + $parent.key end))
            elif .value | type == "array" then
                (. as $parent | .value | to_entries[] |
                flatten(if prefix == "" then ($parent.key + "[" + (.key | tostring) + "]") else prefix + "." + $parent.key + "[" + (.key | tostring) + "]" end))
            else
                "\(if prefix == "" then .key else prefix + "." + .key end)=\(.value | tostring | @sh)"
            end
        ;
        
        flatten("")
    ' | while IFS='=' read -r path value; do
        indent_level=$(echo "$path" | tr -cd '.' | wc -c)
        indent_spaces=$((indent_level * 2))
        printf "%${indent_spaces}s%s=%s\n" "" "$path" "$value"
    done
}
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    #stack_trace
    echo ""
    #container_provider_json | print_json___ident_bash_style
    echo ""
    #ph health
    #ph api open

fi