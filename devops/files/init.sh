#!/bin/bash
# ../../../devops/<*|app|launcher>/tool.sh

set +e

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ This is a library and should be sourced, not run directly."
    return 1
fi

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Tenta carregar o tool do authentik para usar o sistema de provisionamento de apps
source ../authentik/app/tool.sh

context() {
    require_vars \
        INTERNAL_DOMAIN \
        DOMAIN \
        CLIENT_APP_NAME \
        CLIENT_APP_DIR \
        CLIENT_APP_BLUE_LABEL \
        CLIENT_APP_BLUE_GROUP \
        CLIENT_APP_SERVICE_PORT \
        CLIENT_APP_BLUE_APPLY_TPL \
        CLIENT_APP_BLUE_CLEANUP_TPL \
        CLIENT_APP_BLUE_APPLY \
        CLIENT_APP_BLUE_CLEANUP \
        CLIENT_APP_COMPOSE_FILE || return 1
}

deploy() {
    context && {      
        echo "🚀 Iniciando Deploy do Stack Files (oCIS)..."
        app_up
    }
}

on_vault_login_fail() { 
    kp test || kp open
    vault_request_stew_token || return 1
}



provision_secrets() {
    echo "🔐 Provisionando segredos internos do oCIS $CLIENT_APP_NAME..." >&2        
    
    local all_secrets=(
        "OIDC_ID" "OCIS_JWT_SECRET" "OCIS_TRANSFER_SECRET" "OCIS_MACHINE_AUTH_API_KEY"
        "OCIS_SYSTEM_USER_ID" "OCIS_SYSTEM_USER_API_KEY" "OCIS_SERVICE_ACCOUNT_ID"
        "OCIS_SERVICE_ACCOUNT_SECRET" "OCIS_LDAP_BIND_PASSWORD" "OCIS_IDM_SVC_PASSWORD"
        "OCIS_IDM_ADMIN_PASSWORD" "OCIS_IDM_REVA_PASSWORD" "OCIS_IDM_IDP_PASSWORD"
        "OCIS_IDM_IDM_PASSWORD" "OCIS_GRAPH_APPLICATION_ID" "OCIS_ADMIN_USER_ID"
        "OCIS_ADMIN_PASSWORD" "OCIS_IDP_PASSWORD" "OCIS_REVA_PASSWORD" "OCIS_IDM_PASSWORD"
        "OCIS_THUMBNAILS_TRANSFER_SECRET" "OCIS_COLLABORATION_WOPI_SECRET"
        "STORAGE_USERS_MOUNT_ID" "STORAGE_METADATA_MOUNT_ID" "STORAGE_SHARES_MOUNT_ID"
        "GATEWAY_STORAGE_USERS_MOUNT_ID" "GATEWAY_STORAGE_METADATA_MOUNT_ID" "GATEWAY_STORAGE_SHARES_MOUNT_ID"
    )

    for secret in "${all_secrets[@]}"; do
        local secret_val=""
        local found=false

        # --- Loop de Descoberta e Promoção ---
        # Ordem: Memoria -> Vault -> KeePass
        local providers=("mem" "keepass" "vault" )
        for i in "${!providers[@]}"; do
            local p="${providers[$i]}"
            if PROVIDER_SELECT="$p" core_secret_service_get "$CLIENT_APP_NAME/$secret" 2>/dev/null; then
                secret_val="${!secret}"
                secret_val=$(echo "$secret_val" | tr -d '\n\r ')
                
                # Validação simples do valor recuperado
                if [[ -n "$secret_val" && "$secret_val" != *"UNDEF"* && "$secret_val" != "var"* ]]; then
                    found=true
                    # Promoção: Se achou no Vault/KP, salva nos níveis abaixo (anteriores no array)
                    if [[ $i -gt 0 ]]; then
                        local save_to="${providers[@]:0:$i}"
                        PROVIDER_SELECT="$save_to" core_secret_service_put "$CLIENT_APP_NAME/$secret" "$secret_val" 2>/dev/null
                    fi
                    break
                fi
            fi
        done

        # --- Geração de Novos Segredos ---
        if ! $found; then
            echo "🎲 Gerando novo segredo para $secret..." >&2
            if [[ "$secret" == *"ID" ]]; then
                secret_val=$(cat /proc/sys/kernel/random/uuid)
            else
                secret_val=$(openssl rand -hex 32)
            fi
            secret_val=$(echo "$secret_val" | tr -d '\n\r ')
            printf -v "$secret" "%s" "$secret_val" # Mesma coisa que eval, mas mais seguro
            PROVIDER_SELECT="keepass vault mem" core_secret_service_put "$CLIENT_APP_NAME/$secret" "$secret_val" 2>/dev/null || return 1
        fi
    done

    # --- Arquivos Estáticos e Certificados ---
    _provision_static_configs

    # --- Exportação para arquivo .secret e Aliases ---


    core_secret_export2_env_vars "$CLIENT_APP_NAME/.secret" "${all_secrets[@]}" || return 1

    return 0

}

