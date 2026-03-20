#!/bin/bash
# Filename: ../../devops/authentik/./_0.traefik_lib.sh

set +e

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ This is a library and should be sourced, not run directly."  2>&1
    return 1  ## disable return 1 only on development mode. why ??? 
fi

TRAEFIK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "TRAEFIK_DIR: $TRAEFIK_DIR"  2>&1
# --- AUTHENTIK ctx ----
devops_ctx_dir=$(realpath $TRAEFIK_DIR/../../devops)
[[ "$DEVOPS_DIR" == "$devops_ctx_dir" ]] || echo "Wrong script context" >/dev/null 2>&1

export TRAEFIK_DIR

# >>>>>
source $(realpath ../core.sh) > /dev/null 2>&1 # can we hide completly any console log of this script ?

require_vars SERVICES_PIPE
require_locations TRAEFIK_DIR

export DOMAIN="${DOMAIN:-"localhost"}"
export INTERNAL_DOMAIN="${INTERNAL_DOMAIN:-"app-network"}"

require_vars PUBLIC_SERVICES SORTED_DESIRED_NAMES
require_functions require_service_redirect_auth 

# --- DEBUG EXPECTED PUPLIC_SERVICES SECTION ---
tk_show_desired_names() {
    echo -e "\n--- TRAEFIK DESIRED NAMES ---"
    
    # Armazena o JSON em uma variável local
    local json_data
    json_data=$(core_desired_domain_names_json)

    # Validação simples de dependência
    if ! command -v jq &> /dev/null; then
        echo "❌ Erro: 'jq' é necessário para processar o JSON."
        return 1
    fi
    # 3. Extra (Útil para Debug): Mostrar o mapeamento de IP
    echo -e "\n📍 Network Mapping:"
    echo "$json_data" | jq -r '.[] | "\(.host) -> \(.address)"' | sed 's/^/  /'

    echo "-----------------------------"
}
tk_show_desired_names

# 2. Define Paths and Configuration
export TRAEFIK_DIR=${TRAEFIK_DIR}

export TRAEFIK_CERT_DIR="$TRAEFIK_DIR/traefik/certs"

require_vars DEVOPS_DIR

# --- AUTHENTIK ctx ----
devops_ctx_dir=$(realpath $TRAEFIK_DIR/../../devops)
[[ "$DEVOPS_DIR" == "$devops_ctx_dir" ]] || echo "Wrong script context" >/dev/null 2>&1


require_vars \
    TRAEFIK_DIR \
    TRAEFIK_CERT_DIR \
    DOMAIN \
    PUBLIC_SERVICES_LIST \
    SORTED_DESIRED_NAMES


TRAEFIK_CERT_CHAIN="$TRAEFIK_CERT_DIR/traefik-fullchain.pem"
TRAEFIK_CERT_KEY="$TRAEFIK_CERT_DIR/traefik.key"
TRAEFIK_CERT_CA_CHAIN="$TRAEFIK_CERT_DIR/ca-chain.pem"
require_files TRAEFIK_CERT_CHAIN \
    TRAEFIK_CERT_KEY \
    TRAEFIK_CERT_CA_CHAIN || {
        echo "Traefik need tls files, run tk_need_renewal"    
    }
    
