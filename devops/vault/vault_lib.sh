#!/bin/bash
# Filename: ../../devops/vault/./_0.vault_lib.sh

set +e

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ This is a library and should be sourced, not run directly."  2>&1
    echo "     Try: source ./$(realpath --relative-to="$PWD" "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
    return 1 2> /dev/null || exit 1
fi

_dir="$(dirname "${BASH_SOURCE[0]}")"
## vault lib dependency on keepass wrapper....also ../core.sh witch source ../.env
source  "$_dir/keepass.sh" > /dev/null 2>&1



vault_config_requirements() {
    export VAULT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    export VAULT_DIR_NAME=$(basename $VAULT_DIR)
    export VAULT_CONTAINER_NAME="vault"
    export VAULT_CONTAINER_IP="172.28.0.6"

    export VAULT_PKI_CN="${VAULT_PKI_CN,-"home2500.local"}"
    export VAULT_ROOT_CA_NAME="${VAULT_ROOT_CA_NAME,"root-home2500"}"


    require_functions require_vars require_files
    require_vars DEVOPS_DIR && require_locations DEVOPS_DIR
    require_vars MEM_ROOT_DIR && require_locations MEM_ROOT_DIR

    local CONFIG_FILE="$VAULT_DIR/config/vault-active.hcl"

    require_files CONFIG_FILE 2>&1 || {
        echo "❌ Erro: Configuração não encontrada em $CONFIG_FILE"  2>&1
        return 1
    }

    # Extração de variáveis
    export VAULT_ADDR=$(yq -oy '.api_addr' "$CONFIG_FILE" 2>/dev/null || echo "http://127.0.0.1:8200")
    export VAULT_SERVICE_PORT=$(extract_url_port $VAULT_ADDR)
    export VAULT_INTERNAL_NS="$VAULT_DIR_NAME.$INTERNAL_DOMAIN"
    export VAULT_NS="$VAULT_DIR_NAME.$DOMAIN"

    # Lógica de TLS (Chain de confiança)
    require_vars TRUSTED_CA_FILE
    
    # Se o endereço for HTTP, ignoramos qualquer lógica de CA
    if [[ "$VAULT_ADDR" == "http://"* ]]; then
        unset VAULT_CACERT
        export CURL_CA_OPTS=""
        echo "⚠️  Vault em modo HTTP (Insecure for setup)."  2>&1
    else
        # Se for HTTPS, verificamos se temos a Chain de CA
        if [ -f "$TRUSTED_CA_FILE" ]; then
            export VAULT_CACERT="$TRUSTED_CA_FILE"
            export CURL_CA_OPTS="--cacert $VAULT_CACERT"
            echo "🔒 TLS Ativo: Usando CA Chain."  2>&1
            #openssl crl2pkcs7 -nocrl -certfile "$TRUSTED_CA_FILE" | openssl pkcs7 -print_certs -noout
        else
            unset VAULT_CACERT
            export CURL_CA_OPTS="--insecure"
            echo "🔐 TLS Ativo: Modo Insecure (CA não encontrada)."  2>&1
        fi
    fi
}

# --- HELPERS ---
# --- DEFINIÇÃO DAS FUNÇÕES (Para evitar 'command not found') ---
vault_get_secret() {
    local secret_name="$1"
    local field="$2"
    DEBUG=false require_vars secret_name field || return 1
    echo "🔍 Vault: fetching field '$field' from '$secret_name'..." >&2
    (
        PROVIDER_SELECT="mem" core_secret_service_get "vault/VAULT_TOKEN" 2> /dev/null 
        require_vars VAULT_TOKEN || return 1
        echo "$(vault kv get -mount=secret -field="$field" "$secret_name")"
    )
}

vault_save_secret() {
    local secret_name="$1"
    local field="$2"
    local value="$3"

    echo "🔒 vault save '$field' in '$secret_name'..." 2>&1
    require_vars secret_name field value || {
        stack_trace
        return 1
    }

    (
        PROVIDER_SELECT="mem" core_secret_service_get "vault/VAULT_TOKEN" 2> /dev/null 
        require_vars VAULT_TOKEN || return 1
        # 1. Tenta o PATCH (assume que o segredo existe)
        # Usamos -mount=secret para encurtar o path e evitar 403 de descoberta
        if ! vault kv patch -mount=secret "$secret_name" "$field=$value" > /dev/null 2>&1; then
            echo "ℹ️ Path '$secret_name' not found or empty. Creating initial version..." 2>&1
            
            # 2. Se o PATCH falhar (404), usamos PUT para criar o segredo
            vault kv put -mount=secret "$secret_name" "$field=$value" > /dev/null
        fi
    )
}
vault_delete_secret() {
    local secret_name="$1"
    # O field não é estritamente necessário para delete no KV, 
    # pois o Vault deleta a versão do objeto (path) inteiro.
    
    DEBUG=false require_vars secret_name || return 1
    
    echo "🗑️ Vault: soft-deleting version at '$secret_name'..." >&2
    (
        # Recupera o token de forma isolada
        PROVIDER_SELECT="mem" core_secret_service_get "vault/VAULT_TOKEN" 2> /dev/null 
        require_vars VAULT_TOKEN || { echo "❌ Vault: Token não disponível." >&2; return 1; }

        # Executa o Soft Delete (apenas a versão mais recente)
        if vault kv delete -mount=secret "$secret_name" > /dev/null 2>&1; then
            return 0
        else
            echo "⚠️ Vault: Falha ao deletar '$secret_name' (pode não existir)." >&2
            return 1
        fi
    )
}