# Função auxiliar para não poluir a principal
_provision_static_configs() {
    mkdir -p "$CLIENT_APP_DIR/config"

    if [[ ! -f "$CLIENT_APP_DIR/config/csp.yaml" ]]; then
        echo "📝 Criando config/csp.yaml com permissões para Authentik..."
        # Importante: O YAML do oCIS espera as diretivas com aspas simples internas para os valores 'self', etc.
        cat << 'EOF' > "$CLIENT_APP_DIR/config/csp.yaml"
directives:
  child-src:
    - "'self'"
  connect-src:
    - "'self'"
    - "blob:"
    - "https://raw.githubusercontent.com/owncloud/awesome-ocis/"
    - "https://auth.home2500.local"
  default-src:
    - "'none'"
  font-src:
    - "'self'"
    - "data:"
  frame-ancestors:
    - "'self'"
    - "https://auth.home2500.local"
  frame-src:
    - "'self'"
  img-src:
    - "'self'"
    - "data:"
    - "blob:"
    - "https://auth.home2500.local"
  manifest-src:
    - "'self'"
  media-src:
    - "'self'"
  object-src:
    - "'self'"
    - "blob:"
  script-src:
    - "'self'"
    - "'unsafe-inline'"
    - "'unsafe-eval'"
  style-src:
    - "'self'"
    - "'unsafe-inline'"
  worker-src:
    - "'self'"
EOF
    fi
    
    if [[ -f "../trusted-ca.pem" ]]; then
        echo "🔐 Sincronizando trusted-ca.pem..."
        cat "../trusted-ca.pem" > "$CLIENT_APP_DIR/config/trusted-ca.pem"
    fi
}

deploy_secrets() {
    require_vars CLIENT_APP_NAME || return 1

    echo "🔐 Sincronizando credenciais OIDC do vault para mem..." >&2
               
    # Sincronizar do vault para mem
    (            
        FROM="vault" TO="mem" tool_provision__secret_vars \
            "OIDC_ID=$CLIENT_APP_NAME/OIDC_ID" \
            "OIDC_SECRET=$CLIENT_APP_NAME/OIDC_SECRET" \
        || return 1

        # Debug: mostrar credenciais depois de sincronizar
        if PROVIDER_SELECT="mem" core_secret_service_get "$CLIENT_APP_NAME/OIDC_ID" 2>/dev/null; then
            echo "   ✅ Mem OIDC_ID: ${OIDC_ID:0:20}... (len: ${#OIDC_ID})" >&2
        fi
        if PROVIDER_SELECT="mem" core_secret_service_get "$CLIENT_APP_NAME/OIDC_SECRET" 2>/dev/null; then
            echo "   ✅ Mem OIDC_SECRET: ${OIDC_SECRET:0:20}... (len: ${#OIDC_SECRET})" >&2
        fi

    ) || return 1

    tool_renew_certs

    return 0
}

