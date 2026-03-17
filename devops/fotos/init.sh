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
    local container_id="$CLIENT_APP_CONTAINER_NAME"

    recover_maintenance() {
        echo -e "🔧 Tentando recuperar Immich..."
        
        # 1. Tentar reiniciar (às vezes limpa o lock de manutenção)
        docker restart "$container_id"
        
        # 2. Aguardar 10s e verificar status
        sleep 10
    }
    
    if docker container logs "$container_id" | grep -q "maintenance mode"; then
        echo -e "⚠️  Ainda em manutenção. Verifique o link de token nos logs."
        # Extrai o token automaticamente para ti
        docker container logs "$container_id" | grep "token=" | tail -n 1
    else
        echo -e "✅ Parece ter saído do modo de manutenção!"
    fi
    # 2. Verifica se ele está a tentar migrar a BD
    docker container logs --tail 20 $container_id

    local immich_link=$(docker container logs $container_id 2>&1 | grep "token=" | grep -v "ExperimentalWarning" | tail -n 1 | sed 's/.*https/https/')

    if [[ -n "$immich_link" ]]; then
        echo -e "\e[1;33m🛠️  Immich em Manutenção. Link de Admin:\e[0m"
        echo -e "\e[4;34m$immich_link\e[0m"
    fi
    return 1
}
on_compose_fail() {
    echo "compose config fail"

    echo "review compose file: $(core_relative_path2 $CLIENT_APP_COMPOSE_FILE)"    
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
    require_vars AUTHENTIK_API_TOKEN && ak_api_token_validate || return 1
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
        # Sub-função interna para evitar repetição (DRY)
        # Uso: _sync "nome_na_memoria" "caminho_no_vault"
        _sync() {
            local target="$1" path="$2"
            if ! PROVIDER_SELECT="mem" core_secret_service_get "$CLIENT_APP_NAME/$target" &>/dev/null; then
                if PROVIDER_SELECT="vault" core_secret_service_get "$path"; then
                    # O core_secret_service_get costuma exportar a variável com o nome da última parte do path
                    # Precisamos garantir que o valor vai para a variável correta antes do put
                    local var_name="${path##*/}"
                    local val="${!var_name}"
                    PROVIDER_SELECT="mem" core_secret_service_put "$CLIENT_APP_NAME/$target" "$val" || return 1
                else
                    echo "❌ Erro: Falha ao obter $path do Vault" >&2
                    return 1
                fi
            fi
        }

        ### 1. Sincronizar segredos externos
        _sync "REDIS__PASSWORD" "authentik/AUTHENTIK_REDIS__PASSWORD" || return 1
        _sync "CLIENT_APP_OIDC_ID" "$CLIENT_APP_NAME/CLIENT_APP_OIDC_ID" || return 1
        _sync "CLIENT_APP_OIDC_SECRET" "$CLIENT_APP_NAME/CLIENT_APP_OIDC_SECRET" || return 1
        
        ### 2. Sincronizar credenciais de DB
        if ! PROVIDER_SELECT="mem" core_secret_service_get "$CLIENT_APP_NAME/DB_ROLE_ADMIN_PASS" &>/dev/null; then
            if _db_role_get_credentials "admin"; then
                PROVIDER_SELECT="mem" core_secret_service_put "$CLIENT_APP_NAME/DB_ROLE_ADMIN_PASS" "$DB_ROLE_ADMIN_PASS" || return 1
            else
                echo "❌ Erro: Não foi possível obter credenciais DB admin" >&2
                return 1
            fi
        fi

        ### 3. Exportação Final para o ficheiro .secret
        # Nota: Corrigi IMMICH_AUTH_CLIENT_ID para CLIENT_APP_OIDC_ID para manter consistência
        local vars_to_export=(
            DB_ROLE_ADMIN_PASS 
            REDIS__PASSWORD 
            CLIENT_APP_OIDC_ID 
            CLIENT_APP_OIDC_SECRET
        )

        # Garante que as variáveis estão no ambiente da subshell para o export2_env_vars
        for var in "${vars_to_export[@]}"; do
            PROVIDER_SELECT="mem" core_secret_service_get "$CLIENT_APP_NAME/$var" >/dev/null || return 1
        done
        #### write .secret file
        require_vars "${vars_to_export[@]}" || return 1   
        core_secret_export2_env_vars "$CLIENT_APP_NAME" "${vars_to_export[@]}" || return 1
        return 0
                  
    ) || return 1

}

xxxprovision_secretsxxxx_____later___im_so_____() {  
    echo "🔐 Provisionando segredos do Authentik para o Immich..." >&2
    require_vars CLIENT_APP_NAME AUTHENTIK_API_TOKEN AUTHENTIK_URL || return 1

    # 1. Redis Secret (Já está funcional)
    app_create_map_secret_vars "REDIS_PASSWORD=authentik/AUTHENTIK_REDIS__PASSWORD"  
    core_secret_service_put "$CLIENT_APP_NAME/REDIS_PASSWORD" "$REDIS_PASSWORD"

    # 2. Obter credenciais do Authentik com Retry (O server pode demorar a indexar)
    local client_id="null"
    local client_secret="null"
    local count=0

    echo "📡 Consultando API do Authentik para $CLIENT_APP_NAME-provider..." >&2
    while [[ "$client_id" == "null" || -z "$client_id" ]]; do
        local provider_data
        provider_data=$(curl -s -k -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
            "$AUTHENTIK_URL/api/v3/providers/oauth2/?search=$CLIENT_APP_NAME-provider")
        
        client_id=$(echo "$provider_data" | jq -r '.results[0].client_id // "null"')
        client_secret=$(echo "$provider_data" | jq -r '.results[0].client_secret // "null"')

        if [[ "$client_id" != "null" ]]; then break; fi
        
        ((count++))
        if [[ $count -gt 5 ]]; then
            echo "❌ Erro: Timeout ao esperar pelas credenciais do Authentik." >&2
            return 1
        fi
        echo "⏳ Aguardando indexação do provider (tentativa $count)..." >&2
        sleep 2
    done

    # 3. Persistência nos 3 níveis (Env, Vault, KeePass)
    # Evitamos o >> .env para não duplicar linhas em múltiplos runs
    sed -i "/^IMMICH_AUTH_CLIENT_ID=/d" .env 2>/dev/null || true
    sed -i "/^IMMICH_AUTH_CLIENT_SECRET=/d" .env 2>/dev/null || true
    echo "IMMICH_AUTH_CLIENT_ID=$client_id" >> .env
    echo "IMMICH_AUTH_CLIENT_SECRET=$client_secret" >> .env
    
    core_secret_service_put "$CLIENT_APP_NAME/IMMICH_AUTH_CLIENT_ID" "$client_id"
    core_secret_service_put "$CLIENT_APP_NAME/IMMICH_AUTH_CLIENT_SECRET" "$client_secret"
    
    echo "✅ Segredos OIDC injetados: ID=${#client_id} chars, Secret=${#client_secret} chars" >&2
}

deploy_secrets() {
    require_vars CLIENT_APP_NAME || return 1
    core_secret_export2_env_vars "$CLIENT_APP_NAME" \
        "REDIS_PASSWORD" \
        "IMMICH_AUTH_CLIENT_ID" \
        "IMMICH_AUTH_CLIENT_SECRET" || return 1

    return 0
}

funcs() {    
   list_functions ${BASH_SOURCE[0]}
}