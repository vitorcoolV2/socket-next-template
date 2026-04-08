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

on_script_fail() {
    echo "script fail"
    return 1
}
on_login_fail() {
    echo "credential fail. checkout why"
    require_vars VAULT_TOKEN && (vault_validate_token)
    require_vars AUTHENTIK_API_TOKEN && (ak_api_token_validate)
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
    local container_id="$CLIENT_APP_CONTAINER_NAME"

    recover_maintenance() {
        echo -e "🔧 Tentando recuperar $container_id..."
        
        # 1. Tentar reiniciar (às vezes limpa o lock de manutenção)
        docker restart "$container_id"
        
        # 2. Aguardar 10s e verificar status
        sleep 10
    }

    docker logs --tail 20 $container_id


    return 1
}
on_compose_fail() {
    echo "review compose file: $(core_relative_path2 $CLIENT_APP_COMPOSE_FILE)"    
    return 1
}
on_provision_secrets_fail() {  
    echo "provision secrets fail"
    return 1
}
provision_secrets() {
    echo "🔐 Provisionando segredos do Authentik para o Immich..." >&2
    require_vars CLIENT_APP_NAME || return 1
    
    (
        tool_provision__secret_vars "REDIS_PASSWORD=authentik/AUTHENTIK_REDIS__PASSWORD" && \
        core_secret_service_put "$CLIENT_APP_NAME/REDIS_PASSWORD" "$REDIS_PASSWORD" || \
            return 1
    )
}
PROVIDER_SELECT="vault" core_secret_service_get  "fotos/db_fotos__role_admin"
deploy_secrets() {
    require_vars CLIENT_APP_NAME || return 1
    core_secret_export2_env_vars "$CLIENT_APP_NAME/.secret" \
        "REDIS_PASSWORD" \
        "IMMICH_AUTH_CLIENT_ID" \
        "IMMICH_AUTH_CLIENT_SECRET" || return 1

    return 0
}

funcs() {    
   list_functions ${BASH_SOURCE[0]}
}