on_deploy_secrets_fail() {
    return 1
}
on_provision_oidc_fail() {
    return 1
}

on_script_fail() { echo "script fail"; return 1; }
on_login_fail() { return 1; }
on_provision_db_fail() { return 1; } 
on_expose_fail() { return 1; }
on_running_fail() { echo "running fail"; return 1; }
on_compose_fail() { return 1; }
on_provision_secrets_fail() { return 1; }

on_name_register_fail() { return 1; }
on_authentik_login_fail() { 
    require_vars AUTHENTIK_API_TOKEN && ak_api_token_validate || return 1; 
}
on_blue_apply_fail() { return 1; }
on_outpost_add_fail() { return 1; }
on_certificate_fail() { return 0; }

docker_init() {
    echo "🏗️  Iniciando configuração do oCIS..."
    context || return 1
    provision_secrets || return 1
    
    require_files CLIENT_APP_SECRET_FILE || return 1
    
    local tpl_file="$CLIENT_APP_DIR/ocis.yaml.tpl"
    local config_file="$CLIENT_APP_DIR/config/ocis.yaml"
    
    if [[ -f "$tpl_file" ]]; then
        echo "📝 Gerando config a partir do template..."
        
        if [[ -f "../trusted-ca.pem" ]]; then
            mkdir -p "$CLIENT_APP_DIR/config"
            cp "../trusted-ca.pem" "$CLIENT_APP_DIR/config/trusted-ca.pem" 2>/dev/null || true
        fi
        
        echo "no" || perl -e '
            use strict;
            use warnings;
            
            my %vars = (
                # Core Secrets
                OCIS_JWT_SECRET               => $ENV{OCIS_JWT_SECRET} // "",
                OCIS_TRANSFER_SECRET          => $ENV{OCIS_TRANSFER_SECRET} // "",
                OCIS_MACHINE_AUTH_API_KEY      => $ENV{OCIS_MACHINE_AUTH_API_KEY} // "",
                OCIS_SYSTEM_USER_ID           => $ENV{OCIS_SYSTEM_USER_ID} // "",
                OCIS_SYSTEM_USER_API_KEY      => $ENV{OCIS_SYSTEM_USER_API_KEY} // "",
                OCIS_ADMIN_USER_ID            => $ENV{OCIS_ADMIN_USER_ID} // "",
                
                # Graph & Service Accounts
                OCIS_GRAPH_APPLICATION_ID     => $ENV{OCIS_GRAPH_APPLICATION_ID} // "",
                OCIS_SERVICE_ACCOUNT_ID       => $ENV{OCIS_SERVICE_ACCOUNT_ID} // "",
                OCIS_SERVICE_ACCOUNT_SECRET   => $ENV{OCIS_SERVICE_ACCOUNT_SECRET} // "",
                
                # IDM Passwords (Sincronizado com o .tpl)
                OCIS_IDM_ADMIN_PASSWORD       => $ENV{OCIS_IDM_ADMIN_PASSWORD} // "",
                OCIS_IDM_IDM_PASSWORD         => $ENV{OCIS_IDM_IDM_PASSWORD} // "",
                OCIS_IDM_IDP_PASSWORD         => $ENV{OCIS_IDM_IDP_PASSWORD} // "",
                OCIS_IDM_REVA_PASSWORD        => $ENV{OCIS_IDM_REVA_PASSWORD} // "",
                
                # Apps & Storage
                OCIS_COLLABORATION_WOPI_SECRET => $ENV{OCIS_COLLABORATION_WOPI_SECRET} // "changeme",
                OCIS_THUMBNAILS_TRANSFER_SECRET => $ENV{OCIS_THUMBNAILS_TRANSFER_SECRET} // "changeme",
                STORAGE_USERS_MOUNT_ID        => $ENV{STORAGE_USERS_MOUNT_ID} // "",
                GATEWAY_STORAGE_USERS_MOUNT_ID => $ENV{GATEWAY_STORAGE_USERS_MOUNT_ID} // "",
            );
            
            sub escape_yaml {
                my $s = shift;
                $s =~ s/\\/\\\\/g;
                $s =~ s/"/\\"/g;
                return $s;
            }
            
            my $tpl_file = $ARGV[0];
            my $out_file = $ARGV[1];
            
            open(my $fh, "<", $tpl_file) or die "Cannot open template: $!";
            my $tpl = do { local $/; <$fh> };
            close($fh);
            
            for my $k (keys %vars) {
                my $v = escape_yaml($vars{$k});
                $tpl =~ s/\{\{$k\}\}/$v/g;
            }
            
            open(my $out, ">", $out_file) or die "Cannot write output: $!";
            print $out $tpl;
            close($out);
            
            print "Config generated successfully\n";
        ' "$tpl_file" "$config_file" || return 1
        
        echo "✅ Config gerada a partir do template"
    else
        echo "📝 Executando 'ocis init'..."
        
        if [[ -f "../trusted-ca.pem" ]]; then
            mkdir -p "$CLIENT_APP_DIR/config"
            cp "../trusted-ca.pem" "$CLIENT_APP_DIR/config/trusted-ca.pem"
        fi
        
        local ca_mount=""
        if [[ -f "$CLIENT_APP_DIR/config/trusted-ca.pem" ]]; then
            ca_mount="-v ./config/trusted-ca.pem:/etc/ocis/trusted-ca.pem:ro"
        fi
        
        docker run --rm \
            -v "$CLIENT_APP_DIR/config:/etc/ocis" \
            -v "$CLIENT_APP_DIR/data:/var/lib/ocis" \
            $ca_mount \
            --user $(id -u):$(id -g) \
            --env-file "$CLIENT_APP_SECRET_FILE" \
            -e OCIS_INSECURE=false \
            owncloud/ocis init --force-overwrite || return 1
            
        echo "✅ Config inicializada via ocis init"
        
        _ocis_sync_config_secrets || true
    fi
    
    local domain_val="${DOMAIN:-home2500.local}"
    sed -i "s/\$DOMAIN/$domain_val/g" "$CLIENT_APP_DIR/docker-compose.yaml" 2>/dev/null || true
    
    echo "🧪 Testando inicialização do container..."
    
    local docker_args=(
        "-d" "--name" "ocis-server-init-test"
        "--network" "app-network"
        "--restart" "no"
        "-v" "$CLIENT_APP_DIR/data:/var/lib/ocis"
        "-v" "/etc/localtime:/etc/localtime:ro"
        "-v" "$CLIENT_APP_DIR/config/trusted-ca.pem:/etc/ocis/trusted-ca.pem"
        "--env-file" "$CLIENT_APP_SECRET_FILE"
        "-e" "OCIS_INSECURE=false"
        "-e" "OCIS_URL=https://files.${domain_val}"
        "-e" "OCIS_LOG_LEVEL=debug"
        "-e" "OCIS_CERTIFICATE_AUTHORITIES=/etc/ocis/trusted-ca.pem"
        "-e" "PROXY_HTTP_ADDR=0.0.0.0:9200"
        "-e" "PROXY_ENABLE_TLS=false"
        "-e" "PROXY_TLS=false"
        "-e" "OCIS_LOG_LEVEL=info"
        "-e" "IDM_CREATE_DEMO_USERS=false"
        "--add-host" "auth.${domain_val}:172.28.0.11"
        "--add-host" "files.${domain_val}:172.28.0.11"
    )
    
    docker run "${docker_args[@]}" owncloud/ocis:latest 2>/dev/null || {
        echo "❌ Falha ao iniciar container de teste"
        return 1
    }
    
    docker cp "$config_file" ocis-server-init-test:/etc/ocis/ocis.yaml
    if [[ -f "$CLIENT_APP_DIR/config/csp.yaml" ]]; then
        docker cp "$CLIENT_APP_DIR/config/csp.yaml" ocis-server-init-test:/etc/ocis/csp.yaml
    fi
        
    docker restart ocis-server-init-test
    
    sleep 15
    
    if docker logs ocis-server-init-test 2>&1 | grep -q "jwt_secret has not been set"; then
        echo "❌ Erro: jwt_secret não está configurado corretamente"
        docker rm -f ocis-server-init-test 2>/dev/null
        return 1
    fi
    
    local status
    status=$(docker inspect -f '{{.State.Status}}' ocis-server-init-test 2>/dev/null)
    if [[ "$status" == "running" || "$status" == "created" ]]; then
        echo "✅ Container inicia corretamente"
        docker rm -f ocis-server-init-test 2>/dev/null
        
        core_secret_export2_env_vars "$CLIENT_APP_NAME/.secret" \
            OCIS_JWT_SECRET \
            OCIS_TRANSFER_SECRET \
            OCIS_MACHINE_AUTH_API_KEY \
            OCIS_SYSTEM_USER_ID \
            OCIS_SYSTEM_USER_API_KEY \
            OCIS_SERVICE_ACCOUNT_ID \
            OCIS_SERVICE_ACCOUNT_SECRET \
            OCIS_LDAP_BIND_PASSWORD \
            OCIS_IDM_SVC_PASSWORD \
            OCIS_IDM_ADMIN_PASSWORD \
            OCIS_IDM_REVA_PASSWORD \
            OCIS_IDM_IDP_PASSWORD \
            OCIS_IDM_IDM_PASSWORD || return 1 true
            
        return 0
    fi
    
    echo "❌ Container não iniciou. Verificando logs..."
    docker logs ocis-server-init-test 2>&1 | tail -20
    docker rm -f ocis-server-init-test 2>/dev/null
    return 1
}

