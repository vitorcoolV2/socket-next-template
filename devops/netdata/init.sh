#!/bin/bash
# ../../../devops/<*|app|launcher>/tool.sh

set +e


if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ This is a library and should be sourced, not run directly."
    return 1
fi

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source ../authentik/app/tool.sh

requirements() {
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
    requirements && {      
        echo "🚀 Iniciando Deploy do Stack Fotos..."

        deploy_secrets || return 1

        app_up
    }

}


provision_secrets() {  
    echo ""
    
    #app_create_map_secret_vars "NETDATA_DB_PASSWORD=authentik/AUTHENTIK_REDIS__PASSWORD"
    #core_secret_service_put "netdata/REDIS_PASSWORD" "$REDIS_PASSWORD"
}

deploy_secrets() {
    # 1. Mapeia segredos externos (do Authentik) para o contexto local    
    echo ""
    #core_secret_service_get "netdata/REDIS_PASSWORD" || provision_secrets 
}
