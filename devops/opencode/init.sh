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
        echo "🚀 Iniciando Deploy do Stack OpenCode..."
        
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
    echo "provision_db fail - opencode has no DB"
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
    echo "provision secrets fail"
    provision_secrets || return 1
}
on_vault_login_fail() {
    vault_request_stew_token || return 1
    ak_api_token_restore || return 1
}
on_name_register_fail() {
    echo "name resolve or registring fail"
    return 1
}
on_authentik_login_fail() {
    
    if ak_api_token_restore && ak_api_token_validate; then
        return 0
    else
        echo "authentik api token restore failed. try generate one:
        ak_api_token_generate"
        return 1
    fi
}
on_blue_apply_fail() {
    echo "blue apply fail - not required for opencode"
    return 0
}

on_outpost_add_fail() {
    echo "outpost add fail - not required for opencode"
    return 0
}

on_certificate_fail() {
    return 0
}

provision_secrets() {
    echo "🔐 Provisioning OpenCode server password..." >&2        
    require_vars CLIENT_APP_NAME || return 1

    PROVIDER_SELECT="keepass" core_secret_service_get "$CLIENT_APP_NAME/OPENCODE_SERVER_PASSWORD" || \
        TO="keepass" FROM="vault" tool_provision__secret_vars \
            "OPENCODE_SERVER_PASSWORD=opencode/OPENCODE_SERVER_PASSWORD" \
        || return 1
        
    return 0
}

deploy_secrets() {
    require_vars CLIENT_APP_NAME || return 1

    (
        FROM="vault" TO="mem" tool_provision__secret_vars \
            "OPENCODE_SERVER_PASSWORD=$CLIENT_APP_NAME/OPENCODE_SERVER_PASSWORD" \
        || return 1

    ) || return 1

    return 0
}

funcs() {    
   list_functions ${BASH_SOURCE[0]}
}