# Helper function to sync secrets from generated config to vault/mem
_ocis_sync_config_secrets() {
    local config_file="$CLIENT_APP_DIR/config/ocis.yaml"
    [[ -f "$config_file" ]] || return 1
    
    echo "🔄 Sincronizando segredos de $config_file para os provedores..."

    # Helper: Extrai valor do YAML e salva nos provedores
    _sync_yaml_key() {
        local yaml_key="$1"    # Ex: "jwt_secret"
        local secret_var="$2"  # Ex: "OCIS_JWT_SECRET"
        local search_type="${3:-simple}" # simple ou service_user
        local val=""

        if [[ "$search_type" == "service_user" ]]; then
            # Lógica para blocos aninhados (reva_password, etc)
            val=$(grep -A10 "service_user_passwords:" "$config_file" | grep "${yaml_key}:" | awk '{print $2}')
        elif [[ "$yaml_key" == "id:" ]]; then
            # Caso especial para o ID do Graph
            val=$(grep -E "^[[:space:]]*id:" "$config_file" | head -1 | awk '{print $2}')
        else
            # Busca simples no topo/indentação padrão
            val=$(grep -E "^[[:space:]]*${yaml_key}:" "$config_file" | head -1 | awk '{print $2}')
        fi

        # Limpeza de aspas
        val="${val%\"}"; val="${val#\"}"; val="${val%\'}"; val="${val#\'}"

        if [[ -n "$val" ]]; then
            echo "   📝 Atualizando $secret_var"
            export "$secret_var"="$val"
            PROVIDER_SELECT="keepass vault mem" core_secret_service_put "$CLIENT_APP_NAME/$secret_var" "$val" 2>/dev/null || true
        fi
    }

    # --- Mapeamento das Chaves ---
    
    # Básicos
    _sync_yaml_key "jwt_secret"            "OCIS_JWT_SECRET"
    _sync_yaml_key "transfer_secret"       "OCIS_TRANSFER_SECRET"
    _sync_yaml_key "machine_auth_api_key"  "OCIS_MACHINE_AUTH_API_KEY"
    _sync_yaml_key "system_user_id"        "OCIS_SYSTEM_USER_ID"
    _sync_yaml_key "system_user_api_key"   "OCIS_SYSTEM_USER_API_KEY"
    _sync_yaml_key "service_account_id"    "OCIS_SERVICE_ACCOUNT_ID"
    _sync_yaml_key "service_account_secret" "OCIS_SERVICE_ACCOUNT_SECRET"
    
    # Caso especial (Graph ID usa a chave 'id:')
    _sync_yaml_key "id:"                   "OCIS_GRAPH_APPLICATION_ID"

    # Senhas do IDM (Service User Passwords)
    _sync_yaml_key "reva_password"         "OCIS_IDM_REVA_PASSWORD"  "service_user"
    _sync_yaml_key "idm_password"          "OCIS_IDM_IDM_PASSWORD"   "service_user"
    _sync_yaml_key "idp_password"          "OCIS_IDM_IDP_PASSWORD"   "service_user"
    _sync_yaml_key "admin_password"        "OCIS_IDM_ADMIN_PASSWORD" "service_user"

    echo "✅ Segredos sincronizados"
    return 0
}
    
  
cleanup() {
    echo "⚠️  Iniciando limpeza total do oCIS ($CLIENT_APP_NAME)..."
    context || return 1
    app_down
    docker compose down -v
    echo "🧹 Removendo directórias de dados e configuração em $CLIENT_APP_DIR..."
    sudo rm -rf "$CLIENT_APP_DIR/data" "$CLIENT_APP_DIR/config"
    mkdir -p "$CLIENT_APP_DIR/data" "$CLIENT_APP_DIR/config"
    chown -R 1000:1000 "$CLIENT_APP_DIR/data" "$CLIENT_APP_DIR/config" 2>/dev/null
    echo "✅ Limpeza concluída..."
    
    # Copiar trusted-ca.pem se existir
    if [[ -f "../trusted-ca.pem" ]]; then
        mkdir -p "$CLIENT_APP_DIR/config"
        cp "../trusted-ca.pem" "$CLIENT_APP_DIR/config/trusted-ca.pem"
    fi

    app_up    
}

