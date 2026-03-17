# tool.sh # the client app



export CLIENT_APP_DIR="$(pwd)"
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ This is a library and should be sourced, not run directly."
    #return 1
fi

TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_NAME=$(basename ${BASH_SOURCE[0]})

export CLIENT_APP_NAME=$(basename $CLIENT_APP_DIR)

tool_prepare__script_name() {
    # 1. Busca arquivos .sh que contenham a definição da função deploy()
    # Usamos -l para listar apenas o nome do arquivo e -E para a regex
    local found_script
    found_script=$(grep -lE "^deploy\(\) *\{" "$CLIENT_APP_DIR"/*.sh 2>/dev/null | head -n 1)

    # 2. Validação usando sua lógica de require_files
    # Nota: require_files geralmente espera o valor da variável ou o nome dela
    if [[ -n "$found_script" ]]; then        
        export CLIENT_APP_SCRIPT_NAME=$(basename "$found_script")
    else
        # Se não achar, o echo vai para o stderr para não sujar a variável exportada
        local _base_init="$TOOL_DIR/client/CLIENT_APP_NAME--base-init.sh"
        local init_script="$CLIENT_APP_DIR/init.sh"
        ## before ask
        show_vars init_script _base_init && \
            require_files _base_init || return 1
        if ask_provision "init script"; then
            cp "$_base_init" "$init_script"
            chmod 770 "$init_script"
            require_files init_script || return 1            
        else
            return 1
        fi        
    fi    
    
}
tool_prepare__script_name
# Exportando o resultado


echo "
🚀 Home2500 $CLIENT_APP_NAME client script ($CLIENT_APP_SCRIPT_NAME)
   🛡️  Supported by -> ../authentik/app/$TOOL_NAME
      📂  $TOOL_DIR
"


export CLIENT_APP_COMPOSE_FILE="$CLIENT_APP_DIR/docker-compose.yaml"
export CLIENT_APP_ENV_FILE="$CLIENT_APP_DIR/.env"

export CLIENT_APP_BLUEPRINT_SLUG="CLIENT_APP_NAME"
### LOAD CORE
set +e
#### lets require a service tool to deploy compose and expose as blue(oidc) authentik vault
### LOAD BLUEPRINT/AUTHENTIK/VAULT/KEEPASS/CORE (stack)
source $(realpath "$TOOL_DIR/../../authentik/_1-blueprints_lib.sh") > /dev/null 2>&1 



require_functions ak_fix_proxied_redir || {

    echo "Import check. hops. taka a loop at requirements 
    
    " 
    return 1
}

## LOAD client app project dir
cd $CLIENT_APP_DIR

require_locations CLIENT_APP_DIR

## prompt load only vars prefixe with APP_* .env ,parse key=val => "CLIENT_$key=$val"

require_vars DOMAIN \
    INTERNAL_DOMAIN \
    AUTHENTIK_DIR \
    AUTHENTIK_URL | return 1 ### ctx essencial

# Agora as templates (certifica-te que CLIENT_APP_NAME está definido, ex: CLIENT_APP_NAME="netdata")


#show_vars TOOL_APPLY_TEMPLATE TOOL_CLEANUP_TEMPLATE CLIENT_APP_BLUE_APPLY_TPL CLIENT_APP_BLUE_CLEANUP_TPL
# load client app env file
# new service need a port to comunicate and a aditional app

# requirements
### inthis func let y setup apply/cleanup acording to app/blueprints/** "template name"

## if template tool not defined


app_context() {
    require_vars INTERNAL_DOMAIN DOMAIN

    tool_stage_workflow
    
    show_vars \
        CLIENT_APP_NAME \
        CLIENT_APP_DIR \
        CLIENT_APP_BLUE_LABEL \
        CLIENT_APP_BLUE_GROUP \
        CLIENT_APP_CONTAINER_NAME \
        CLIENT_APP_SERVICE_IP \
        CLIENT_APP_SERVICE_PORT \
        CLIENT_APP_BLUE_APPLY_TPL \
        CLIENT_APP_BLUE_CLEANUP_TPL \
        CLIENT_APP_BLUE_APPLY \
        CLIENT_APP_BLUE_CLEANUP \
        CLIENT_APP_COMPOSE_FILE
    show_vars \
        CLIENT_APP_COMPOSE_FILE \
        CLIENT_APP_BLUE_TEMPLATE_MODULE \
        CLIENT_APP_BLUE_APPLY \
        CLIENT_APP_BLUE_CLEANUP \
        CLIENT_APP_ENV_FILE 
       

} 

# 2. Identificar a service_key baseada compose services[] having .container_name| container with predicatable name

### the script invgest transformed var
export TOOL__CLIENT_APP__VAR_PATTERN="ENV.*|DIR|NAME|SERVICE_IP|BLUEPRINT_TPL|CLEANUP_TPL"
tool_prepare__env_vars() {
    # 1. Tentar carregar se o ficheiro já existir
    if [[ -f "$CLIENT_APP_ENV_FILE" ]]; then
        # Limpeza preventiva
        unset \
            CLIENT_APP_DB_NAME \
            CLIENT_APP_BLUE_LABEL \
            CLIENT_APP_BLUE_GROUP

        local match_prefix_exceptions="${4:-$TOOL__CLIENT_APP__VAR_PATTERN}"
        
        core_transform_inject_env_file_vars \
            "$CLIENT_APP_ENV_FILE" \
            "APP_" \
            "CLIENT_APP_" \
            "$match_prefix_exceptions"

        _resolve_compose__container_name
    else
        # 2. Se não existe, tentamos resolver o nome via Compose primeiro para popular o exemplo
        _resolve_compose__container_name
        
        # Validamos se temos o nome do container antes de sugerir o provisionamento
        if [[ -n "$CLIENT_APP_CONTAINER_NAME" ]] && ask_provision ".env file para $CLIENT_APP_NAME"; then   
            
            # Usamos um Here-Doc limpo para evitar problemas de indentação no ficheiro gerado
            cat <<EOF > "$CLIENT_APP_ENV_FILE"
APP_BLUE_GROUP=${CLIENT_APP_BLUE_GROUP:-Ferramentas}
APP_CONTAINER_NAME=${CLIENT_APP_CONTAINER_NAME}
## optional
# APP_SERVICE_PORT=80
# APP_BLUE_LABEL=$(app_blue_label_fallback "$CLIENT_APP_NAME") 
# APP_BLUE_TEMPLATE_MODULE=${CLIENT_APP_BLUE_TEMPLATE_MODULE:-proxy}
# APP_BLUE_META_DESCRIPTION=Service image: $(_get_compose__container_entry | jq ".image")
# APP_DB_NAME=$CLIENT_APP_NAME
EOF
                                                            
            chmod 770 "$CLIENT_APP_ENV_FILE"
            
            # Recarregar as variáveis após criar o ficheiro
            tool_prepare__env_vars "$@"
        else        
            echo "❌ Erro: Não foi possível determinar o CLIENT_APP_CONTAINER_NAME ou o utilizador recusou o provisionamento." >&2
            return 1
        fi        
    fi        
}


_resolve_compose__container_name() {
    # 1. Early exit se já resolvida       
    [[ -n "$CLIENT_APP_CONTAINER_NAME" ]] && return 0

    local c_name="${CLIENT_APP_CONTAINER_NAME:-$CLIENT_APP_NAME}"

    # Obtemos o JSON do compose (cache em variável se necessário para performance)
    _container_name() {
        local container_name="$1"
        require_vars container_name
        local compose_json
        compose_json=$(_get_compose_file_json)
        echo "$compose_json" | jq -r --arg app "$container_name" '
            .services
            | to_entries[]
            | select(
                (.value.container_name == $app) or
                (.value.service_name == $app) or
                (.key == $app)
            )
            | .key
        ' | head -n 1 || echo "null"
    }
    local service_key=$(_container_name "$container_name")
    show_vars service_key || return 1
    # 3. Validação do resultado
    if [[ -z "$service_key" || "$service_key" == "null" ]]; then
        echo -e "⚠️  \e[33mWarning:\e[0m No service match for \e[1m$CLIENT_APP_NAME\e[0m in JSON." >&2
        [[ -z "$CLIENT_APP_CONTAINER_NAME" ]] && return 1
    fi

    # 4. Feedback e Export
    if [[ "$service_key" == "$CLIENT_APP_NAME" ]]; then            
        echo -e "✅ Found aligned service: \e[32m$service_key\e[0m" >&2    
    else
        echo -e "💡 \e[35mNote:\e[0m Mapping \e[1m$CLIENT_APP_NAME\e[0m -> Service: \e[1m$service_key\e[0m" >&2    
    fi
   

    export CLIENT_APP_CONTAINER_NAME="$service_key"
    return 0
}

#···· PG ZONE
# --- Helper de Credenciais do Provisionador (Fallbacks) ---
_db_provider_credentials() {
    echo "🔑 Buscando credenciais master do Postgres (authentik)..." >&2
    export POSTGRES_USER='authentik'
    
    # Mapeia o segredo do Authentik para a variável global do provisionador
    app_export_map_secret_vars \
        "POSTGRES_PASSWORD=authentik/AUTHENTIK_POSTGRESQL__PASSWORD" || return 1
}

# --- Lógica de Execução SQL ---
pg_exec() {
    local sql="$1"
    local user="${2:-$POSTGRES_USER}"
    local pass="${3:-$POSTGRES_PASSWORD}"
    local db="${4:-postgres}"
    local pg_container="$AUTHENTIK_DB_CONTAINER"
    require_vars sql user pass db pg_container || return 1    
    docker exec -i -e PGPASSWORD="$pass" "$pg_container" \
        psql -U "$user" -d "$db" -tAc "$sql"
}

_db_role_names() {
    local _role="${1:-admin}"
    _role=$(sanitize_db_name "${_role}")
    if [[ ! "$_role" =~ ^(admin|rw|ro)$ ]]; then
        echo "❌ Erro: '$_role' é inválido. Valores permitidos: admin, rw, ro." >&2
        return 1
    fi
    require_vars CLIENT_APP_NAME || return 1
    
    local app_name="$CLIENT_APP_NAME"    
    # let .env APP_DB_NAME set the app db
    local db_name=$(sanitize_db_name "${CLIENT_APP_DB_NAME:-app_name}")
    
    export CLIENT_APP_DB_NAME="$db_name"
    export CLIENT_APP_DB_ROLE_NAME="db_${db_name}__role_${_role}"
    export CLIENT_APP_DB_ROLE_PASS="DB_ROLE_${_role^^}_PASS"
    return 0
}

app_create_map_secret_vars() {
    local mappings=("$@")
    require_vars CLIENT_APP_NAME || return 1
    
    echo "🗺️  Mapping (${#mappings[@]}) secrets for $CLIENT_APP_NAME..." >&2

    for mapping in "${mappings[@]}"; do
        # Divide "TARGET_VAR=SOURCE_PATH"
        local target_var="${mapping%%=*}"
        local source_path="${mapping#*=}"
        (
            # 1. Tenta obter o segredo (o core_secret_service_get exporta o basename do path)
            if core_secret_service_get "$source_path"; then
                
                # 2. Extração dinâmica do valor
                # Se o path for "folder/sub/PASSWORD", o core_secret_service_get exporta PASSWORD
                local source_var_name="${source_path##*/}"
                local secret_value="${!source_var_name}"
                
                if [[ -z "$secret_value" ]]; then
                    echo "   ⚠️  Warning: $source_var_name is empty (Path: $source_path)" >&2
                    continue
                fi

                # 3. Persistência no contexto da App
                # Salva o segredo no caminho relativo à aplicação e exporta a variável $target_var
                core_secret_service_put "$CLIENT_APP_NAME/$target_var" "$secret_value" || return 1
                        
                echo "   ✅ Mapped: $target_var" >&2
            else
                echo "   ❌ Failed to map: $target_var (Path: $source_path not found)" >&2
                return 1
            fi
        )
    done
}