vault_secret_path_caps () {
    local secret_path=${1:-"secret/"}    
    require_vars secret_path || return 1
    (
        PROVIDER_SELECT="mem" core_secret_service_get "vault/VAULT_TOKEN" 2> /dev/null 
        require_vars VAULT_TOKEN || return 1
        
        # Verificamos o path de dados e o path de sistema (onde ocorre o 403)
        local CAPS=$(vault token capabilities "$secret_path")    
        echo "   - [$secret_path] : $CAPS" 2>&1    
    ) || return 1    
}
is_sealed() {
    local status
    # Usamos -k (CURL_CA_OPTS) e garantimos que o status captura tudo
    local curl_opts="-s"
    [[ "$VAULT_SKIP_VERIFY" == "true" ]] && curl_opts="$curl_opts -k"

    status=$(curl $curl_opts --connect-timeout 2 "$VAULT_ADDR/v1/sys/health" 2>/dev/null)

    # Se o curl falhou, status está vazio
    if [[ -z "$status" ]]; then
        echo "⚠️  [VAULT] No response. Assuming sealed." >&2
        return 0
    fi

    # Forçamos o jq a interpretar como booleano e depois comparamos
    local sealed_val
    sealed_val=$(echo "$status" | jq -r '.sealed')

    if [[ "$sealed_val" == "false" ]]; then
        # echo "🔓 [VAULT] Cofre aberto." >&2
        return 1 # Não está selado
    fi

    echo "🔒 [VAULT] Cofre selado." >&2
    return 0 # Está selado
}
is_initialized() {
    # Necessário para garantir que o Vault está a responder
    local health_url="${VAULT_ADDR}/v1/sys/health"

    # Faz o curl ignorando o certificado se VAULT_SKIP_VERIFY estiver true
    local curl_opts="-s"
    [[ "$VAULT_SKIP_VERIFY" == "true" ]] && curl_opts="$curl_opts -k"

    local response
    response=$(curl $curl_opts "$health_url")
    local status=$?

    if [[ $status -ne 0 ]]; then
        echo "❌ ERRO: Não foi possível conectar ao Vault em ${VAULT_ADDR}" >&2
        return 1
    fi

    # Extrai o valor de 'initialized' usando jq
    local initialized
    initialized=$(echo "$response" | jq -r '.initialized')

    if [[ "$initialized" == "true" ]]; then
        #echo "initializada, accessivel ${VAULT_ADDR}" >&2
        return 0 # Está inicializado
    else
        echo "❌ ERRO: Não está initializada, ou nao foi possível conectar ao Vault em ${VAULT_ADDR}" >&2
        return 1 # Não inicializado ou em erro
    fi
}
# Função exemplo fazer GET na API do Vault usando o Token atual
vault_curl_get() {
    local endpoint="$1" # Ex: /v1/sys/health ou /v1/auth/oidc/config    
    (
        PROVIDER_SELECT="mem" core_secret_service_get "vault/VAULT_TOKEN" 2> /dev/null 
        require_vars VAULT_TOKEN || return 1
        curl -s $CURL_CA_OPTS \
            -H "X-Vault-Token: $VAULT_TOKEN" \
            "$VAULT_ADDR/$endpoint" | jq .
    )
}

# Função exemplo para fazer POST/WRITE na API do Vault
vault_curl_post() {
    local endpoint="$1"
    local data="$2" # JSON string
    
    require_vars endpoint data || return 1
    (
        PROVIDER_SELECT="mem" core_secret_service_get "vault/VAULT_TOKEN" 2> /dev/null 
        require_vars VAULT_TOKEN || return 1
        curl -s $CURL_CA_OPTS -X POST \
            -H "X-Vault-Token: $VAULT_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$data" \
            "$VAULT_ADDR/$endpoint" | jq .
    )
}

