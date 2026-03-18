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
        echo "🚀 Iniciando Deploy do Stack Backup..."
        
        app_up
    }
}

on_script_fail() {
    echo "script fail"
    return 1
}
on_login_fail() {
    echo "credential fail"
    return 1
}
on_provision_db_fail() {
    echo "provision_db fail - backup has no DB"
    return 0
}
on_expose_fail() {
    echo "exposing fail"
    return 1
}
on_running_fail() {
    echo "running fail"    
    local container_id="$CLIENT_APP_CONTAINER_NAME"

    docker logs --tail 20 $container_id

    return 1
}
on_compose_fail() {
    echo "compose config fail"
    echo "review compose file: $(core_relative_path2 $CLIENT_APP_COMPOSE_FILE)"    
    return 1
}
on_provision_secrets_fail() {  
    echo "provision secrets fail - backup has no secrets"
    return 0
}
on_vault_login_fail() {
    echo "vault login fail - not required for backup"
    return 0
}
on_name_register_fail() {
    echo "name resolve or registring fail"
    return 1
}
on_authentik_login_fail() {
    echo "authentik api token - not required (no blue apply)"
    return 0
}
on_blue_apply_fail() {
    echo "blue apply fail - not required for backup"
    return 0
}

on_outpost_add_fail() {
    echo "outpost add fail - not required for backup"
    return 0
}

on_certificate_fail() {
    return 0
}

provision_secrets() {
    echo "🔐 Backup has no secrets (auth disabled)"
    return 0
}

deploy_secrets() {
    echo "deploy secrets - not required for backup"
    return 0
}

funcs() {    
   list_functions ${BASH_SOURCE[0]}
}