# --- Lógica de Provisionamento (Chamada apenas quando necessário) ---
app_db_schema() {
    local role="${1:-admin}"
    role=$(sanitize_db_name "${_role}")
    # 1. Carregar credenciais e validar existência da DB primeiro
    app_db_exist "$role" || { echo "❌ DB não existe. Impossível verificar esquema."; return 1; }

    local db_name="$CLIENT_APP_DB_NAME"
    local db_role="$CLIENT_APP_DB_ROLE_NAME"
    local db_pass_var="$CLIENT_APP_DB_ROLE_PASS"
    local db_pass_value="${!db_pass_var}"

    echo "📊 Inspecionando esquema da DB '$db_name' via '$db_role'..." >&2

    # 2. Query para contar tabelas criadas pelo utilizador (excluindo sistema)
    local sql_count="SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE';"
    
    local table_count=$(pg_exec "$sql_count" "$db_role" "$db_pass_value" "$db_name")

    # Garante que table_count é um número
    if [[ ! "$table_count" =~ ^[0-9]+$ ]]; then
        echo "❌ Erro ao ler contagem de tabelas."
        return 1
    fi

    if [ "$table_count" -eq 0 ]; then
        echo "⚪ DB '$db_name' está VAZIA (0 tabelas)."
        return 2 # Status específico para "DB existe mas está vazia"
    else
        echo "🟢 DB '$db_name' contém $table_count tabelas."
        return 0
    fi
}
app_db_exist() {
    local role="${1:-admin}"
    
    # 1. Tenta carregar credenciais da role especificada
    _db_role_get_credentials "$role" || { echo "⚠️ Não foi possível carregar credenciais para $role"; return 1; }

    local db_name="$CLIENT_APP_DB_NAME"
    local db_role="$CLIENT_APP_DB_ROLE_NAME"
    local db_pass_var="$CLIENT_APP_DB_ROLE_PASS"
    local db_pass_value="${!db_pass_var}"

    echo "🔍 Verificando existência da DB '$db_name' como '$db_role'..." >&2

    # 2. Tentativa 1: Acesso direto com a role do App
    # Se isto funcionar, a DB existe e as permissões estão OK.
    if pg_exec "SELECT 1" "$db_role" "$db_pass_value" "$db_name" >/dev/null 2>&1; then
        return 0
    fi

    # 3. Tentativa 2: Verificação via Provider (Root)
    # Se a primeira falhou, pode ser que a DB exista mas a role não tenha acesso, 
    # ou a DB ainda não foi criada. Consultamos o catálogo real.
    if _db_provider_credentials; then
        echo "🔍 Role '$db_role' falhou. Consultando catálogo via Root..." >&2
        
        local sql_check="SELECT 1 FROM pg_database WHERE datname = '$db_name'"
        
        if [[ "$(pg_exec "$sql_check" "$POSTGRES_USER" "$POSTGRES_PASSWORD" "postgres")" == "1" ]]; then
            echo "✅ DB '$db_name' existe (confirmado via Root)." >&2
            return 0
        fi
    fi

    echo "❌ DB '$db_name' não encontrada em nenhum role." >&2
    return 1
}
app_db_wait() {    
    local role="admin"
    _db_role_names "$role" || return 1
    
    local db_name="$CLIENT_APP_DB_NAME"
    local db_role="$CLIENT_APP_DB_ROLE_NAME"

    require_vars \
        db_name \
        db_role || return 1

    echo "⏳ Aguardando DB '$db_name' estar pronta para '$db_role'..." >&2


    local retries=10
    local count=0
    
    # Loop de espera (10 tentativas com delay)
    while [ $count -lt $retries ]; do
        if _db_role_test_credentials "$role"; then
            return 0
        fi
        count=$((count + 1))
        echo "🔄 Tentativa $count/$retries: DB ainda não responde..." >&2
        sleep 2
    done

    echo "❌ [FATAL] DB '$db_name' não ficou pronta após $retries tentativas." >&2
    return 1
}
# --- Função Principal ---
_db_role_get_credentials() {
    local db_role="${1}" # admin | rw | ro
    db_role=$(sanitize_db_name "${db_role}")
    if [[ ! "$db_role" =~ ^(admin|rw|ro)$ ]]; then
        echo "❌ Erro: '$db_role' é inválido. Valores permitidos: admin, rw, ro." >&2
        return 1
    fi
    require_vars CLIENT_APP_NAME || return 1
    # 1. Carregar definições da db_role (assume que esta função exporta CLIENT_APP_DB_ROLE_NAME e a senha)
    _db_role_names "$db_role" || return 1
    local role_name="${CLIENT_APP_DB_ROLE_NAME}"
    local role_pass="${CLIENT_APP_DB_ROLE_PASS}"
    
    PROVIDER_SELECT="mem vault keepass" core_secret_service_get "$CLIENT_APP_NAME/$role_pass" || \
    return 1
}