vault_config() {
    require_vars DEVOPS_DIR_NAME DEVOPS_DIR VAULT_ADDR VAULT_CACERT CURL_CA_OPTS

    echo "📂 Project Root ($DEVOPS_DIR_NAME): $DEVOPS_DIR"  2>&1
    echo "🔗  VAULT_ADDR: $VAULT_ADDR"  2>&1
    echo "🛡️  VAULT_CACERT: $VAULT_CACERT"  2>&1
    echo "🛡️  CURL_CA_OPTS: $CURL_CA_OPTS"  2>&1
}
export -f vault_config

vault_unseal() {    
    # Lazy Loading
    echo "🔓 Unsealing: ($VAULT_CONTAINER_NAME) $VAULT_ADDR "  
    (    
        kp open
        PROVIDER_SELECT="keepass" core_secret_service_get "root/UNSEAL_KEY" 
        if ! require_vars UNSEAL_KEY; then return 1; fi

        echo "🔓 Unsealing: $VAULT_ADDR, path: root/UNSEAL_KEY, key: ${UNSEAL_KEY:0:2}" >&2
        local resp=$(docker exec -e VAULT_ADDR="$VAULT_ADDR" -i $VAULT_CONTAINER_NAME vault operator unseal "$UNSEAL_KEY")
        #local resp=$(docker exec $VAULT_CONTAINER_NAME vault operator unseal "$UNSEAL_KEY")

        if echo "$resp" | grep -q "Sealed.*false"; then
            echo "✅ Vault unsealed successfully" >&2
            return 0
        else
            echo "❌ Failed to unseal Vault" >&2
            echo "$resp" >&2
            return 1
        fi
    ) 
}
export -f vault_unseal

vault_stewards_caps() {
    echo "🔍 Checking Steward Capabilities"  2>&1
    vault_secret_path_caps "secret/"
    vault_secret_path_caps "secret/data/"
    vault_secret_path_caps "sys/internal/ui/mounts/secret/data/"
    vault_secret_path_caps "secret/metadata/"

    vault_secret_path_caps "secret/data/pihole/"
    vault_secret_path_caps "secret/data/pihole/*"
    vault_secret_path_caps "secret/pihole/"
    vault_secret_path_caps "secret/pihole/*"
    vault_secret_path_caps "sys/internal/ui/mounts"
    vault_secret_path_caps "sys/internal/ui/mounts/secret"
    vault_secret_path_caps "sys/internal/ui/mounts/secret/data"
    vault_secret_path_caps "sys/internal/ui/mounts/secret/data/pihole"
    vault_secret_path_caps "secret/metadata/pihole/"  
}

