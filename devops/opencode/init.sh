#!/bin/bash
# ../../../devops/<*|app|launcher>/tool.sh

set +e


if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ This is a library and should be sourced, not run directly."
    return 1
fi

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"



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
    local stage="$1" # 
    local console="$2"
    

    core_log_error "Falha crítica no estado 'running' do contentor: $CLIENT_APP_CONTAINER_NAME"
    
    # Mostrar logs para dar contexto à decisão
    docker logs --tail 30 "$CLIENT_APP_CONTAINER_NAME"

    # Pergunta ao Steward se quer tentar o Recovery Workflow
    if ask "Desejas tentar o 'retry state running' (limpeza + restart)?" true; then
        core_log_info "Iniciando 'tool_stage_workflow running'..."
        
        # Limpeza de segurança antes do retry
        docker compose stop "$CLIENT_APP_CONTAINER_NAME" 2>/dev/null
        # Opcional: remover ficheiros de erro do opencode.json se for esse o caso
        
        if tool_stage_workflow "running"; then
            core_log_info "Serviço recuperado com sucesso!"
            return 0
        else
            core_log_error "O retry falhou novamente."
        fi
    fi

    core_log_error "Workflow interrompido pelo utilizador ou falha persistente."
    return 1
}
on_compose_fail() {
    echo "compose config fail"
    echo "review compose file: $(core_relative_path2 $CLIENT_APP_COMPOSE_FILE)"    
    return 1
}

on_vault_login_fail() {
    local stage="$1"
    local console="$2"
    local whyJson="$3" # run stack info. allways under discution, when client on_*stage-event*_fail. it is Developers know has to be notified and trigger response

    #echo $whyJson | jq .
    vault_request_token steward
    echo "x"
    vault_validate_token || return 1
    echo "x2"
    return 0
}
on_outpost_add_success() {
    local stage="$1"
    local console="$2"
    #tool_report_stack__DRY3_analitical_json "$stage" "$console"
    return 0
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

on_provision_oidc_fail() {
    return 0
}

on_certificate_fail() {
    return 0
}
on_provision_secrets_fail() {  
    echo "provision secrets fail"
    provision_secrets || return 1
}
on_provision_user_fail() {
    echo "provision user fail"
    provision_secrets || return 1
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
        unset APP_USER APP_UID APP_GUI
        core_transform_inject_env_file_vars "$CLIENT_APP_ENV_FILE";

        PROVIDER_SELECT="mem" core_secret_service_put "$CLIENT_APP_NAME/APP_USER" "$APP_USER"
        PROVIDER_SELECT="mem" core_secret_service_put "$CLIENT_APP_NAME/APP_UID" "$APP_UID"
        PROVIDER_SELECT="mem" core_secret_service_put "$CLIENT_APP_NAME/APP_GID" "$APP_GID"
        # Nota: CLIENT_APP_NAME deve estar definido no teu .env ou shell
        PROVIDER_SELECT="mem" core_secret_service_put "$CLIENT_APP_NAME/OWNER" "$(whoami)"
        PROVIDER_SELECT="mem" core_secret_service_put "$CLIENT_APP_NAME/OWNER_UID" "$UID"
        PROVIDER_SELECT="mem" core_secret_service_put "$CLIENT_APP_NAME/OWNER_GID" "$(id -g)"
        
        show_vars \
            APP_USER \
            APP_UID \
            APP_GID \
            OWNER \
            OWNER_UID \
            OWNER_GID
            
        FROM="vault" TO="mem" tool_provision__secret_vars \
            "OPENCODE_SERVER_PASSWORD=$CLIENT_APP_NAME/OPENCODE_SERVER_PASSWORD" \
        || return 1

    ) || return 1

    return 0
}
on_deploy_secrets_fail(){
    kp test || echo "keepass fail test. Lets handle another stable wrapper"
    vault_validate_token
    return 1
}
on_complete() {
    tool_report_stack__analitical_jsonV1
    return 0
}

funcs() {    
   list_functions ${BASH_SOURCE[0]}
}

prepare() {
    docker compose down --remove-orphans
    docker system prune -f  # Limpa cache não utilizada
    # Opcional: apagar volumes de socket/tmp se estiverem presos
    sudo rm -rf /run/user/2500/home2500/*
    kp test
    source ../authentik/app/tool.sh    
}

on_build_image_fail() {
    core_log_error "Falha crítica no build da imagem para $CLIENT_APP_CONTAINER_NAME"
    
    # Limpar cache de build corrompida para evitar persistência do erro
    core_log_info "Tentando limpar cache de build..."
    docker builder prune -f --filter "until=1h"
    
    # Notificar sistema de monitorização ou paragem forçada
    return 1
}

source ../authentik/app/tool.sh