#!/bin/bash
# ../../../devops/<*|app|launcher>/tool.sh

set +e

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ This is a library and should be sourced, not run directly."
    return 1
fi

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Tenta carregar o tool do authentik para usar o sistema de provisionamento de apps
if [[ -f ../authentik/app/tool.sh ]]; then
    source ../authentik/app/tool.sh
else
    echo "❌ Erro: ../authentik/app/tool.sh não encontrado."
    return 1
fi


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

provision_secrets() {
    echo "🔐 Provisionando segredos do Authentik para o oCIS $CLIENT_APP_NAME..." >&2        
    
    _sync() {
        local target="$1" path="$2"
        if ! PROVIDER_SELECT="mem" core_secret_service_get "$CLIENT_APP_NAME/$target" &>/dev/null; then
            local val=""
            if PROVIDER_SELECT="vault" core_secret_service_get "$path" &>/dev/null; then
                local var_name="${path##*/}"
                val="${!var_name}"
            fi
            
                # Validação: se vier "UNDEF", vazio ou for curto demais (falha do vault)
                if [[ -z "$val" || "$val" == *"UNDEF"* || ${#val} -lt 10 ]]; then
                    echo "🎲 Gerando novo segredo para $target (Vault retornou valor inválido)..." >&2
                    if [[ "$target" == *"OIDC_ID" || "$target" == *"SYSTEM_USER_ID" ]]; then
                        val="ocis-$(openssl rand -hex 4)"
                    else
                        val=$(openssl rand -base64 32)
                    fi
                    PROVIDER_SELECT="vault mem" core_secret_service_put "$CLIENT_APP_NAME/$target" "$val" || return 1

            else
                PROVIDER_SELECT="mem" core_secret_service_put "$CLIENT_APP_NAME/$target" "$val" || return 1
            fi
        fi
    }

    ### Sincronizar credenciais geradas pelo Authentik (módulo oidc)
    _sync "CLIENT_APP_OIDC_ID" "$CLIENT_APP_NAME/OIDC_ID" || return 1
    _sync "CLIENT_APP_OIDC_SECRET" "$CLIENT_APP_NAME/OIDC_SECRET" || return 1
    
    ### Provisionar segredos internos do oCIS (JWT e outros)
    for secret in OCIS_JWT_SECRET OCIS_TRANSFER_SECRET OCIS_MACHINE_AUTH_API_KEY OCIS_SYSTEM_USER_API_KEY OCIS_SERVICE_ACCOUNT_SECRET OCIS_LDAP_BIND_PASSWORD OCIS_IDM_SVC_PASSWORD OCIS_IDM_ADMIN_PASSWORD OCIS_IDM_REVA_PASSWORD OCIS_IDM_IDP_PASSWORD OCIS_IDM_IDM_PASSWORD; do
        local current_val=""
        if ! PROVIDER_SELECT="mem" core_secret_service_get "$CLIENT_APP_NAME/$secret" &>/dev/null; then
            PROVIDER_SELECT="vault" core_secret_service_get "$CLIENT_APP_NAME/$secret" &>/dev/null
            current_val="${!secret}"
            
            if [[ -z "$current_val" || ${#current_val} -lt 30 || "$current_val" == *"UNDEF"* ]]; then
                echo "🎲 Gerando novo segredo aleatório para $secret (anterior era inválido, curto ou garbage)..." >&2
                local val=$(openssl rand -base64 32)
                PROVIDER_SELECT="vault mem" core_secret_service_put "$CLIENT_APP_NAME/$secret" "$val" || return 1
            else
                PROVIDER_SELECT="mem" core_secret_service_put "$CLIENT_APP_NAME/$secret" "$current_val" || return 1
            fi
        fi
    done

    # Copiar trusted-ca.pem para a pasta de config local
    if [[ -f "../trusted-ca.pem" ]]; then
        mkdir -p "$CLIENT_APP_DIR/config"
        cat "../trusted-ca.pem" > "$CLIENT_APP_DIR/config/trusted-ca.pem"
    fi

    # OCIS_SYSTEM_USER_ID, OCIS_SERVICE_ACCOUNT_ID e OCIS_GRAPH_APPLICATION_ID devem ser UUIDs.
    for secret in OCIS_SYSTEM_USER_ID OCIS_SERVICE_ACCOUNT_ID OCIS_GRAPH_APPLICATION_ID; do
        if ! PROVIDER_SELECT="mem" core_secret_service_get "$CLIENT_APP_NAME/$secret" &>/dev/null; then
            PROVIDER_SELECT="vault" core_secret_service_get "$CLIENT_APP_NAME/$secret" &>/dev/null
            current_val="${!secret}"
            if [[ -z "$current_val" || ${#current_val} -lt 30 || "$current_val" == *"UNDEF"* ]]; then
                echo "🎲 Gerando UUID para $secret..." >&2
                local val=$(cat /proc/sys/kernel/random/uuid)
                PROVIDER_SELECT="vault mem" core_secret_service_put "$CLIENT_APP_NAME/$secret" "$val" || return 1
            else
                PROVIDER_SELECT="mem" core_secret_service_put "$CLIENT_APP_NAME/$secret" "$current_val" || return 1
            fi
        fi
    done

    # STORAGE IDs (Mount IDs)
    for secret in STORAGE_USERS_MOUNT_ID STORAGE_METADATA_MOUNT_ID STORAGE_SHARES_MOUNT_ID GATEWAY_STORAGE_USERS_MOUNT_ID GATEWAY_STORAGE_METADATA_MOUNT_ID GATEWAY_STORAGE_SHARES_MOUNT_ID; do
        if ! PROVIDER_SELECT="mem" core_secret_service_get "$CLIENT_APP_NAME/$secret" &>/dev/null; then
            PROVIDER_SELECT="vault" core_secret_service_get "$CLIENT_APP_NAME/$secret" &>/dev/null
            current_val="${!secret}"
            if [[ -z "$current_val" || ${#current_val} -lt 30 || "$current_val" == *"UNDEF"* ]]; then
                echo "🎲 Gerando UUID para $secret..." >&2
                local val=$(cat /proc/sys/kernel/random/uuid)
                PROVIDER_SELECT="vault mem" core_secret_service_put "$CLIENT_APP_NAME/$secret" "$val" || return 1
            else
                PROVIDER_SELECT="mem" core_secret_service_put "$CLIENT_APP_NAME/$secret" "$current_val" || return 1
            fi
        fi
    done

    local vars_to_export=(
        CLIENT_APP_OIDC_ID 
        CLIENT_APP_OIDC_SECRET
        OCIS_JWT_SECRET
        OCIS_TRANSFER_SECRET
        OCIS_MACHINE_AUTH_API_KEY
        OCIS_SYSTEM_USER_ID
        OCIS_SYSTEM_USER_API_KEY
        OCIS_SERVICE_ACCOUNT_ID
        OCIS_SERVICE_ACCOUNT_SECRET
        OCIS_LDAP_BIND_PASSWORD
        OCIS_IDM_SVC_PASSWORD
        OCIS_IDM_ADMIN_PASSWORD
        OCIS_IDM_REVA_PASSWORD
        OCIS_IDM_IDP_PASSWORD
        OCIS_IDM_IDM_PASSWORD
        OCIS_GRAPH_APPLICATION_ID
        STORAGE_USERS_MOUNT_ID
        STORAGE_METADATA_MOUNT_ID
        STORAGE_SHARES_MOUNT_ID
        GATEWAY_STORAGE_USERS_MOUNT_ID
        GATEWAY_STORAGE_METADATA_MOUNT_ID
        GATEWAY_STORAGE_SHARES_MOUNT_ID
    )

    for var in "${vars_to_export[@]}"; do
        PROVIDER_SELECT="mem" core_secret_service_get "$CLIENT_APP_NAME/$var" >/dev/null || return 1
    done

    require_vars "${vars_to_export[@]}" || return 1   
    core_secret_export2_env_vars "$CLIENT_APP_NAME" "${vars_to_export[@]}" || return 1
    return 0
}

on_script_fail() { echo "script fail"; return 1; }
on_login_fail() { return 1; }
on_provision_db_fail() { return 1; } 
on_expose_fail() { return 1; }
on_running_fail() { echo "running fail"; return 1; }
on_compose_fail() { return 1; }
on_provision_secrets_fail() { provision_secrets; return 1; }
on_vault_login_fail() { 
    vault_request_stew_token || return 1
}
on_name_register_fail() { return 1; }
on_authentik_login_fail() { require_vars AUTHENTIK_API_TOKEN && ak_api_token_validate || return 1; }
on_blue_apply_fail() { return 1; }
on_outpost_add_fail() { return 1; }
on_certificate_fail() { return 0; }

docker_init() {
    echo "🏗️  Iniciando 'ocis init' via Docker para gerar configuração base..."
    context || return 1
    provision_secrets || return 1
    
    local secret_file=$(core_secret_mapper_mem "$CLIENT_APP_NAME" ".secret")
    require_files secret_file || return 1

    docker run --rm \
        -v "$CLIENT_APP_DIR/config:/etc/ocis" \
        -v "$CLIENT_APP_DIR/data:/var/lib/ocis" \
        --user $(id -u):$(id -g) \
        --env-file "$secret_file" \
        -e OCIS_INSECURE=true \
        owncloud/ocis init || return 1
        
    echo "✅ Configuração inicializada em $CLIENT_APP_DIR/config"
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
    provision_secrets 
}

funcs() {    
   list_functions ${BASH_SOURCE[0]}
}