_db_role_set_credentials() {
    local role="${1}" # admin | rw | ro
    local pass="${2}"
    # 1. Validações Iniciais
    require_vars \
        CLIENT_APP_NAME \
        role pass || return 1
    
    # 2. Carregar nomes (Exporta CLIENT_APP_DB_ROLE_NAME e CLIENT_APP_DB_ROLE_PASS)
    # Ex: role_name="app_admin", role_pass="DB_ADMIN_PASS"
    _db_role_names "$role" || return 1
    local role_name="${CLIENT_APP_DB_ROLE_NAME}"
    local role_pass_var_name="${CLIENT_APP_DB_ROLE_PASS}"

    # 3. Persistir no Secret Provider (Vault/KeePass)
    # Esta função deve exportar a variável cujo nome está em $role_pass_var_name
    (
        core_secret_service_put "$CLIENT_APP_NAME/$role_pass_var_name" "$pass" || return 1
        
        # Pegamos o valor real da password usando indireção
        local role_pass_value="${!role_pass_var_name}"

        # Debug (Opcional, cuidado em produção com senhas no log)
        # show_vars role_name role_pass_var_name POSTGRES_USER
        
        echo "🔑 Provisionando Role '$role_name' no Postgres..." >&2

        # 4. Execução SQL Idempotente
        # Usamos o POSTGRES_USER para garantir privilégios de criação
        pg_exec "DO \$$ 
        BEGIN 
            IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$role_name') THEN 
                CREATE ROLE $role_name WITH LOGIN PASSWORD '$role_pass_value'; 
            ELSE
                -- Se já existir, garantimos que a password está atualizada (Rotation)
                ALTER ROLE $role_name WITH LOGIN PASSWORD '$role_pass_value';
            END IF; 
        END \$$;" \
        "$POSTGRES_USER" \
        "$POSTGRES_PASSWORD" \
        "postgres"
    )    
}
_db_role_test_credentials() {        
    local role="${1}" # admin | rw | ro
    role=$(sanitize_db_name "${role}")
    if [[ ! "$role" =~ ^(admin|rw|ro)$ ]]; then
        echo "❌ Erro: '$role' é inválido. Valores permitidos: admin, rw, ro." >&2
        return 1
    fi
    require_vars role || return 1
    # 1. Carregar definições da role (assume que esta função exporta CLIENT_APP_DB_ROLE_NAME e a senha)
    _db_role_get_credentials "$role" || return 1
    
    echo "🧪 Testando permissões para a role: $CLIENT_APP_DB_ROLE_NAME ($role)..." >&2

    # 2. Definir o statement baseado na role
    local test_sql
    case "$role" in
        admin)
            # Admin deve conseguir ver tabelas de sistema e configurações de runtime
            test_sql="SELECT count(*) FROM pg_settings WHERE name LIKE 'max_%';"
            ;;
        rw|ro)
            # RW e RO devem conseguir ler o esquema público e listar tabelas
            # Este comando prova que o USER tem permissão de CONNECT + USAGE no SCHEMA
            test_sql="SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';"
            ;;
        *)
            echo "❌ Role desconhecida: $role"
            return 1
            ;;
    esac

    # 3. Execução via pg_exec
    _db_role_get_credentials "$role" || return 1
    local pass_value="${!CLIENT_APP_DB_ROLE_PASS}"
    # Se o comando retornar status 0, a role está funcional.
    if pg_exec "$test_sql" "$CLIENT_APP_DB_ROLE_NAME" "$pass_value" "$CLIENT_APP_DB_NAME"; then
        echo "✅ Role '$CLIENT_APP_DB_ROLE_NAME' validada com sucesso."
        return 0
    else
        echo "❌ FALHA: Role '$role' não tem acesso à base de dados '$CLIENT_APP_DB_NAME'."
        return 1
    fi
}
## very dangerous
app_db_nuke() {
    require_vars POSTGRES_PASSWORD POSTGRES_USER || {
        _db_provider_credentials || return 1
    }   
    require_vars CLIENT_APP_DB_NAME || return 1
    local role="admin" # admin | rw | ro
    require_vars role || return 1
    # 1. Carregar definições da role (assume que esta função exporta CLIENT_APP_DB_ROLE_NAME e a senha)
    _db_role_get_credentials "$role" || return 1
    local db_name="$CLIENT_APP_DB_NAME"
    
    require_vars db_name role
    
    echo "⚠️  RESET TOTAL SOLICITADO: Removendo DB '$db_name' e seus utilizadores..." >&2    
    app_db_schema
    ask_nuke "$db_name" || return 1
    # 1. Matar conexões ativas na base de dados
    # Sem isto, o comando DROP DATABASE falhará
    pg_exec "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$db_name' AND pid <> pg_backend_pid();" \
            "$POSTGRES_USER" "$POSTGRES_PASSWORD" "postgres"

    # 2. Dropar a Base de Dados
    echo "🔥 Eliminando base de dados..." >&2
    pg_exec "DROP DATABASE IF EXISTS $db_name;" "$POSTGRES_USER" "$POSTGRES_PASSWORD" "postgres"

    # 3. Dropar as Roles (Admin, RW, RO)
    echo "🧹 Limpando utilizadores (roles) para $db_name..." >&2
    
    for role in "admin" "rw" "ro"; do
        # 1. Obter o nome da role através da tua função helper
        _db_role_names "$role" || continue
        local role_name="$CLIENT_APP_DB_ROLE_NAME"
        
        echo "   -> Removendo role: $role_name" >&2
        
        # 2. DROP OWNED e DROP ROLE
        # O 'DROP OWNED' limpa objetos criados pelo utilizador dentro das DBs
        # O 'DROP ROLE' remove o utilizador propriamente dito
        pg_exec "
            DO \$$ 
            BEGIN 
                IF EXISTS (SELECT FROM pg_roles WHERE rolname = '$role_name') THEN
                    EXECUTE 'DROP OWNED BY $role_name CASCADE';
                    EXECUTE 'DROP ROLE $role_name';
                END IF;
            END \$$;" \
            "$POSTGRES_USER" "$POSTGRES_PASSWORD" "postgres"
    done

    # 4. Re-correr o provisionamento inicial
    # app_db_provision_logic || return 1
    echo "✅ Reset concluído. Agora a reconstruir..." >&2
    
    
}