vault_logout(){
    unset VAULT_TOKEN
    (PROVIDER_SELECT="mem" core_secret_mem_delete "vault/VAULT_TOKEN")
    kp close

}
vault_request_root_token() {    
    ! require_containers_ready VAULT_CONTAINER_NAME && {
        echo "❌ Erro: Instancia $VAULT_CONTAINER_NAME server não está a correr."
        return 1
    }

    (        
        echo '>>>>>>>>> "mem" vault/root/VAULT_TOKEN <<<<<<< "keepass"'
        kp test 2> /dev/null || kp open
        PROVIDER_SELECT="keepass" core_secret_service_get "root/VAULT_TOKEN" 
        vault_secret_path_caps
        # 2. Validar usando a função especializada
        if ! vault_validate_token "$VAULT_TOKEN" "root" 2> /dev/null; then            
            # Se a validação falhou, limpamos o cache para forçar novo login
            PROVIDER_SELECT="mem" core_secret_mem_delete "vault/VAULT_TOKEN"
            echo "⚠️  Cleaning invalid/expired token from mem." >&2
            # unset VAULT_TOKEN
        fi

        # 3. Health Check & Unseal (Pré-requisitos de Login)
        if ! curl -sk --connect-timeout 2 "$VAULT_ADDR/v1/sys/health" > /dev/null 2>&1; then
            echo "❌ Vault API down at $VAULT_ADDR" >&2 && return 1
        fi
        is_sealed && { echo "🔓 Unsealing..." >&2; vault_unseal || return 1; }
        
        # never save vault/VAULT_TOKEN to any persistent media. specialy the root
        PROVIDER_SELECT="mem" core_secret_service_put "vault/VAULT_TOKEN" "$VAULT_TOKEN" || return 1

    )
}
vault_request_stew_token() {
  
    ! require_containers_ready VAULT_CONTAINER_NAME && {
        echo "❌ Erro: Instancia $VAULT_CONTAINER_NAME server não está a correr."
        return 1
    }

    (
        PROVIDER_SELECT="mem" core_secret_service_get "vault/VAULT_TOKEN" 2> /dev/null
         #echo "$VAULT_TOKEN"
        
        # 2. Validar usando a função especializada
        if ! vault_validate_token "$VAULT_TOKEN" "steward-policy" 2> /dev/null; then            
            # Se a validação falhou, limpamos o cache para forçar novo login
            PROVIDER_SELECT="mem" core_secret_mem_delete "vault/VAULT_TOKEN"
            echo "⚠️  Cleaning invalid/expired token from mem." >&2
            # unset VAULT_TOKEN
        else    
            echo "VAULT_TOKEN still valid"
            return 0
        fi

        # 3. Health Check & Unseal (Pré-requisitos de Login)
        if ! curl -sk --connect-timeout 2 "$VAULT_ADDR/v1/sys/health" > /dev/null 2>&1; then
            echo "❌ Vault API down at $VAULT_ADDR" >&2 && return 1
        fi
        is_sealed && return 1  # need { echo "🔓 Unsealing..." >&2; vault_unseal || return 1; }

        # 4. Recuperação de Credenciais (KeePass fallback)
        # @todo review steward dependency on keepass. should return 1 when ROLE ID, SECRET ID are not recoved
        # 
        # unless root owner of only SEAL KEY ROOT KEY ROOT CA VAULT POLICY
        # root as delegate to "steward" caps to handle provison of all WEB [resource][user] provision 
        # steward is the 2nd most powerfull role @ home, but certainly the most busy one.
        # Steward is the app role delegator
        # Steward is the app (pihole,traefit, Authentik)  akamin, and local infra developer
        # Steward is the app provisiner
        # Steward is the app promoter 
        local r_id="$VAULT_ROLE_ID"
        local s_id="$VAULT_SECRET_ID"



        if [[ -z "$r_id" || -z "$s_id" ]]; then
            echo "🔑 Recovering AppRole from KeePass steward-role password..." >&2
            
            local creds=$(kp_get_approle "vault/AppRole/steward-role")
            r_id=$(echo "$creds" | awk '{print $1}')
            s_id=$(echo "$creds" | awk '{print $2}')
            #echo "$creds"
        fi

        [[ -z "$r_id" || -z "$s_id" ]] && { echo "❌ AppRole credentials not found." >&2; return 1; }

        # 5. Autenticação AppRole
        local LOGIN_RESPONSE
        LOGIN_RESPONSE=$(vault write -format=json auth/approle/login role_id="$r_id" secret_id="$s_id" 2>&1)
        
        VAULT_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.auth.client_token // empty')

        # ok: show all;;show_vars LOGIN_RESPONSE VAULT_TOKEN 
        # never store this token on keepass. 
        #       keepass is to store $user var definition must be mandatory and documented
        PROVIDER_SELECT="mem keepass" core_secret_service_put "vault/VAULT_TOKEN" "$VAULT_TOKEN" || return 1
    ) || return 1
}
export -f vault_request_stew_token

vault_request_token() {
    local role="${1:-"user"}" ## can be user|developer|bot
    
    ! require_containers_ready VAULT_CONTAINER_NAME && {
        echo "❌ Error: $VAULT_CONTAINER_NAME not running."
        return 1
    }

    local vault_role="$(sanitize_path_name "${role}-role")"
    local vault_policy="$(sanitize_path_name "${role}-policy")"
    local var_name="VAULT_TOKEN"
    ## default policy . if valid stay
    (
        PROVIDER_SELECT="mem" core_secret_service_get "vault/VAULT_TOKEN" 2>/dev/null
        
        if ! vault_validate_token "$VAULT_TOKEN" "$vault_policy" 2>/dev/null; then            
            PROVIDER_SELECT="mem" core_secret_service_delete "vault/VAULT_TOKEN" 2> /dev/null
            echo "⚠️ Cleaning invalid/expired token from mem." >&2
        else    
            echo "VAULT_TOKEN still valid"
            return 0
        fi        
    )

    if ! curl -sk --connect-timeout 2 "$VAULT_ADDR/v1/sys/health" > /dev/null 2>&1; then
            echo "❌ Vault API down at $VAULT_ADDR" >&2 && return 1
    fi
    is_sealed && return 1


    (
        # Check for environment variables first
        local r_id="$VAULT_ROLE_ID"
        local s_id="$VAULT_SECRET_ID"

        if [[ -z "$r_id" || -z "$s_id" ]]; then
            kp test 2> /dev/null || { 
                echo "requesting vault token role: $vault_role"
                kp open || return 1
            }

            echo "🔑 Recovering AppRole from KeePass $vault_role..." >&2
            local creds=$(kp_get_approle "vault/AppRole/$vault_role")
            r_id=$(echo "$creds" | awk '{print $1}')
            s_id=$(echo "$creds" | awk '{print $2}')
        fi

        [[ -z "$r_id" || -z "$s_id" ]] && { echo "❌ AppRole/$vault_role credentials not found." >&2; return 1; }

        # Use curl to call Vault API directly
        local LOGIN_RESPONSE
        LOGIN_RESPONSE=$(curl -sk -X POST "$VAULT_ADDR/v1/auth/approle/login" \
            -H "Content-Type: application/json" \
            -d "{\"role_id\": \"$r_id\", \"secret_id\": \"$s_id\"}" 2>&1)
        
        VAULT_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.auth.client_token // empty')
        
        [[ -z "$VAULT_TOKEN" ]] && { echo "❌ Failed to get token" >&2; return 1; }
                
        PROVIDER_SELECT="mem keepass" core_secret_service_put "vault/VAULT_TOKEN" "$VAULT_TOKEN" || return 1       
    )
}
export -f vault_request_token

