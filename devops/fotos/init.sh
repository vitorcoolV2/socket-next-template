#!/bin/bash
# ../../../devops/<*|app|launcher>/tool.sh

set +e


if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ This is a library and should be sourced, not run directly."
    return 1
fi

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
        echo "🚀 Iniciando Deploy do Stack Fotos..."
        
        app_up
    }

}
watch_immich_recovery() {
    echo "👀 A monitorizar recuperação do Immich..."
    while true; do
        local status=$(docker inspect --format='{{.State.Health.Status}}' authentik-db 2>/dev/null)
        local logs=$(docker logs --tail 5 immich-server 2>&1)

        if [[ "$status" == "unhealthy" ]]; then
            echo -e "❌ [authentik-db] ainda UNHEALTHY. A corrigir healthcheck..."
        elif [[ "$logs" == *"maintenance mode"* ]]; then
            echo -e "⏳ [immich-server] ainda em modo de manutenção..."
        else
            echo -e "✅ [SISTEMA] Parece que estabilizou!"
            break
        fi
        sleep 5
    done
}
on_script_fail() {
    echo "script fail"
    return 1
}
on_login_fail() {
    echo "credential fail. checkout why"
    require_vars VAULT_TOKEN && vault_validate_token
    require_vars AUTHENTIK_API_TOKEN && ak_api_token_validate
    return 1    
    #app_login || return 1    
}
on_provision_db_fail() {
    echo "provision_db fail"
    app_db_schema

    docker logs --tail 100 authentik-db

    docker inspect authentik-db | jq '.[0].State.Health'

    return 1
}
on_expose_fail() {
    echo "exposing fail"
    return 1
}
on_running_fail() {
    echo "running fail"    
    local secret_file=$(core_secret_mapper_mem "$CLIENT_APP_NAME" ".secret")            
         
    if env $(grep -v '^#' $secret_file | xargs)  docker compose -f "$CLIENT_APP_COMPOSE_FILE" config --quiet; then
        return 1
    fi        
    recover_maintenance() {
        echo -e "🔧 Tentando recuperar $CLIENT_APP_CONTAINER_NAME..."
        
        # 1. Tentar reiniciar (às vezes limpa o lock de manutenção)
        docker restart "$CLIENT_APP_CONTAINER_NAME"
        
        # 2. Aguardar 10s e verificar status
        sleep 10
    }
    
    if docker container logs "$CLIENT_APP_CONTAINER_NAME" | grep -q "maintenance mode"; then
        echo -e "⚠️  Ainda em manutenção. Verifique o link de token nos logs."
        # Extrai o token automaticamente para ti
        docker container logs "$CLIENT_APP_CONTAINER_NAME" | grep "token=" | tail -n 1
    else
        echo -e "✅ Parece ter saído do modo de manutenção!"
    fi
    # 2. Verifica se ele está a tentar migrar a BD
    docker container logs --tail 20 $CLIENT_APP_CONTAINER_NAME

    local link=$(docker container logs $CLIENT_APP_CONTAINER_NAME 2>&1 | grep "token=" | grep -v "ExperimentalWarning" | tail -n 1 | sed 's/.*https/https/')

    if [[ -n "$link" ]]; then
        echo -e "\e[1;33m🛠️  Immich em Manutenção. Link de Admin:\e[0m"
        echo -e "\e[4;34m$link\e[0m"
    fi
    return 1
}
on_compose_fail() {
    echo "compose config fail"

    echo "review compose file: $(core_relative_path2 $CLIENT_APP_COMPOSE_FILE)"    
    tree /run/user/1000/home2500/$CLIENT_APP_NAME
    return 1
}
on_provision_secrets_fail() {  
    echo "provision secrets fail"
    provision_secrets
    return 1
}
on_vault_login_fail() {    
    vault_request_stew_token || return 1
}
on_name_register_fail() {
    echo "name resolve or registring fail"
    return 1
}
on_authentik_login_fail() {
    echo "authentik api token"
    kp test && kp open
    ak_api_token_validate || ak_api_token_generate return 1
}
on_blue_apply_fail() {
    echo "blue apply fail"
    echo "Checkout $AUTHENTIK_URL/if/admin/#/administration/system-tasks"
    return 1
}

on_outpost_add_fail() {
    echo "blue apply fail"
    return 1
}

on_certificate_fail() {
    return 0 # continue without create certificate
}

provision_secrets() {
    echo "🔐 Provisionando segredos do Authentik para o Immich..." >&2        
    (
        # Define o contexto da aplicação (caso ainda não esteja definido no escopo)
        require_vars CLIENT_APP_NAME || return 1
        
        PROVIDER_SELECT="vault" core_secret_service_get "$CLIENT_APP_NAME/REDIS_PASSWORD" || \
            TO="vault" FROM="vault" tool_provision__secret_vars \
                "REDIS_PASSWORD=authentik/AUTHENTIK_REDIS__PASSWORD" \
            || return 1        
        return 0
                  
    ) || return 1

}

### just return list of secrets provision
deploy_secrets() {
    require_vars CLIENT_APP_NAME || return 1

    (            
        FROM="vault" TO="mem" tool_provision__secret_vars \
            "REDIS_PASSWORD=$CLIENT_APP_NAME/REDIS_PASSWORD" \
            "IMMICH_OAUTH_CLIENT_ID=$CLIENT_APP_NAME/OIDC_ID" \
            "IMMICH_OAUTH_CLIENT_SECRET=$CLIENT_APP_NAME/OIDC_SECRET" \
        || return 1

    ) || return 1

    return 0
}
on_deploy_secrets_fail() {
    return 1
}

on_provision_oidc_fail() {
    return 1
}

funcs() {    
   list_functions ${BASH_SOURCE[0]}
}