app_db_provision_logic() {
    # 1. Verifica se já existe acesso (Idempotência) one db 3 roles admin,rw,ro
    _db_role_names
    echo "Aprovisionamento de DB $CLIENT_APP_DB_NAME"
    echo "  owned by: ($CLIENT_APP_DB_ROLE_NAME)"
    echo "  container: ($AUTHENTIK_DB_CONTAINER) "

    ask_provision "db:$CLIENT_APP_DB_NAME" && \
    # 2. Garante credenciais do Provisionador (Root)
    require_vars POSTGRES_PASSWORD POSTGRES_USER || {
        _db_provider_credentials || return 1
    }    

    # 3. Provisionamento de Roles (Loop Unificado)
    for role in "admin" "rw" "ro"; do
        _db_role_names "$role"
        
        # Guardamos o nome da role para as ACLs finais
        declare "db_role_${role}=$CLIENT_APP_DB_ROLE_NAME"
        
        # Se o teste falhar, criamos/atualizamos a role
        if ! _db_role_test_credentials "$role" >/dev/null 2>&1; then
            if _db_role_get_credentials "$role"; then
                local pass_var_name="$CLIENT_APP_DB_ROLE_PASS"
                local pass_value="${!pass_var_name}"
                _db_role_set_credentials "$role" "$pass_value"
            else
                echo "❌ Erro: Não foi possível obter segredo para a role $role" >&2
                return 1
            fi
        fi
    done

    # 4. Criação da Database (Owner = Admin)
    _db_role_names "admin"
    local db_admin_name="$CLIENT_APP_DB_ROLE_NAME"
    # Dentro do Passo 5, após o loop de extensões:
    pg_exec "GRANT ALL ON SCHEMA public TO $CLIENT_APP_DB_ROLE_NAME; 
            GRANT ALL ON SCHEMA vectors TO $CLIENT_APP_DB_ROLE_NAME; 
            ALTER SCHEMA vectors OWNER TO $CLIENT_APP_DB_ROLE_NAME;" \
        "$POSTGRES_USER" "$POSTGRES_PASSWORD" "$CLIENT_APP_DB_NAME"
    
    if [[ "$(pg_exec "SELECT 1 FROM pg_database WHERE datname='$CLIENT_APP_DB_NAME'")" != "1" ]]; then
        echo "🏗️ Criando database '$CLIENT_APP_DB_NAME'..." >&2
        pg_exec "CREATE DATABASE $CLIENT_APP_DB_NAME OWNER $db_admin_name;" \
            "$POSTGRES_USER" "$POSTGRES_PASSWORD" "postgres"
    fi

    # --- NOVO PASSO 5: Extensões (Root context) ---
    echo "📦 Provisionando Extensões de Sistema para $CLIENT_APP_NAME..." >&2

    # Ordem é importante: cube deve vir antes de earthdistance
    local extensions=("vectors" "pg_trgm" "uuid-ossp" "cube" "earthdistance")

    for ext in "${extensions[@]}"; do
        # Instalamos como Root na DB do cliente
        if pg_exec "CREATE EXTENSION IF NOT EXISTS \"$ext\" CASCADE;" \
            "$POSTGRES_USER" "$POSTGRES_PASSWORD" "$CLIENT_APP_DB_NAME"; then
            echo "   ✅ Extension installed: $ext" >&2
        else
            echo "   ❌ Failed to install extension: $ext" >&2
            return 1
        fi
    done

    # --- NOVO PASSO 6: ACLs Granulares (Agora que os schemas existem) ---
    echo "🔐 Aplicando privilégios granulares em '$CLIENT_APP_DB_NAME'..." >&2
    
    local sql_acls="
        REVOKE ALL ON SCHEMA public FROM PUBLIC;
        
        -- Public Schema
        GRANT USAGE ON SCHEMA public TO $db_role_admin, $db_role_rw, $db_role_ro;
        GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $db_role_admin;
        GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $db_role_admin;
        
        -- Vectors Schema (Garante acesso ao tipo 'vector' e funções de busca)
        DO \$$ 
        BEGIN 
            IF EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'vectors') THEN
                -- Usage permite "entrar" no esquema
                GRANT USAGE ON SCHEMA vectors TO $db_role_admin, $db_role_rw, $db_role_ro;
                
                -- EXECUTE apenas para funções (SELECT aqui causa erro)
                GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA vectors TO $db_role_admin, $db_role_rw, $db_role_ro;
                
                -- SELECT apenas para tabelas (necessário para metadados da extensão)
                GRANT SELECT ON ALL TABLES IN SCHEMA vectors TO $db_role_admin, $db_role_rw, $db_role_ro;
            END IF;
        END \$$;

        -- Manutenção de permissões para novas tabelas
        ALTER DEFAULT PRIVILEGES FOR ROLE $db_role_admin IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO $db_role_rw;
        ALTER DEFAULT PRIVILEGES FOR ROLE $db_role_admin IN SCHEMA public GRANT SELECT ON TABLES TO $db_role_ro;
    "
    pg_exec "$sql_acls" "$POSTGRES_USER" "$POSTGRES_PASSWORD" "$CLIENT_APP_DB_NAME"

    # 6. Validação Final
    echo "🔎 Validando provisionamento final..." >&2
    for role in "admin" "rw" "ro"; do
        _db_role_test_credentials "$role" || continue
    done

    echo "✨ Provisionamento de '$CLIENT_APP_DB_NAME' concluído com sucesso!"
}


app_blue_label_fallback() {
    local name=$1
    require_vars name || return 1
    # 1. Substitui underscores (_) e hífens (-) por espaços
    # 2. Converte a primeira letra de cada palavra para maiúscula
    echo "$1" | sed -E 's/[_-]+/ /g' | sed -E 's/\b([a-z])/\U\1/g'
}
# this case (the devepoing example case), define the service key in compose (backrest)
# Finds the service key where container_name == $CLIENT_APP_NAME
_get_compose_file_json() {
    require_files CLIENT_APP_COMPOSE_FILE || return 1
    yq eval -o=json "." "$CLIENT_APP_COMPOSE_FILE" 2>/dev/null | jq -c '
        .services |= (to_entries | map(.value + {service_name: .key}))
    '
}
_get_compose_json_entry() {

    local cn=${CLIENT_APP_CONTAINER_NAME}    
    _get_compose_file_json | jq -c --arg cn "$cn" '
        .services[] | 
        select(.container_name == $cn)
    '
}
_get_compose__env_var() {
    local var_name=${1}
    require_vars CLIENT_APP_CONTAINER_NAME CLIENT_APP_COMPOSE_FILE var_name || return 1

    # Extraímos a secção environment bruta
    local env_data=$(yq ".services.${CLIENT_APP_CONTAINER_NAME}.environment" "$CLIENT_APP_COMPOSE_FILE")
    
    local var_value=""

    # Lógica manual para extrair o valor (suporta os dois formatos de YAML)
    if [[ "$env_data" == *"- $var_name="* ]]; then
        # Formato LISTA: - PORT=19999
        var_value=$(echo "$env_data" | grep "^- $var_name=" | cut -d'=' -f2-)
    else
        # Formato DICIONÁRIO: PORT: 19999
        var_value=$(yq ".services.${CLIENT_APP_CONTAINER_NAME}.environment.${var_name}" "$CLIENT_APP_COMPOSE_FILE")
    fi

    # Validação
    if [[ "$var_value" == "null" || -z "$var_value" ]]; then
        echo "⚠️  Var $var_name not found on file $(require_files CLIENT_APP_COMPOSE_FILE)" >&2
        return 1
    fi

    # Exportação Dinâmica
    echo "$var_value"    
    return 0
}

app_require_export_container_ip_port() {
    require_vars CLIENT_APP_CONTAINER_NAME
    
    # 1. Tentar obter o IP
    local _ip
    _ip=$(docker_container_name_ip "$CLIENT_APP_CONTAINER_NAME") 

    if [[ -z "$_ip" ]]; then     
        # Se estiver vazio, deu erro
        unset CLIENT_APP_SERVICE_IP
        debug_required_type_name "$CLIENT_APP_NAME-ip" "CLIENT_APP_CONTAINER_NAME" "$REQ_STATUS_MISS"
        return 1 
    else        
        # Se encontrou, exporta
        export CLIENT_APP_SERVICE_IP="$_ip" 
    fi   

    # 2. Tentar obter a Porta (apenas se ainda não estiver definida)
    local _port
    _port=$(docker_container_name_ports "$CLIENT_APP_CONTAINER_NAME") 
    
    if [[ -n "$_port" ]]; then 
        export CLIENT_APP_SERVICE_PORT="$_port" 
    else
        debug_required_type_name "$CLIENT_APP_NAME-port" "CLIENT_APP_CONTAINER_NAME" "$REQ_STATUS_MISS"
        return 1
    fi                        

    echo "$CLIENT_APP_SERVICE_IP:$CLIENT_APP_SERVICE_PORT"
    return 0
}