reset_ocis() {
    echo "🔄 Reset do oCIS mantendo segredos..."
    context || return 1
    
    # Parar container
    echo "🛑 Parando container..."
    docker rm -f $CLIENT_APP_CONTAINER_NAME 2>/dev/null || true
    
    # Backup segredos existentes (eles já estão no vault/mem via provision_secrets)
    # Apenas remover config e regenerar
    
    # Remover config (mas não os dados do usuário)
    echo "🧹 Removendo configuração..."
    rm -rf "$CLIENT_APP_DIR/config"/* 2>/dev/null || true
    
    # Copiar trusted-ca.pem se existir
    if [[ -f "../trusted-ca.pem" ]]; then
        mkdir -p "$CLIENT_APP_DIR/config"
        cp "../trusted-ca.pem" "$CLIENT_APP_DIR/config/trusted-ca.pem"
    fi
    
}
on_complete() {
    curl -I -k -H "Host: files.home2500.local" https://files.app-network:9200 | grep -i "content-security-policy"

}

full_reset_ocis() {
    echo "🔄 COMPLETE RESET of oCIS files..."
    context || return 1
    
    # Step 1: Delete vault secrets for files app
    (
        # Recupera o token de forma isolada
        PROVIDER_SELECT="mem" core_secret_service_get "vault/VAULT_TOKEN" 2> /dev/null 
        echo "🗑️  Deleting vault secrets for files..."
        if vault kv list secret/files/ 2>/dev/null | grep -q "^keys"; then
            for key in $(vault kv list -format=json secret/files/ 2>/dev/null | jq -r '.[]' 2>/dev/null); do
                if [[ -n "$key" ]]; then
                    PROVIDER_SELECT="vault keepass" core_secret_service_delete "files/$key"                
                fi
            done
        fi
    )
    
    # Step 2: Delete mem secrets for files app
    echo "🗑️  Deleting mem secrets for files..."
    rm -rf /run/user/1000/home2500/files/* 2>/dev/null || true
    
    reset_ocis
}

funcs() {    
   list_functions ${BASH_SOURCE[0]}
}