tk_need_renewal() {
    require_vars SORTED_DESIRED_NAMES TRAEFIK_CERT_CHAIN TRAEFIK_CERT_KEY
    local RENEWAL_NEEDED=false
    require_files TRAEFIK_CERT_CHAIN TRAEFIK_CERT_KEY || {
        echo "missing files. traefik need renewal" 
        return 1
    }

    # Improved SAN extraction
    # We use -certopt no_subject,no_issuer etc to keep output clean
    # Refined SAN extraction to remove the OpenSSL header label
    CURRENT_NAMES=$(openssl x509 -in "$TRAEFIK_CERT_CHAIN" -noout -ext subjectAltName | \
        grep -v "subjectAltName" | \
        sed 's/DNS://g; s/ //g; s/X509v3SubjectAlternativeName://g' | \
        tr ',' '\n' | grep -v '^$' | sort -u | tr '\n' ',' | sed 's/,$//')

    # 3. Names changed? Yes, need renewal (return 0)
    #echo "Current names: $CURRENT_NAMES"
    #echo "Desired names: $SORTED_DESIRED_NAMES"
    if [[ "$CURRENT_NAMES" != "$SORTED_DESIRED_NAMES" ]]; then
        echo "Desired names changed. traefik need renewal"
        return 0
    fi

    # 4. Expiring? Yes, need renewal (return 0)
    if ! openssl x509 -checkend $(( 7 * 24 * 3600 )) -in "$TRAEFIK_CERT_CHAIN" -noout; then
        echo "Certificate expired. traefik need renewal" 
        return 0
    fi

    # 5. Everything is fine? No renewal needed (return 1)
    return 1
    
}
# review traekif exposed formation certs in order to rrrurrrruuuunnnnnnnnnnnnnnnnnnn
tk_renew_certs() {
    require_vars SORTED_DESIRED_NAMES TRAEFIK_CERT_DIR TRAEFIK_CERT_KEY DOMAIN

    require_vars VAULT_CACERT VAULT_TOKEN || {            
        source $(core_resolve_file "vault/vault_lib.sh")
        vault_request_stew_token  
        vault_validate_token      
    }
    # 4. Build and Sort the Desired State

    echo "🔐 Requesting new certificate from Vault..."  >&2
    echo "📜 SANs: $SORTED_DESIRED_NAMES"  >&2
    local RESPONSE=$(
        PROVIDER_SELECT="mem" core_secret_service_get "vault/VAULT_TOKEN" 2> /dev/null
        
        vault write -format=json pki_int/issue/home-server-role \
            common_name="traefik.${DOMAIN}" \
            alt_names="${SORTED_DESIRED_NAMES}" \
            ttl="720h" | jq -e .
    ) || return 1            

    if [ $? -eq 0 ]; then
        echo "✅ Certificado gerado com sucesso!"  >&2
    else
        echo "❌ Falha crítica: O Steward não conseguiu criar a role ou emitir o cert."  >&2
        return 1
    fi     
    
    echo $RESPONSE | jq -r '{request_id,renewable,lease_duration,expiration: .data.expiration}'  >&2
    #expose echo $RESPONSE | jq
    # Extrair dados do JSON
    local KEY_DATA=$(echo "$RESPONSE" | jq -r '.data.private_key')
    local CERT_DATA=$(echo "$RESPONSE" | jq -r '.data.certificate')
    
    # IMPORTANTE: O ca_chain do Vault já contém a Intermediate + Root se usaste o Bundle no set-signed
    local CA_CHAIN=$(echo "$RESPONSE" | jq -r '.data.ca_chain | join("\n")')

    if [[ -z "$KEY_DATA" || "$KEY_DATA" == "null" ]]; then
        echo "❌ Error: Vault returned no key."  >&2
        return 1
    fi

    ## GEN
    # 1. Guardar a Chave Privada (Apenas a chave!)
    echo "$KEY_DATA" > "$TRAEFIK_CERT_KEY" 

    # 2. Guardar o Certificado Leaf (Apenas o certificado do site)
    echo "$CERT_DATA" > "$TRAEFIK_CERT_DIR/traefik.crt"

    # 3. Guardar a CA Chain (Intermediate + Root)
    printf "%s\n" "$CA_CHAIN" > "$TRAEFIK_CERT_DIR/ca-chain.pem"

    # 4. CRIAR O FULLCHAIN CORRETAMENTE (Com quebras de linha garantidas)
    # Usamos printf para garantir que cada bloco termina bem antes do próximo começar
    {
        cat "$TRAEFIK_CERT_DIR/traefik.crt"
        echo "" # Linha de segurança
        cat "$TRAEFIK_CERT_DIR/ca-chain.pem"
    } > "$TRAEFIK_CERT_CHAIN"

    echo "✅ Ficheiros PKI gerados em $TRAEFIK_CERT_DIR"

    
    # 7. Permissions (Essencial para o Traefik conseguir ler)
    sudo chown 1000:1000 $TRAEFIK_CERT_DIR/*   # 1000 costuma ser o ID do user no docker
    chmod 644 $TRAEFIK_CERT_DIR/*.pem
    chmod 644 $TRAEFIK_CERT_DIR/*.crt
    chmod 600 $TRAEFIK_CERT_DIR/*.key

    require_files TRAEFIK_CERT_CHAIN TRAEFIK_CERT_KEY 
    return 0
}

tk_test_tls() {
    require_binaries openssl grep sed timeout
    require_vars SORTED_DESIRED_NAMES "PUBLIC_SERVICES_LIST" "TRAEFIK_CERT_DIR" "DOMAIN"
    
    local errorsFound=0
    local CERT_CHAIN="$TRAEFIK_CERT_DIR/traefik-fullchain.pem"

    echo "🧐 Checking certificate file integrity..."
    if ! openssl x509 -in "$CERT_CHAIN" -noout 2>/dev/null; then
        echo "❌ Error: Invalid or missing certificate at $CERT_CHAIN"
        return 1
    fi

    # 1. Check if the file contains a chain (at least 2 certs: Entity + Intermediate)
    local cert_count=$(grep -c "BEGIN CERTIFICATE" "$CERT_CHAIN")
    if [ "$cert_count" -lt 2 ]; then
        echo "⚠️  Warning: File contains only $cert_count certificate(s). Intermediate CA might be missing."
    fi

    echo "--- Testing TLS Connectivity per Service ---"
    
    # FIX: Convert comma-separated string to space-separated for the loop
    local service_list=$(echo "$SORTED_DESIRED_NAMES" | tr ',' ' ')

    for sd in $service_list; do
        echo -n "🔍 Testing: $sd ... "
        
        # We try to grab the cert from the live endpoint
        # -servername is CRITICAL for SNI (Traefik needs it to pick the right cert)
        local live_cert
        live_cert=$(timeout 4s openssl s_client -connect "${sd}:443" -servername "$sd" -showcerts </dev/null 2>/dev/null)
        local exit_code=$?
        
        if [ $exit_code -eq 0 ] && [ -n "$live_cert" ]; then
            # Check for the dreaded Traefik Default Certificate
            if echo "$live_cert" | openssl x509 -noout -text | grep -q "TRAEFIK DEFAULT CERT"; then
                echo -e "\n❌ ERROR: Serving 'TRAEFIK DEFAULT CERT' (Check Traefik labels/rule match!)"
                errorsFound=1
            else
                # Verify expiry of the LIVE cert
                local expiry=$(echo "$live_cert" | openssl x509 -noout -enddate | cut -d= -f2)
                echo "✅ OK (Expires: $expiry)"
            fi
        else
            echo -e "\n❌ CRITICAL: Could not establish TLS with $sd (Port 443 blocked or DNS issue?)"
            errorsFound=1
        fi
    done

    if [ $errorsFound -ne 0 ]; then
        echo "------------------------------------------------------------"
        echo "❌ Validation finished with errors."
        return 1
    else
        echo "------------------------------------------------------------"
        echo "✅ All services are serving the correct TLS certificates."
        return 0
    fi
}

tk_test_authentik_outpost() {
    local service_list=$(echo "$SORTED_DESIRED_NAMES" | tr ',' ' ')

    for sd in $service_list; do
        echo -n "🔍 Testing: $sd "        
        core_http_url_status "https://$sd"
    done
}
tk_test_authentik_outpost() {
    echo -e "\n--- 🛡️  AUTHENTIK OUTPOST HEALTH CHECK ---"
    
    # Converte a lista separada por vírgulas em um array real do Bash
    local service_list=(${SORTED_DESIRED_NAMES//,/ })

    for sd in "${service_list[@]}"; do
        # Formata a URL (assume https se não especificado)
        local url="https://$sd"
        
        # Executa o status e captura o código de saída
        # Corrigido o redirecionamento para silenciar a função interna
        core_http_url_status "$url" >/dev/null 2>&1
        local status=$?

        # Escolha do ícone baseado no status (reutilizando sua lógica)
        local icon="❌"
        case $status in
            0)   icon="✅" ;;
            7)   icon="🔌" ;; # Connection Refused
            28)  icon="🕒" ;; # Timeout
            144) icon="🔗"; last_error="SSL/TLS Error or Interrupted" ;;
            148) icon="🚧"; last_error="No Route to Host / Backend Down" ;;
            502) icon="🧱" ;; # Bad Gateway
            *)   icon="❌ $status"; last_error="Code $status" ;;
        esac

        # Saída limpa em uma linha por serviço
        printf "  %-30s [%-3s] %s\n" "$sd" "$status" "$icon"
    done
    echo "------------------------------------------"
}

tk_check_renewal() {
    tk_need_renewal && tk_renew_certs && {
        tk_test_tls
    }
}

tk_up() {
    (
        cd $TRAEFIK_DIR
        tk_check_renewal
        docker compose up -d        
    )
}

tk_down() {
    (
        cd $TRAEFIK_DIR        
        docker compose down #--remove-orphans
    )
}


tk_logs() {
    # Define os alvos (podes pôr isto no teu core.sh)
    # Filtra apenas a criação de LoadBalancers e Middlewares de Auth/Redirect
    docker logs traefik 2>&1 | grep -E "Creating|Setting up" | grep -E "$SERVICES_PIPE"
    

    # Filtra o log do Traefik usando a tua lista de serviços e limpa o output
    docker logs traefik 2>&1 | grep -E "$SERVICES_PIPE" | \
        grep "Setting up redirection" | \
        sed 's/.*redirection from //' | \
        awk '{print "🔗 Redirection: " $1 " -> " $3}' | \
        sort -u


    # 1. Filtra pelos teus serviços e remove duplicados temporais
    # 2. Mostra apenas o estado final de cada router/middleware
    docker logs traefik 2>&1 | grep -E "$SERVICES_PIPE" | \
        grep "Setting up" | \
        sed 's/.*entryPointName/entryPointName/' | \
        sort -u
}

tk_logs_cert_tls_error() {
    docker logs traefik 2>&1 | grep -iE "cert|tls|error|$SERVICES_PIPE"

    curl -vIk https://traefik.home2500.local --resolve traefik.home2500.local:443:127.0.0.1

    require_service_redirect_auth traefik
}

##### SWITCH MODE "unprotected" to "authentik"
##### ATENTION :  .yml~ files are assets, used for switching treafik from stage "unprotected" to "authentik"

authentik_setup=$(core_resolve_file "traefik/traefik/dyn-options/authentik-routes.yml")
unprotected_setup=$(core_resolve_file "traefik/traefik/dyn-options/not_auth-routes.yml")
active_dynamic_yml=$(core_resolve_file "traefik/traefik/config/dynamic.yml")


require_files unprotected_setup authentik_setup
require_files active_dynamic_yml


#head -n 2 ./traefik/config/dynamic.yml
#echo ""
#echo "tk_switch2_authentik_routes              : authentik mode"
#echo "tk_switch2_unprotected_routes            : unprotected mode"


tk_switch2_authentik_routes() {
    # 1. Validar se o ficheiro de origem existe
    if [[ ! -f "$authentik_setup" ]]; then
        echo "❌ Erro: Ficheiro de configuração Authentik não encontrado em: $authentik_setup"
        return 1
    fi

    # 2. Copiar para o ficheiro ativo
    cp "$authentik_setup" "$active_dynamic_yml"
    
    # 3. Ajustar permissões (Garante que o Traefik consegue ler)
    chmod 644 "$active_dynamic_yml"
    
    echo "🔐 Mudado para: ROTAS PROTEGIDAS (Authentik SSO)"
}

tk_switch2_unprotected_routes() {
    # 1. Validar se o ficheiro de origem existe
    if [[ ! -f "$unprotected_setup" ]]; then
        echo "❌ Erro: Ficheiro de configuração desprotegido não encontrado em: $unprotected_setup"
        return 1
    fi

    # 2. Copiar para o ficheiro ativo
    cp "$unprotected_setup" "$active_dynamic_yml"
    
    # 3. Ajustar permissões
    chmod 644 "$active_dynamic_yml"

    echo "🔓 Mudado para: ROTAS ABERTAS (Unprotected)"
}

test_1_unprotected_routes() {
    tk_switch2_unprotected_routes
    cat $active_dynamic_yml
    sleep 5
    tk_test_tls
}

test_2_authentic_routes() {
    tk_switch2_authentik_routes
    cat $active_dynamic_yml
    sleep 5
    tk_test_tls
    tk_test_authentik_outpost
}

test_AUTHENTIK_TRAEFIK() {
    
    echo "----------------------- test unprotected routes"
    test_1_unprotected_routes

    echo ""
    echo "----------------------- test authentik routes"
    ak_fix_proxied_redir    
    test_2_authentic_routes

    . $(realpath ../authentik/_0-authentik.sh) \
                                            && \
        check_well_known_openid_config \                                            
        ak_fix_proxied_redir \
        require_service_redirect_auth "whoami"
}


require_functions \
    tk_need_renewal \
    tk_renew_certs \
    tk_test_tls \
    tk_test_authentik_outpost \
    tk_switch2_authentik_routes \
    tk_switch2_unprotected_routes \
    test_2_authentic_routes \
    test_AUTHENTIK_TRAEFIK 