app_required_env_vars() {
    require_functions app_blue_label_fallback _get_compose__env_var tool_prepare__env_vars
    require_vars CLIENT_APP_NAME || return 1
    require_vars CLIENT_APP_CONTAINER_NAME || tool_prepare__env_vars || return 1
       
    # 4. Extrair APP_BLUE_GROUP - template blue tpl defining UI app link label 
    if [[ -z "$CLIENT_APP_BLUE_GROUP" ]]; then 
        local _var_APP_GROUP=$(_get_compose__env_var "APP_BLUE_GROUP")
        if [[ -z "$CLIENT_APP_BLUE_GROUP" ]]; then 
            require_vars CLIENT_APP_BLUE_GROUP
            return 1
        fi
        export CLIENT_APP_BLUE_GROUP="${_var_APP_GROUP}"     
    fi

    # 5. Extrair APP_BLUE_LABEL - template blue tpl defining UI app link label 
    if [[ -z "$CLIENT_APP_BLUE_LABEL" ]]; then 
        local _var_APP_LABEL=$(_get_compose__env_var "APP_BLUE_LABEL")
        if [[ -z "$CLIENT_APP_BLUE_LABEL" ]]; then 
            require_vars CLIENT_APP_BLUE_LABEL
            return 1
        fi
        export CLIENT_APP_BLUE_LABEL="${_var_APP_LABEL}"     
    fi

    export CLIENT_APP_NS="$CLIENT_APP_NAME.$DOMAIN"
        
    _resolve_compose__container_name || return 1 ## must exist container name
           
    
    export CLIENT_APP_INTERNAL_NS="$CLIENT_APP_CONTAINER_NAME.$INTERNAL_DOMAIN"
    echo "🔍 Internal Service: $CLIENT_APP_CONTAINER_NAME" >&2    
    # ok it seams echo "${TOOL_STAGES[@]}"
    # Export final para o motor de template

    _set_blueprint_template_module() {
        require_locations DEVOPS_DIR
        local template_name=${CLIENT_APP_BLUE_TEMPLATE_MODULE:-proxy} # did have two type templates "proxy" "oidc" defined by
        require_vars template_name || return 1
        local _apply_="apply-$template_name"        ## must have apply blue file
        local _cleanup_="cleanup-$template_name"    ## must hav  cleanup blue file

        local _source="$DEVOPS_DIR/authentik/app/blueprints"
        local _target="$DEVOPS_DIR/authentik/blueprints"    
        require_locations _target _source || return 1
        export CLIENT_APP_BLUE_APPLY="$_target/home2500_$CLIENT_APP_NAME--${_apply_}.yaml"
        export CLIENT_APP_BLUE_CLEANUP="$_target/home2500_$CLIENT_APP_NAME--${_cleanup_}.yaml"
        
        export CLIENT_APP_BLUE_APPLY_TPL="$_source/CLIENT_APP_NAME--${_apply_}.yaml"
        export CLIENT_APP_BLUE_CLEANUP_TPL="$_source/CLIENT_APP_NAME--${_cleanup_}.yaml"
        ### developer responsability to templace _apply_ && _cleanup_ blueprint templates
        if require_files CLIENT_APP_BLUE_APPLY_TPL CLIENT_APP_BLUE_CLEANUP_TPL; then
            export CLIENT_APP_BLUE_TEMPLATE_MODULE="$template_name"
        else
            return 1
        fi    
        
    }
    _set_blueprint_template_module

    if [[ $CLIENT_APP_BLUE_TEMPLATE_MODULE == "proxy" ]];then
        TOOL_STAGES=(
            "script" 
            "provision_db" 
            "provision_secrets" 
            "vault_login"            
            "compose" 
            "running" 
            "name_register" 
            "authentik_login" 
            "blue_apply" 
            "outpost_add"
        )
    else        
        TOOL_STAGES=(
            "script" 
            "provision_db" 
            "provision_secrets" 
            "vault_login" 
            "compose" 
            "running" 
            "name_register" 
            "authentik_login" 
            "blue_apply" 

        )
    fi
    export TOOL_STAGES_OFF=(
        "outpost_remove"
        "blue_clean" 
        "authentik_logout" 
        "stop" 
        "vault_logout"                 
        "names_unregister"                     
    )

    require_vars \
        TOOL_STAGES \
        CLIENT_APP_BLUE_LABEL \
        CLIENT_APP_BLUE_GROUP \
        CLIENT_APP_CONTAINER_NAME \
        CLIENT_APP_NS \
        CLIENT_APP_INTERNAL_NS || return 1    
}

app_names_sync() {
    # Garante a biblioteca do Pi-hole
    declare -f ph_api >/dev/null || source $(core_resolve_file "pihole/_0.pihole_lib.sh") > /dev/null 2>&1
    echo "🌐 Configurando DNS no Pi-hole..." >&2
    
    # ph_api auth agora tem os 5 retries internos
    ph api open || return 1    
    if ph api auth; then
        ph api dns sync
        echo "✅ DNS atualizado." >&2
    else
        echo "❌ Falha crítica de DNS: Pi-hole API inacessível." >&2
        return 1
    fi
 
}
app_up_names() {
    require_vars CLIENT_APP_NAME || return 1
    require_vars CLIENT_APP_INTERNAL_NS || {      
        echo "check:"        
        echo "  app_compose_required_vars" 
        return 1
    }
    app_require_export_container_ip_port >/dev/null #>&2  
    
    if [[ -z "$CLIENT_APP_SERVICE_IP" ]]; then
        echo "⚠️  Optional CLIENT_APP_SERVICE_IP missing, ${FUNCNAME[0]} attempting to continue..." >&2
    fi    
    
    local APP_NS_IP="$CLIENT_APP_SERVICE_IP"   
    show_vars APP_NS_IP

    local service="pihole"
    if require_container_running service; then
       # Garante a biblioteca do Pi-hole
        declare -f ph_api dns add >/dev/null || source $(core_resolve_file "pihole/_0.pihole_lib.sh") > /dev/null 2>&1

        # Verifica se realmente precisamos de mexer no DNS
        # 5. Lógica de Sincronização de DNS
        # Só executa se um dos nomes não resolver para o IP correto
        if ! TARGET_IP="$CLIENT_APP_SERVICE_IP" require_ns_resolve CLIENT_APP_INTERNAL_NS || \
            ! TARGET_IP="$APP_NS_IP" require_ns_resolve CLIENT_APP_NS $APP_NS_IP; then
            echo "🌐 Configurando DNS no Pi-hole para $CLIENT_APP_NAME..." >&2    
            # Rotaciona senha e autentica (com seus retries internos)
            ph api open || return 1
            if ph api auth; then
                # Registra o Domínio Público no IP do Traefik (Proxy)
                ph_api dns add "$APP_NS_IP" "$CLIENT_APP_NS"
           
                # Registra o Domínio Interno no IP direto do Container
                ph_api dns add "$CLIENT_APP_SERVICE_IP" "$CLIENT_APP_INTERNAL_NS"
                
                echo "✅ DNS Records updated successfully." >&2
            else
                echo "❌ Critical DNS Failure: Pi-hole API unreachable after auth attempts." >&2
                return 1
            fi
        else
            echo "✅ DNS is already up to date. Skipping Pi-hole API calls." >&2
            #app_names_sync
        fi
    else
        echo "❌ Critical DNS Failure: Pi-hole container is not running." >&2
    fi
}



app_up_traefik_tls_proxy() {
    # 1. Carregar lib se necessário
    declare -f tk_need_renewal >/dev/null || source $(core_resolve_file "traefik/_0.traefik_lib.sh") > /dev/null 2>&1
    (
                
        # 2. Verificar necessidade de renovação
        if tk_need_renewal; then
            echo "🔐 [INFO] Iniciando renovação de certificados Traefik..." >&2            
            if tk_renew_certs; then
                # Em vez de restart, vamos forçar o Traefik a ler a nova config.
                # Se usas ficheiros dinâmicos, o Traefik deteta-os sozinho via Watcher.
                # Se precisares mesmo de sinalizar, o 'reload' é mais seguro:
                
                echo "🔄 Atualizando configuração do Traefik..." >&2
                docker compose exec -T traefik kill -s SIGHUP 1 2>/dev/null || docker compose restart
         
                tk_wait4_service_ready "$CLIENT_APP_NAME"
                echo "✅ Certificados aplicados com sucesso." >&2
            else
                echo "❌ [ERRO] Falha na renovação dos certificados!" >&2

                return 1
            fi
        else
            echo "✔ [INFO] Certificados Traefik ainda são válidos." >&2
        fi
    )
}
# Resultado será: "Whoami Service Identity"