vault_validate_token() {
    local token="${1:-$VAULT_TOKEN}"    
    local match_policy="${2:-default}" ## or not if empty
    local name="${2:-approle}"
    local vault_url="${VAULT_ADDR:-"https://$VAULT_INTERNAL_NS"}"

    (
        # 1. Recuperação robusta do token
        if [[ -z "$token" ]]; then
            # Tenta buscar do provider mem sem criar subshells desnecessários
            PROVIDER_SELECT="mem" core_secret_service_get "vault/VAULT_TOKEN" >/dev/null 2>&1
            token="$VAULT_TOKEN"
        fi
        
        [[ -z "$token" ]] && { echo "❌ [VAULT] Erro: Token não fornecido." >&2; return 1; }

        echo "🔍 Validando Vault Token em $vault_url..." >&2

        # 2. Chamada à API (Adicionado --fail para capturar erros HTTP 4xx/5xx)
        local response
        response=$(curl -k -s --connect-timeout 5 \
            -H "X-Vault-Token: $token" \
            "$vault_url/v1/auth/token/lookup-self")

        [[ -z "$response" ]] && { echo "🚫 [VAULT NETWORK] Sem resposta de $vault_url" >&2; return 1; }

        # 3. Processamento ÚNICO via jq (Performance)
        # Extraímos tudo o que precisamos numa string formatada para o 'read' do Bash
        local auth_data response
        auth_data=$(echo "$response" | jq -r '
            if .errors then "ERROR \(.errors | join("; "))"
            else "OK \(.data.display_name) \(.data.ttl) \(.data.policies | join(","))"
            end' 2>/dev/null)
        
        # 4. Parsing do resultado do jq
        read -r status display_name ttl policies <<< "$auth_data"

        if [[ "$status" == "OK" ]]; then
            local ttl_min=$(( ttl / 60 ))
            
            echo "✅ [VAULT SUCCESS] Autenticado como: $display_name" >&2
            # B. Validação de Política (Usando Regex para evitar matches parciais como 'default' em 'default-admin')
            if [[ -n "$match_policy" ]]; then
                if [[ ! ",$policies," =~ ,$match_policy, ]]; then
                    echo "❌ [ERROR] Política '$match_policy' não encontrada em: [$policies]" >&2
                    return 1
                fi
            fi
            echo "   ⏳ TTL: ${ttl_min}m | 📜 Políticas: [${policies//,/ ,}]" >&2
            [[ $ttl_min -gt 0 ]] && [[ $ttl -lt 600 ]] && echo "⚠️  [WARNING] Token prestes a expirar (<10m)!" >&2
            if [[ ! -z $name &&  $name != $display_name ]]; then 
                return 1
            fi
            return 0
        else
            # Se não for OK, reporta o erro e verifica estado do Vault
            local error_msg="${auth_data#ERROR }"
            echo "⚠️ [VAULT] Erro na validação: ${error_msg:-"Resposta inesperada"}" >&2
            
            # Estas funções devem ser chamadas apenas em caso de erro
            is_sealed 
            is_initialized 
            return 1
        fi
    )

}


vault_up() {    
    (
        cd $VAULT_DIR
        docker_container_kill_ip "$VAULT_CONTAINER_IP"
        docker network prune -f
        sleep 1
        #export MOUNT_VAULT_CACERT="/vault/config/certs/trusted-ca.pem"
        # try two times to up vault
        if docker compose up -d; then
            vault_up_wait || return 1
        else
            docker compose up -d "$VAULT_CONTAINER_NAME" && \
            vault_up_wait || return 1
            return 0
        fi 
    ) || return 1
}

vault_down() {
    (
        cd $VAULT_DIR     
        docker compose down --remove-orphans    
    ) || return 1
}

vault_up_wait() {
    # 5. Test availability (Health Check)
    local MAX_RETRIES=5
    local COUNT=0
    
    show_vars CURL_CA_OPTS VAULT_ADDR
    until [ $COUNT -ge $MAX_RETRIES ]; do
        local HTTP_STATUS 
        HTTP_STATUS=$(
            curl $CURL_CA_OPTS -s -o /dev/null -w "%{http_code}" \
                --connect-timeout 2 \
            "$VAULT_ADDR/v1/sys/health" || echo "000"
        )
        
        # 200: OK, 429: Unsealed/Standby, 503: Sealed, 501: Not initialized
        if [[ "$HTTP_STATUS" =~ ^(200|429|503|501)$ ]]; then
            echo -e "\n✅ Vault is responsive (Status: $HTTP_STATUS) at $VAULT_ADDR"  >&2
            if is_sealed; then    
                # is_sealed retornou 0 (True), logo o cofre está fechado.
                echo "🔒 Vault is sealed. Action: vault_unseal" >&2
            elif ! is_initialized; then
                # is_initialized retornou 0 (True), logo o cofre NÃO está inicializado.
                echo "🐣 Vault is not initialized." >&2    
            fi
            return 0
        else
            printf ".$HTTP_STATUS"  >&2
            if is_sealed; then    
                # is_sealed retornou 0 (True), logo o cofre está fechado.
                echo "🔒 Vault is sealed. Action: vault_unseal" >&2
                return 0
            elif ! is_initialized; then
                # is_initialized retornou 0 (True), logo o cofre NÃO está inicializado.
                echo "🐣 Vault is not initialized." >&2    
                return 1
            fi
        fi 
        sleep 2
        ((COUNT++))
    done

    echo -e "\n❌ Timeout: Vault at $VAULT_ADDR is not responsive."  >&2
    return 1
}
vault_create_home_server_role() {
    echo "🔧 Criando Role: "$home_vault_role"..." >&2
    local vrole=$(vault write pki_int/roles/$home_vault_role \
        allowed_domains="$DOMAIN,$INTERNAL_DOMAIN" \
        allow_bare_domains=true \
        allow_subdomains=true \
        allow_wildcard_certificates=true \
        allow_localhost=true \
        allow_ip_sans=true \
        server_flag=true \
        client_flag=true \
        max_ttl="720h" \
        key_bits=2048 \
        key_type="rsa" \
        use_csr_common_name=true \
        use_csr_sans=true \
        enforce_hostnames=false \
        require_cn=false \
        organization="Home2500" \
        ou="Home IT Department" \
        country="PT" \
        locality="Local" \
        province="Network")

    if [ $? -eq 0 ]; then
        echo "✅ Role gerado com sucesso!" >&2
    else
        echo "❌ Falha crítica: O não conseguiu criar a role."  >&2
        return 1
    fi             
}

vault__self_certificate() {
    local home_vault_role="home-server-role"
    local CERTS_FOLDER="$VAULT_DIR/config/certs"
    require_locations CERTS_FOLDER
    echo "🔧 Verificando/Criando Role: "$home_vault_role"..." >&2

    (
        
        vault_switch http || return 1
        vault_unseal || return 1

        PROVIDER_SELECT="mem" core_secret_service_get "vault/VAULT_TOKEN" #2> /dev/null 
        require_vars VAULT_TOKEN || return 1
        # O Steward agora pode fazer este 'write' porque atualizámos a política

        echo "🔐 Gerando certificados internos..."  >&2

        local vault_output=$(docker exec -e VAULT_ADDR=$VAULT_ADDR -e VAULT_TOKEN=$VAULT_TOKEN vault \
            vault write -format=json pki_int/issue/$home_vault_role \
            common_name="vault.$INTERNAL_DOMAIN" \
            alt_names="localhost,vault.$INTERNAL_DOMAIN,vault.$DOMAIN,vault-oidc.$DOMAIN" \
            ip_sans="127.0.0.1,172.28.0.6" \
            ttl="720h")   

        if [ $? -eq 0 ]; then
            echo "✅ Certificado gerado pelo com sucesso!" >&2
        else
            echo "❌ Falha crítica: O não conseguiu criar a role ou emitir o cert."  >&2
            return 1
        fi     

        # Extrai e salva os arquivos na pasta de config (montada como volume)
        sudo chown -R $USER:$USER $CERTS_FOLDER
        #echo $vault_output
        rm -f $CERTS_FOLDER/*
        
        echo "$vault_output" | jq -r '.data.certificate' > $CERTS_FOLDER/vault.crt
        echo "$vault_output" | jq -r '.data.private_key' > $CERTS_FOLDER/vault.key

        echo "📋 Getting Root CA certificate..."  >&2
        vault read -format=json pki/cert/ca | jq -r '.data.certificate' > $CERTS_FOLDER/root_ca.crt
        vault read -format=json pki_int/cert/ca | jq -r '.data.certificate' > $CERTS_FOLDER/ca.crt

        cat $CERTS_FOLDER/vault.crt \
            $CERTS_FOLDER/ca.crt \
            $CERTS_FOLDER/root_ca.crt > $CERTS_FOLDER/vault-fullchain.crt

        (
            cd $CERTS_FOLDER
            sudo chown -R "$USER:$USER" $CERTS_FOLDER
            sudo chmod -R 644 $CERTS_FOLDER
            sudo chmod -R 640 *.key
        )
        
        ls -la $CERTS_FOLDER/
        echo "✅ Certificados gerados com sucesso em $CERTS_FOLDER"  >&2
    ) || return 1
}
vault__steward_policy__DO_NOT_DELETE() {
  echo "Initializing/Updating Steward Role..."

  # 1. Define the Steward Policy (Fixed syntax)
  # We use single quotes around EOF to prevent shell expansion
  vault policy write app-steward-policy - <<'EOF'
# --- 1. SEGREDOS (KV v2) ---
path "secret" { capabilities = ["list", "read"] }
path "secret/data/*" { capabilities = ["create", "read", "update", "patch", "delete", "list"] }
path "secret/metadata/*" { capabilities = ["list", "read", "delete"] }

# --- 2. DESCOBERTA E UI (Preflight Fix) ---
# Permite à CLI validar a existência do mount 'secret'
path "secret/pihole/*" { capabilities = ["read", "list"] }
path "sys/internal/ui/mounts" { capabilities = ["read"] }
path "sys/internal/ui/mounts/secret" { capabilities = ["read"] }
path "sys/internal/ui/mounts/secret/*" { capabilities = ["read"] }
path "sys/internal/ui/mounts/secret/data" { capabilities = ["read", "list"] }
# --- UI Discovery (Preflight Fix) ---
# Permite que a UI do Vault saiba o que existe no mount 'secret'
path "sys/internal/ui/mounts/secret/data/**" { 
  capabilities = ["read", "list"] 
}
#path "sys/internal/ui/mounts/secret/data/pihole/" { capabilities = ["read", "list"] }
path "sys/internal/ui/mounts/secret" { capabilities = ["read"] }
## ????
path "sys/mounts" { capabilities = ["read"] }
path "sys/mounts/secret" { capabilities = ["read"] }


# --- 3. INTERMEDIATE CA (pki_int) - ADMINISTRAÇÃO TOTAL ---
# O Steward é o dono da pki_int, pode configurar URLs, Issuers e Roles
path "pki_int/*" { capabilities = ["create", "read", "update", "delete", "list"] }
# Permite ao Steward gerir as roles de emissão dentro da pki_int
path "pki_int/roles/home-server-role" { capabilities = ["create", "read", "update", "delete"] }
# Permite listar as roles para validação
path "pki_int/roles" { capabilities = ["list"] }

# --- 4. EMISSÃO DE CERTIFICADOS (Traefik proxy service 4 home2500.local ) ---
path "pki_int/issue/home-server-role" { capabilities = ["create", "update"] }
path "pki_int/sign/home-server-role" { capabilities = ["create", "update"] }

# --- 5. ROOT CA (pki) - APENAS LEITURA PARA BUNDLE ---
# O Steward precisa de ler a Root para gerar o trusted-ca.pem, mas não pode alterar nada
path "pki/cert/ca" { capabilities = ["read"] }
path "pki/config/urls" { capabilities = ["read"] }

# --- 6. AUTH & OIDC (Gestão de Identidade) ---
# ESTA LINHA É A CRÍTICA: O sudo deve estar no prefixo sys/
path "sys/auth/oidc" { 
  capabilities = ["create", "update", "read", "delete", "sudo"] 
}

path "sys/auth/oidc" { capabilities = ["create", "update", "read", "delete", "sudo"] }
path "sys/mounts/auth/oidc/tune" { capabilities = ["update", "sudo"] }

# Aqui o sudo é opcional, mas create/update são necessários para as Roles
path "auth/oidc/*" { 
  capabilities = ["create", "read", "update", "delete", "list"] 
}

path "sys/auth" { 
  capabilities = ["read"] 
}

# OIDC Handle 
# Permitir ler o RoleID do próprio Steward
path "auth/approle/role/steward-role/role-id" {
  capabilities = ["read"]
}
# Permitir gerar novos SecretIDs para o Steward
path "auth/approle/role/steward-role/secret-id" {
  capabilities = ["update", "create"]
}
# (Opcional) Se o Steward precisar listar ou criar outros AppRoles
path "auth/approle/role/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# (Opcional) Se o Steward precisar configurar o próprio método auth
path "auth/approle/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Gerenciar Identidades (Grupos, Entidades e Aliases)
path "identity/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
# Gerenciar Identidades (Grupos, Entidades e Aliases)
path "identity/group" {
  capabilities = ["create", "update", "read", "delete", "list"]
}

path "identity/group/name/*" {
  capabilities = ["read"]
}

path "identity/group-alias" {
  capabilities = ["create", "update", "read", "delete", "list"]
}

# Permitir configurar (tune) o método de autenticação OIDC
path "sys/mounts/auth/oidc/tune" {
  capabilities = ["update", "sudo"]
}

# Opcional: Se você quiser que o script possa listar todos os mounts para validar
path "sys/mounts" {
  capabilities = ["read"]
}
# create access control 
path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF

    vault policy read app-steward-policy
    # 2. Enable AppRole auth if not already enabled
    if ! vault auth list | grep -q "^approle/"; then
        echo "📦 Enabling AppRole..." >&2
        vault auth enable approle
    else
        echo "ℹ️ AppRole already enabled." >&2
    fi

    # 3. Configure the role 
    # We ensure the policy is assigned here.
    vault write auth/approle/role/steward-role \
        token_policies="app-steward-policy" \
        token_ttl="4h" \
        token_max_ttl="4h" \
        bind_secret_id=true
}

vault_switch() {
    local MODE="${1}" # Remove '--' se o user passar --http
    local BASE_DIR="$VAULT_DIR" # Ajusta para o teu path absoluto
    
    # 1. Validação de Argumentos
    if [[ "$MODE" != "http" && "$MODE" != "https" ]]; then
        echo "❌ Error: Usage: vault_switch [http|https]" >&2
        return 1
    fi

    # 2. Definição de Paths
    local UNSECURE_CONFIG="$BASE_DIR/config/vault-http.hcl"
    local SECURE_CONFIG="$BASE_DIR/config/vault-https.hcl"
    local ACTIVE_CONFIG="$BASE_DIR/config/vault-active.hcl"
    local VAULT_LIB="$BASE_DIR/vault_lib.sh"

    echo "🔄 Switching Vault to: $MODE"  >&2

    # 3. Verificar estado atual (via yq)
    local CURRENT_ADDR
    CURRENT_ADDR=$(yq -oy '.api_addr' "$ACTIVE_CONFIG" 2>/dev/null || echo "none")

    local TARGET_SOURCE
    local EXPECT_PROTOCOL
    if [[ "$MODE" == "http" ]]; then
        TARGET_SOURCE="$UNSECURE_CONFIG"
        EXPECT_PROTOCOL="http://"
    else
        TARGET_SOURCE="$SECURE_CONFIG"
        EXPECT_PROTOCOL="https://"
    fi

    # 4. Executar a troca se houver mudança de protocolo
    if [[ "$CURRENT_ADDR" != *"$EXPECT_PROTOCOL"* ]]; then
        echo "⚠️ Protocol change detected ($CURRENT_ADDR -> $MODE). Restarting..."  >&2
        
        vault_down        
                
        sudo cp "$TARGET_SOURCE" "$ACTIVE_CONFIG"
        vault_config_requirements
        vault_config
        mkdir -p "$BASE_DIR/config/certs"                      
        vault_up || return 1
        
        echo "✅ Config applied. Waiting for health check..."  >&2
    else
        echo "ℹ️ Vault is already configured for $MODE. Ensuring container is up..."  >&2
        vault_up || return 1
    fi

}

vault_sort_weights() {
    local rules_json
    rules_json=$(cat <<-'EOF'
[
  {
    "prefix": "vault_*",
    "weight": 20,
    "cat": "VAULT"
  },
  
  {
    "prefix": "_*",
    "refine": "",
    "weight": 32,
    "cat": "INTERNAL"
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

vault_fn_catalog() {
    #core_fn_sort_json "${BASH_SOURCE[0]}" "kp_sort_weights" 
    core_fn_catalog "${BASH_SOURCE[0]}" "vault_sort_weights" 
}

# --- CHECK FUNCIONS ---
require_functions \
    require_vars \
    require_functions \
    require_binaries \
    vault_get_secret \
    vault_save_secret \
    vault_secret_path_caps \
    is_sealed \
    is_initialized \
    vault_curl_get \
    vault_curl_post \
    vault_config \
    vault_unseal \
    vault_request_stew_token




# 1. Determine if we are being Sourced or Executed
# (Checking if BASH_SOURCE exists and the 0th element is the script itself)
# Calculate the depth of the sourcing stack
stack_depth=${#BASH_SOURCE[@]}
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    #stack_trace
    vault_config_requirements
    vault_config
    echo "" 2>&1
    require_vars VAULT_CACERT 

    kp test || kp open

    ### check state
    if require_containers_ready VAULT_CONTAINER_NAME; then
        if is_sealed; then    
            # is_sealed retornou 0 (True), logo o cofre está fechado.
            echo "🔒 Vault is sealed. Action: vault_unseal" >&2
            return 1
        elif ! is_initialized; then
            # is_initialized retornou 0 (True), logo o cofre NÃO está inicializado.
            echo "🐣 Vault is not initialized." >&2    
            return 1
        fi

        vault_validate_token || {
            echo "vault_request_stew_token" >&2
            return 1
        }  
    else    
        echo "vault_up"   
    fi

fi


