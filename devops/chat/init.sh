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
        echo "🚀 Iniciando Deploy do Stack Chat..."
        
        app_up
    }

}
on_vault_login_fail() { 
    kp test || kp open
    vault_request_stew_token || return 1
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
    return 1
}
on_provision_oidc_fail() {
    echo "provision_oidc fail"
    return 1
}
on_expose_fail() {
    echo "exposing fail"
    return 1
}
on_deploy_secrets_fail() {
    echo "deploy secrets fail"
    return 1
}
on_name_register_fail() {
    echo "name register  fail"
    return 1
}
on_authentik_login_fail() {
    echo "authentik login fail"
    return 1
}
on_blue_apply_fail() {
    echo "authentik login fail"
    return 1
}
on_outpost_add_fail() {
    echo "authentik login fail"
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
    echo "🔐 Provisionando segredos master do $CLIENT_APP_NAME..." >&2        
    
    local secrets=("WEBUI_SECRET_KEY" "OIDC_ID" "OIDC_SECRET")
    local secret_val=""
    (
        if kp open; then
            echo "🔑 KeePass aberto: Sincronizando com Vault..." >&2
            for secret in "${secrets[@]}"; do
                # 1. Busca no KeePass primeiro
                if PROVIDER_SELECT="keepass" core_secret_service_get "$CLIENT_APP_NAME/$secret" 2>/dev/null; then
                    secret_val="${!secret}"
                    secret_val=$(echo "$secret_val" | tr -d '\n\r ')

                    if [[ -n "$secret_val" && "$secret_val" != *"UNDEF"* ]]; then
                        # 2. Compara/Atualiza o Vault para garantir paridade
                        # (Se o valor no Vault for diferente, o put sobrescreve)
                        PROVIDER_SELECT="vault" core_secret_service_put "$CLIENT_APP_NAME/$secret" "$secret_val" 2>/dev/null                                        
                        continue
                    fi
                fi
                
                # Se não achou no KP, tenta no Vault como fallback
                if ! PROVIDER_SELECT="vault" core_secret_service_get "$CLIENT_APP_NAME/$secret" 2>/dev/null; then            
                    echo "⚠️  Aviso: $secret não encontrado em keepass ou vault!" >&2
                    echo "🎲 Gerando nova $secret segura..." >&2
                    if [[ "$secret" == *"ID" ]]; then
                        secret_val=$(cat /proc/sys/kernel/random/uuid)
                    else
                        secret_val=$(openssl rand -hex 32)
                    fi
                    printf -v "$secret" "%s" "$secret_val"
                    
                    # Salva em todos os provedores para persistência
                    PROVIDER_SELECT="keepass vault" core_secret_service_put "$CLIENT_APP_NAME/$secret" "$secret_val" 2>/dev/null || return 1
                            # Aqui você pode decidir se chama a função de geração de novos segredos ou se falha.
                fi
            done
        else
            echo "🛡️  KeePass fechado: Operando apenas via Vault..." >&2
            for secret in "${secrets[@]}"; do
                # Carrega estritamente do Vault
                if ! PROVIDER_SELECT="vault" core_secret_service_get "$CLIENT_APP_NAME/$secret" 2>/dev/null; then
                    echo "❌ Erro crítico: Segredo $secret não encontrado no Vault e KeePass está fechado!" >&2
                    return 1
                fi
                
                # Validação do valor carregado
                secret_val="${!secret}"
                if [[ -z "$secret_val" || "$secret_val" == *"UNDEF"* ]]; then
                    echo "❌ Erro: Valor para $secret no Vault é inválido/vazio." >&2
                    return 1
                fi            
            done
        fi
    ) || return 1
    return 0
}

deploy_secrets() {    
    (            
        FROM="vault" TO="mem" tool_provision__secret_vars \
            "WEBUI_SECRET_KEY=$CLIENT_APP_NAME/WEBUI_SECRET_KEY" \
            "OIDC_ID=$CLIENT_APP_NAME/OIDC_ID" \
            "OIDC_SECRET=$CLIENT_APP_NAME/OIDC_SECRET" \
        || return 1

    ) || return 1
    
    
    return 0
}
on_provision_user_fail() {
    return 1
}

funcs() {    
   list_functions ${BASH_SOURCE[0]}
}


on_complete() {
    return 0
    if [[ "$CLIENT_APP_BLUE_TEMPLATE_MODULE" == "proxy" ]]; then                
        require_service_redirect_auth "$CLIENT_APP_NAME" || return 1            
    fi
    if [[ "$CLIENT_APP_BLUE_TEMPLATE_MODULE" == "oidc"* ]]; then                
        app_oidc_validate "$CLIENT_APP_NAME" || return 1
    fi      
}

reset_secret() {
    echo "🔄 RESET SECRETS of $CLIENT_APP_NAME..."
    context || return 1
    
    # Step 1: Delete vault secrets for files app
    (
        # Recupera o token de forma isolada
        PROVIDER_SELECT="mem" core_secret_service_get "vault/VAULT_TOKEN" 2> /dev/null 
        echo "🗑️  Deleting vault secrets for files..."
        if vault kv list secret/$CLIENT_APP_NAME/ 2>/dev/null | grep -q "^keys"; then
            for key in $(vault kv list -format=json secret/$CLIENT_APP_NAME/ 2>/dev/null | jq -r '.[]' 2>/dev/null); do
                if [[ -n "$key" ]]; then
                    PROVIDER_SELECT="vault keepass" core_secret_service_delete "$CLIENT_APP_NAME/$key"                
                fi
            done
        fi
    )
    
    # Step 2: Delete mem secrets for chat app
    echo "🗑️  Deleting mem secrets for $CLIENT_APP_NAME..."
    rm -rf /run/user/1000/home2500/$CLIENT_APP_NAME/* 2>/dev/null || true
}