app_blue_generate() {
    local source_tpl_file=${1}
    require_files source_tpl_file || return 1
    local target_yaml=${2}
    echo "📝 Gerando Blueprint a partir de template $(basename $source_tpl_file)..." >&2

    require_files source_tpl_file || return 1
    require_vars target_yaml || return 1
    require_functions \
            blue_template_vars || return 1
    (
        cd $DEVOPS_DIR
        # 3. Gerar Blueprint se necessário                                           
        blue_template_vars "$source_tpl_file" "$target_yaml"
        require_files target_yaml || {
            echo "cound not create missing blueprint file: $target_yaml"
            return 1
        }
        # FIX DE PERMISSÕES: Essencial para o Authentik ler o ficheiro
        chmod 644 "$target_yaml"
    )
}
app_blue_apply() {
    local target_yaml=${2:-$CLIENT_APP_BLUE_APPLY}
    require_files CLIENT_APP_BLUE_APPLY_TPL || {
        echo "missing blueprint template file: $CLIENT_APP_BLUE_APPLY_TPL"
        return 1
    }

    # 4 now generate always. must a a way to check version evolution
    blue_template_vars \
        $CLIENT_APP_BLUE_APPLY_TPL \
        $CLIENT_APP_BLUE_APPLY || return 1
        
    blue_apply "$CLIENT_APP_BLUE_APPLY" || return 1
}
app_blue_cleanup() {
    local target_yaml=${CLIENT_APP_BLUE_CLEANUP}
    require_files CLIENT_APP_BLUE_CLEANUP_TPL || {
        echo "missing blueprint template file: $CLIENT_APP_BLUE_CLEANUP_TPL"
        return 1
    }

    blue_template_vars \
        $CLIENT_APP_BLUE_CLEANUP_TPL \
        $target_yaml || return 1

    blue_apply "$target_yaml" "false" || return 1
}
app_wait4_oidc() {
    local target_service="${1}" ##:-$CLIENT_APP_NAME}"
    require_vars target_service || return 1    
    local max_attempts=${2:-10}  
    local attempt=1    
    local interval="${3:-2}"
    local dots=""

    # Mensagem enviada para stderr (não interfere no $(...) )
    echo "🔍 Validando Proteção SSO para $target_service (max $max_attempts tentativas)..." >&2
    
    while [ $attempt -le $max_attempts ]; do
        # require_service_redirect_auth deve retornar 0 (sucesso) ou 1 (falha)
        if require_service_redirect_auth "$target_service" > /dev/null 2>&1; then
            echo "  ✅ Proteção detetada na tentativa $attempt." >&2
            
            # Única coisa que sai no stdout (opcional, ou apenas return 0)
            echo "protected" 
            return 0
        fi
        
        dots="${dots}."
        # \r volta ao início, \033[K limpa a linha atual
        printf "\r⏳ [%d/%d] Aguardando propagação%s" "$attempt" "$max_attempts" "$dots" >&2
        sleep $interval
        ((attempt++))
    done
    
    # Lógica de erro enviada para stderr
    echo "❌ Erro: O serviço $target_service continua EXPOSTO." >&2
    #echo "🔍 Diagnóstico extra (whoami):" >&2
    #require_service_redirect_auth "whoami" >&2
    
    echo "exposed"
    return 1
}

app_wait4_docker_ip() {
    # Definir o limite de tentativas
    local max_attempts=5
    local count=0

    echo "⏳ Aguardando que o container '$CLIENT_APP_NAME' obtenha um IP..." >&2

    while [[ $count -lt $max_attempts ]]; do
        # Tenta obter e exportar o IP/Porto
        # Nota: Esta função deve internamente chamar docker_container_name_ip
        if app_require_export_container_ip_port > /dev/null; then            
            if [[ -n "$CLIENT_APP_SERVICE_IP" && "$CLIENT_APP_SERVICE_IP" != "invalid IP" ]]; then
                local url="http://$CLIENT_APP_SERVICE_IP:$CLIENT_APP_SERVICE_PORT"
                if require_http_status_ok url; then
                    echo "✅ Container IP detetado: $CLIENT_APP_SERVICE_IP:$CLIENT_APP_SERVICE_PORT" >&2
                fi
                break
            fi
        fi

        count=$((count + 1))
        
        if [[ $count -eq $max_attempts ]]; then
            echo "❌ Erro: Timeout ao aguardar IP do container após $max_attempts tentativas." >&2
            return 1
        fi

        echo "   [Attempt $count/$max_attempts] Aguardando 2s..." >&2
        sleep 2
    done
}

app_script_requirements() {
    require_vars CLIENT_APP_SCRIPT_NAME || return 1
    local client_script="$CLIENT_APP_DIR/$CLIENT_APP_SCRIPT_NAME"       
    
    ### 1. Definição das funções base
    local base_funcs=("deploy" "deploy_secrets")

    ### 2. Gerar handlers de falha dinamicamente
    local fail_stage_funcs=()
    for stage in "${TOOL_STAGES[@]}"; do        
        fail_stage_funcs+=("on_${stage}_fail")        
    done

    #### 3. Unir arrays corretamente (Fix da sintaxe Bash)
    local expected_funcs=("${base_funcs[@]}" "${fail_stage_funcs[@]}")

    if require_files client_script; then
        echo -e "\n🔍 Client script handler functions in: [$(core_relative_path2 "$client_script")]" >&2
        
        # Criar pattern para visualização ou filtragem
        local pattern
        pattern=$(printf "|%s" "${expected_funcs[@]}")
        pattern="${pattern:1}" # Remove o primeiro pipe extra

        # Validar cada função individualmente
        local missing_count=0
        for func_name in "${expected_funcs[@]}"; do
            # require_single_script_function deve retornar 0 se existir, >0 se não
            if ! require_single_script_function "client_script" "$func_name"; then
                ((missing_count++))
            fi
        done

        # Verificação crítica específica
        if ! require_single_script_function "client_script" "deploy" 2>/dev/null; then    
            echo -e "\e[31m❌ Missing critical 'deploy' function in $client_script\e[0m" >&2
            return 1
        fi

        [[ $missing_count -gt 0 ]] && echo -e "⚠️  Missing $missing_count optional handlers." >&2
        echo "" >&2
    else
        echo "❌ Can't find tool client script: $client_script"
        echo "💡 Create ./init.sh to handle stages: ${TOOL_STAGES[*]}"
        return 1
    fi
}
app_login() {            
    if vault_request_stew_token; then    
        ak_api_token_validate || \
        ak_api_token_generate || return 1
        return 0
    fi
    return 1           
}
tool_stage_workflow() {
    local stages=("${@}")
    [[ ${#stages[@]} -eq 0 ]] && stages=("${TOOL_STAGES[@]}")
    
    __fail_stage__handler() {     
        local stage="$1"  
        local client_handler_func="on_${stage}_fail"
        local service__func="_${stage}__requirements"
        local client_script="$CLIENT_APP_DIR/$CLIENT_APP_SCRIPT_NAME"         
        require_files client_script || return 1
        echo "
        ---------------------------------------
        ❌ stage \"$stage\" $REQ_STATUS_MISS"
        local tool_="${BASH_SOURCE[0]}"
        # show link to handler
        if ! LABEL="          handler:" require_single_script_function tool_ "$service__func" ; then            
            return 1
        fi
        
        #show_vars stage client_handler_func
        ## make on_${stage}_fail a mandatory method
        ## ok it seams show_vars client_script client_handler_func client_script
        ## no &2 noise
        if ! LABEL="          response review:" require_single_script_function client_script "$client_handler_func"; then    
            return 1        
        fi

        "$client_handler_func"
    }
    
    # 1. Requisitos Base (Impedem qualquer execução se falharem)
    _base__requirements() {        
        tool_prepare__env_vars  || return 1
        app_required_env_vars || return 1
        require_vars CLIENT_APP_CONTAINER_NAME || return 1
    }
    _base__requirements 2> /dev/null || return 1 # essencial desired names 

    _script__requirements() {        
        app_script_requirements || return 1
    }

    _provision_db__requirements() {
        # 1. Lógica de Base de Dados .env file APP_DB_NAME trigger db creation
        if [[ -n "$CLIENT_APP_DB_NAME" ]]; then
            # Se a DB não existir, provisiona. 
            # Se app_db_exist falhar (erro de rede), não avança.     
            (       
                if ! app_db_exist; then                    
                    echo "📦 Client request $CLIENT_APP_DB_NAME DB. Provisioning..." >&2 
                    if ! app_db_provision_logic; then                        
                        return 1                    
                    fi
                fi
            )
        fi
        return 0 
    }

    _provision_secrets__requirements() {        
        local client_script="$CLIENT_APP_DIR/$CLIENT_APP_SCRIPT_NAME"   
        if ! require_single_script_function "client_script" "provision_secrets" 2>/dev/null; then    
            echo -e "\e[31m❌ Missing critical 'provision_secrets' function in $CLIENT_APP_SCRIPT_NAME\e[0m" >&2
            return 1
        else    
            provision_secrets || return 1            
        fi
    }

    _vault_login__requirements() {        
        vault_validate_token || return 1        
    }

    _compose__requirements() {
        echo "📦 Iniciando containers via Compose..."
        
        require_files CLIENT_APP_COMPOSE_FILE || return 1
        
        (
            local compose_config_check
            local secret_file=$(core_secret_mapper_mem "$CLIENT_APP_NAME" ".secret")
            local env_cmd=()

            # 1. Preparar o prefixo 'env' se o segredo existir
            if [[ -f "$secret_file" ]]; then
                echo "🔐 Carregando segredos de: $secret_file"
                # Usamos um array para evitar problemas com espaços
                env_cmd=(env $(grep -v '^#' "$secret_file" | xargs))
            else
                echo "⚠️  Aviso: Ficheiro de segredos não encontrado. Continuando apenas com .env local."
            fi
               
            compose_config_check=$("${env_cmd[@]}" docker compose -f "$CLIENT_APP_COMPOSE_FILE" config 2>&1 >/dev/null)

            if echo "$compose_config_check" | grep -qi "WARN\|error"; then
                echo "❌ [DOCKER COMPOSE] Erro de validação ou variáveis ausentes:" >&2
                echo "$compose_config_check" | grep -i "WARN\|error" >&2
                require_search_file CLIENT_APP_COMPOSE_FILE "$CLIENT_APP_CONTAINER_NAME" "name=container_name" || return 1
                return 1
            fi
        )
    }

    # 2. Camada Interna (Serviço a responder no Docker Network)
    _running__requirements() {
        if ! require_container_running "CLIENT_APP_CONTAINER_NAME"  >/dev/null 2>&1; then
            echo "❌ Container $CLIENT_APP_CONTAINER_NAME is not running." >&2
            return 1
        fi
        app_require_export_container_ip_port  || return 1       
    }

    _name_register__requirements() {
        # Tenta resolver NS ou forçar atualização       
        _running__requirements || return 1
        DEBUG=true require_vars CLIENT_APP_INTERNAL_NS CLIENT_APP_SERVICE_PORT || return 1
        if ! require_ns_resolve "CLIENT_APP_INTERNAL_NS" >/dev/null 2>&1 || \
           ! require_ns_resolve "CLIENT_APP_NS"; then 
           echo "run app_up_names"
           return 1; 
        fi
    
        local container="pihole"
        if ! require_container_running "container"  ; then #>/dev/null 2>&1; then            
            return 1
        fi
        return 0
    }

    _authentik_login__requirements() {
        local container="authentik-server"
        if ! require_container_running "container"  >/dev/null 2>&1; then
            ## missing pihole running not going to resolve names            
            return 1
        fi
        ak_api_token_validate || return 1
        require_http_status_ok client_internal_url
        return 0
    }

    _blue_apply__requirements() {
        _authentik_login__requirements || return 1
        require_files CLIENT_APP_BLUE_APPLY_TPL || return 1
        require_single_blue_file CLIENT_APP_BLUE_APPLY || return 1

        local cur
        cur=$(blue__get_current_json "$CLIENT_APP_BLUE_APPLY")

        # 2. Verificação: Se NÃO tem PK ou NÃO está enabled
        # jq -e retorna 1 (erro) se a condição for falsa
        if ! echo "$cur" | jq -e '.pk and .content != ""' >/dev/null 2>&1; then
            echo "ℹ️  State: Not present or disabled. Proceeding with apply..." >&2            
            return 1
        fi
        echo $cur | jq .
        echo "⚠️  State: Blueprint already active (PK: $(echo "$cur" | jq -r .pk)). Skipping." >&2
        return 0
    }
    _blue_cleanup__requirements() {
        _authentik_login__requirements || return 1
        require_files CLIENT_APP_BLUE_CLEANUP_TPL || return 1
        require_single_blue_file CLIENT_APP_BLUE_CLEANUP || return 1

        local cur
        cur=$(blue__get_current_json "$CLIENT_APP_BLUE_CLEANUP")

        # 2. Verificação: Se NÃO tem PK ou NÃO está enabled
        # jq -e retorna 1 (erro) se a condição for falsa
        if echo "$cur" | jq -e '.pk' >/dev/null 2>&1; then
            echo "ℹ️  State: Is present. Proceeding with clean..." >&2
            return 1
        fi

        echo "⚠️  State: Blueprint does not exist. Skipping." >&2
        return 0
    }

    _outpost_add__requirements() {
        if [[ "$CLIENT_APP_BLUE_TEMPLATE_MODULE" == "oidc" ]]; then
            # oidc app does is not proxied
            return 1   
        fi
        _authentik_login__requirements || return 1

        local count
        # Capturamos o número de providers associados a este slug
        count=$(outpost__get_current_json | \
                jq -r --arg slug "$CLIENT_APP_NAME" '
                    if .providers_obj then 
                        [.providers_obj[] | select(.assigned_application_slug == $slug)] | length 
                    else 0 end
                ')

        # Validação de sanidade: garantir que 'count' é um número
        [[ ! "$count" =~ ^[0-9]+$ ]] && count=0

        if [[ $count -eq 0 ]]; then
            echo "ℹ️  $CLIENT_APP_NAME is NOT part of outpost. Ready to add." >&2
            return 1
        else    
            echo "⚠️  $CLIENT_APP_NAME is ALREADY part of outpost ($count matches)." >&2
            return 0
        fi        
    }
    _outpost_remove__requirements() {
        if [[ "$CLIENT_APP_BLUE_TEMPLATE_MODULE" == "oidc" ]]; then
            # oidc app does is not proxied
            return 1        
        fi
        _authentik_login__requirements || return 1

        local count
        # Capturamos o número de providers associados a este slug
        count=$(outpost__get_current_json | \
                jq -r --arg slug "$CLIENT_APP_NAME" '
                    if .providers_obj then 
                        [.providers_obj[] | select(.assigned_application_slug == $slug)] | length 
                    else 0 end
                ')

        # Validação de sanidade: garantir que 'count' é um número
        [[ ! "$count" =~ ^[0-9]+$ ]] && count=0

        if [[ $count -eq 0 ]]; then
            echo "⚠️  $CLIENT_APP_NAME is not part of outpost. skipping" >&2
            return 0
        else
            echo "ℹ️  $CLIENT_APP_NAME is part of outpost. ready to remove." >&2                
            return 1
        fi        
    }
    # 3. Camada Externa (Serviço a responder via Traefik/HTTPS)
    _expose__requirements() {
        # Para estar exposto, primeiro tem de estar a correr internamente
        stage_running_requirements  >/dev/null 2>&1 || return 1
        
        require_vars CLIENT_APP_NS || return 1

        # Tenta resolver o domínio público (DNS)
        require_ns_resolve "CLIENT_APP_NS" >/dev/null 2>&1 || return 1
        
        if ! require_ns_resolve "CLIENT_APP_NS"; then return 1; fi
        
        local url="https://$CLIENT_APP_NS"
        require_http_status_ok url
    }
    

    __missing_handler_fn__fallback() {        
        echo "
        ------------------------------------------------------------------
        ⚠️ Stage: \"$stage\" handler is missing. " >&2 
        local stage__func="_${stage}__requirements"
        local workflow_func="tool_stage_workflow"     
        local tool_="${BASH_SOURCE[0]}"
        # show file function          
         echo -n "       declare "
        if LABEL="$handler_function() " require_single_script_function tool_ "tool_stage_workflow" ; then            
            return 1
        fi           
        return 1
    }

    # --- Loop de ExecuMissing important clição dos Stages ---
    for stage in "${stages[@]}"; do     
        ##echo "running stage: \"$stage\"" >&2   
        local handler_function="_${stage}__requirements"
        
        # Verifica se a função de stage existe antes de chamar
        if declare -f "$handler_function" > /dev/null; then
            #echo "running handler function $handler_function"

            if status=$(! "$handler_function"); then ## nao existe. nao esta carregada                
                __fail_stage__handler "$stage"    
                ## dev response         
                #DEBUG=true debug_required_type_name "review" "stage" $REQ_STATUS_STOP 4
                echo $status
                return 1
            fi
            echo "  ✅ Stage: \"$stage\" complete" >&2
        else
            __missing_handler_fn__fallback
            return 1  
        fi
    done
}
app_up() {
    # 1. Pré-requisitos e Docker
    echo "📦 Iniciando containers via Compose..."
    (
        tool_stage_workflow \
            "script" \
            "provision_db" "provision_secrets" \
            "vault_login" "compose" || return 1
        # skip this exit even if is running tool_stage_workflow "running" && return 1
        require_vars CLIENT_APP_COMPOSE_FILE CLIENT_APP_NAME  || return 1     
            
        # Execução segura num único comando

        local secret_file=$(core_secret_mapper_mem "$CLIENT_APP_NAME" ".secret")            
        if DEBUG=false require_files secret_file; then
            env $(grep -v '^#' $secret_file | xargs) docker compose -f "$CLIENT_APP_COMPOSE_FILE" up -d 
        else            
            docker compose -f "$CLIENT_APP_COMPOSE_FILE" up -d 
        fi
        
        ### this is a docker expected http proxiable ip:port
        app_wait4_docker_ip || return 1

        if ! tool_stage_workflow "name_register"; then
            app_up_names || return 1
        fi

        if ! tool_stage_workflow "blue_apply"; then             
            app_blue_apply || return 1            
        fi

        if [[ "$CLIENT_APP_BLUE_TEMPLATE_MODULE" == "proxy" ]]; then                
            if ! tool_stage_workflow "outpost_add"; then             
                app_provider_add2_outpost || return 1            
            fi    
            if ! require_service_redirect_auth "$CLIENT_APP_NAME"; then               
                ak_fix_proxied_redir     
            fi        
        fi

        app_up_traefik_tls_proxy
        
        # must have resolvable names  
        local status
        status=$(app_wait4_oidc whoami 4 || return 1)               # wait 8 seconds 
        #
        #show_vars status
        if [[ "$status" == "protected" ]]; then        
            # Garante que o fix corre no contexto certo
            #blue_outpost_sync   
            app_wait4_oidc $CLIENT_APP_NAME 15 && \
            require_service_redirect_auth "$CLIENT_APP_NAME"
        fi  
        
    )
}
app_down() {
    cd "$CLIENT_APP_DIR"
    # Para o container
    docker compose down
}

app_down_names() {
    require_vars CLIENT_APP_NAME INTERNAL_DOMAIN DOMAIN CLIENT_APP_CONTAINER_NAME
    local service="pihole"
    if require_container_running service; then
        # 2. Carregar Lib se necessário
        (
            cd $CLIENT_APP_DIR
            source $(core_resolve_file "pihole/_0.pihole_lib.sh") > /dev/null 2>&1
            ph_api password rotate        
            ph_api auth
            ph_dns_remove "$CLIENT_APP_INTERNAL_NS"
            ph_dns_remove "$CLIENT_APP_NS"
        )    
    else
        return 1
    fi
}

app_provider_add2_outpost() {
    require_vars CLIENT_APP_BLUE_TEMPLATE_MODULE CLIENT_APP_NAME || return 1
    if [[ "$CLIENT_APP_BLUE_TEMPLATE_MODULE" != "proxy" ]]; then
        echo "ℹ️  OIDC/OAuth2 detectado ($CLIENT_APP_BLUE_TEMPLATE_MODULE). Ignorando Outpost." >&2
        return 0
    fi
    require_functions blue_outpost_add_provider || return 1

    (        
        echo "🔗 Associando Provider ao Outpost..." >&2
        blue_outpost_add_provider "$CLIENT_APP_NAME-provider"
        
        # O Outpost Embedded do Authentik às vezes precisa de um "push"
        echo "⏳ Aguardando propagação interna..." >&2
    )
}
app_provider_remove2_outpost() {
    require_vars CLIENT_APP_BLUE_TEMPLATE_MODULE CLIENT_APP_NAME || return 1
    if [[ "$CLIENT_APP_BLUE_TEMPLATE_MODULE" != "proxy" ]]; then
        echo "ℹ️  OIDC/OAuth2 detectado ($CLIENT_APP_BLUE_TEMPLATE_MODULE). Ignorando Outpost." >&2
        return 0
    fi
    require_functions \
            blue_outpost_remove_provider || return 1
    # Se o blueprint não existe, gera a partir do template
    (        
        echo "🔗 Desvinculando Provider do Outpost..." >&2
        blue_outpost_remove_provider "$CLIENT_APP_NAME-provider"
        echo "⏳ Aguardando propagação interna..." >&2
    )
}

app_destroy() {
    app_down    
    
    app_blue_cleanup
    app_provider_remove2_outpost           
}



tool_fn_sort_weights() {
    local rules_json
    rules_json=$(cat <<-'EOF'
[
    {"prefix": "app_db_*",      "weight": 10, "cat": "DATABASE (APP)"},
    {"prefix": "_db_*",         "weight": 11, "cat": "DATABASE "},
    {"prefix": "pg*",          "weight": 11, "cat": "DATABASE "},
    {"prefix": "app_blue*|*set_blueprint*", "weight": 20, "cat": "BLUEPRINTS"},
    {"prefix": "app_up*|app_down*|app_destroy*",       "weight": 30, "cat": "LIFECYCLE"},    
    {"prefix": "app_script*",   "weight": 30, "cat": "REQUIREMENTS"},
    {"prefix": "tool_stage*|*__requirements|__fail_stage*|__missing_handler*",   "weight": 40, "cat": "REQUIREMENTS"},
    {"prefix": "tool_prepare", "weight": 41, "cat": "REQUIREMENTS"},      
    {"prefix": "__*",           "weight": 80, "cat": "PRIVATE"},
    {"prefix": "tool_fn*","weight": 80, "cat": "DEV"},
    {"prefix": "_*",            "weight": 81, "cat": "INTERNAL"},
    {"prefix": ".",            "weight": 90, "cat": "MISC"}
]
EOF
)
    # Mantive o output como ARRAY (removendo o .[] no fim) conforme o teu último exemplo
    echo "$rules_json" | jq -c '
        map(. + {refine: (.refine // "")}) 
        | sort_by(.weight, .prefix) 
    '
}
tool_fn_catalog() {
    core_fn_catalog "$TOOL_DIR/$TOOL_NAME" "tool_fn_sort_weights"
}


unset TOOL_SKIP_INTERACTION
if [[ ! -t 1 && ! -t 2 ]]; then    
    # Estamos em "Silent Mode" (source > /dev/null 2>&1)
    # Podemos pular comandos visuais pesados como o stack_trace()
    TOOL_SKIP_INTERACTION=true
fi
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    # Opcional: só mostra a stack se estiver em modo debug
    [[ "$DEBUG" == "true" ]] && stack_trace

    tool_stage_workflow
    
    # Camada de Interatividade para o Vault
    if [[ "$TOOL_SKIP_INTERACTION" != "true" ]]; then
        #tool_functions_catalog
        echo "tool_functions_catalog"
    else
        echo "⚠️  Non-interactive mode: skipping token validation." >&2
    fi   
    
fi
