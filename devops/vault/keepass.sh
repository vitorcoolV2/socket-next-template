#!/bin/bash
# Filename: ../../../devops/vault/keepass.sh

### Estou chocado. depois do que vi aqui comprendo melhor o estado do mundo dos secredos
###


set +e

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ This is a library and should be sourced, not run directly."  2>&1
    echo "     Try: source ./$(realpath --relative-to="$PWD" "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")" 
    return 1 2> /dev/null || exit 1
fi

### import CORE && validate dependency context

_dir="$(dirname "${BASH_SOURCE[0]}")"
source  "$_dir/../core.sh" > /dev/null 2>&1

export RUNTIME_ROOT_DIR="/run/user/$UID/home2500"
require_vars RUNTIME_ROOT_DIR  || return 1 

_tool="keepassxc-cli"
if ! command -v "$_tool" &> /dev/null; then
    echo "
        Missing \"$_tool\".
        echo "Error: Missing \"$_tool\"."    
        echo "Install it from: https://keepassxc.org/download/"

        After install, run again.
    "; 
    return 1;
fi    

require_vars KP_DB || { echo "missing KP_DB var"; return 1; }

wrapper_client_key() {
    local KPID="$$"
    local SPLITTER_PATH="$(basename $(dirname $PWD))/$(basename $PWD)"
    local SCRIPT_PATH="${BASH_SOURCE[0]}"

    #echo "${#BASH_SOURCE[@]}" >&2
    #echo "${BASH_SOURCE[@]}" >&2

    local _dir="$(dirname "$_script_path")"
    
    local l1 l2 p
    l1=$(basename $SCRIPT_PATH) l1=${l1%.*}
    l2=$(sanitize_var_name $SPLITTER_PATH);


    local key="${l1}_${KPID}_${l2}"
    key="${key^^}"
    key=$(sanitize_var_name $key)
    echo "$key"
}

wrapper_lock() {
    local PID="$$"
    local ddname="$(wrapper_client_key)"
    #show_vars ddname

    (
        # Lock único baseado no nome do ficheiro
        exec 200>"/tmp/watcher_${ddname}.lock"
        if flock -n 200; then
            while kill -0 "$PID" 2>/dev/null; do
                sleep 2
            done
            # Cleanup silencioso e seguro
            [[ -f "$KP_PASS_FILE" ]] && shred -u -n 1 "$KP_PASS_FILE" 2>/dev/null
        fi
    ) & disown
}

wrapper_declare() {

    # "create" -> Se a chave não existir, cria a DB e a Key.
    export KP_OPEN_POLICY="${KP_OPEN_POLICY:-block}" # prodution mode
    ### expected user vars the KP_DB, KP_KEY location files
    export KP_DB="${KP_DB}"  # Default database path
    export KP_KEY="${KP_KEY}"  # Default key file paths

    local ddname="$(wrapper_client_key)"
    
    unset KP_PASS_FILE 
    KP_RUNTIME_DIR="$RUNTIME_ROOT_DIR/${ddname}" 
    KP_PASS_FILE="${KP_RUNTIME_DIR}/$(basename ${KP_DB%.*}).kp" 


    wrapper_lock 
 
    # 3. Keep the standard EXIT trap as a safety net
    #trap 'kp close' EXIT INT TERM
    #trap '[[ -f "$KP_PASS_FILE" ]] && echo "shred:'$KPID':$KP_PASS_FILE" && shred -u -n 1 "$KP_PASS_FILE" 2>/dev/null' EXIT INT TERM 

}
wrapper_declare


# keepass wrapper
kp() {
    local cmd="$1"
    shift
    local args=("$@") 

    if [[ -z "$cmd" ]]; then
        echo "Usage: kp <cmd> <arg> ..." >&2
        return 1
    fi

    # 1. Captura o STDIN (pipe) para um array, se existir
    local pipe_values=()
    if [[ ! -t 0 ]]; then
        mapfile -t pipe_values
    fi

    close_session() {
        if [[ -f "$KP_PASS_FILE" ]]; then
            # -u remove o ficheiro após o shred
            # -n 1 é suficiente para SSDs (evita desgaste excessivo)
            shred -u -n 1 "$KP_PASS_FILE"
            echo "✅ Ficheiro de sessão trap shredk." >&2
        else
            echo "ℹ️  Nenhum ficheiro de sessão encontrado para destruir." >&2
        fi
        unset KP_SESSION        
    }

    runtime_init() {    
        if [[ ! -d "$KP_RUNTIME_DIR" ]]; then
            echo "Creating private keepass runtime directory: $KP_RUNTIME_DIR"  >&2
            mkdir -p "$KP_RUNTIME_DIR"
            chmod 700 "$KP_RUNTIME_DIR"
        fi
        # Se require_locations for função externa, mantém. Se não, valida aqui:
        if [[ -z "$KP_RUNTIME_DIR" ]]; then
            echo "missing $KP_RUNTIME_DIR"  >&2
            return 1
        fi
        return 0
    }

    input_password() {      
        runtime_init || return 1
        
        # Mudei de "read" para "_get_password" para não quebrar o Bash
        _get_password() {
            local MASTER_PASSWORD            
            # Aqui usamos o comando 'read' original do sistema
            command read -rsp "🔑 Enter master password: " MASTER_PASSWORD
            echo ""  >&2
            echo -n "$MASTER_PASSWORD" > "$KP_PASS_FILE"
            chmod 600 "$KP_PASS_FILE"
        }
        runtime_init || return 1

        if _get_password; then
            # 2. Ativação do Watcher Singleton
            # Garante que, assim que o input é bem-sucedido, o monitoramento começa
            wrapper_lock || return 1
        else
            echo "❌ Erro: Unlock cancelado ou falhou." >&2
            return 1
        fi

    }

    open___create_policy() {        
        #  rules: 
        #   1: never overwrite DB 
        if [[ -f "$KP_DB" ]]; then
            #echo "exists"
            return 0
        fi
        echo "Creating keepass db file: $KP_DB" >&2
        generate_key() {
            require_vars KP_KEY 2> /dev/null || return 1
            
            if [[ ! -f "$KP_KEY" ]]; then
                echo "Generating new key file: $KP_KEY" >&2
                
                # Garante que a pasta onde a chave vai ficar existe
                mkdir -p "$(dirname "$KP_KEY")" 
                
                if openssl rand -out "$KP_KEY" 256; then
                    chmod 600 "$KP_KEY"
                else
                    echo "❌ Erro fatal: Falha ao gerar chave com openssl" >&2
                    return 1
                fi
            else
                echo "Key file already exists: $KP_KEY" >&2
                return 0 # Se já existe, não é erro, ok=0 apenas segue caminho
            fi
        }
        input_password || return 1
        generate_key "$KP_KEY" || return 1        
        
        show_vars KP_KEY KP_PASS_FILE
        cat KP_PASS_FILE
        if KEEPASSXC_CLI_PASSWORD="$(cat $KP_PASS_FILE)" keepassxc-cli db-create "$KP_DB" \
            --set-key-file "$KP_KEY" -p; then
            echo "✅ Database criada com sucesso." >&2
            return 0
        else
            echo "❌ Erro ao criar base de dados." >&2
            return 1
        fi
    }        

    open___block_policy() {
        if [[ ! -f "$KP_DB" || ! -f "$KP_KEY" ]]; then 
            echo "blocked"  >&2
            return 1; 
        fi
        input_password || return 1       
        return 0        
    }

    {
        ## show test vars
        test() {
            local debug=${1:-false}

            # Cores e Estilos
            local C_BLUE="\e[1;34m"
            local C_GREEN="\e[1;32m"
            local C_RED="\e[1;31m"
            local C_YELLOW="\e[1;33m"
            local C_BOLD="\e[1m"
            local C_OFF="\e[0m"            

            runtime_init || return 1

            wrapper_test() {
                local PID="$$"
                local ddname="$(wrapper_client_key)"
                              

                echo -e "\n${C_BOLD}🔍 Diagnosticando Wrapper:${C_OFF}"  >&2
                #show_vars PID  
                
                local WRAP_DESCRIBE="$ddname"       
                local WRAP_TEST=("ls" "/")
                
                echo -e "${C_BLUE}🔗 Contexto:${C_OFF} $WRAP_DESCRIBE"  >&2

                # --- Validação da DB ---
                if DEBUG="$debug" && ! require_files KP_DB; then
                    echo -e "${C_RED}  ❌ DB NOT OK:${C_OFF} Ficheiro ${C_BOLD}$KP_DB${C_OFF} ausente. Executa: ${C_YELLOW}kp open${C_OFF}"  >&2
                    return 1
                else    
                    echo -e "${C_GREEN}  ✅ DB OK:${C_OFF} Encontrado: $KP_DB"  >&2
                fi

                # --- Validação da Key ---
                if DEBUG="$debug" && require_vars KP_KEY && ! require_files KP_KEY; then
                    echo -e "${C_RED}  ❌ KEY NOT OK:${C_OFF} Chave definida mas ausente: ${C_BOLD}$KP_KEY${C_OFF}"  >&2
                    return 1
                else    
                    echo -e "${C_GREEN}  ✅ KEY OK:${C_OFF} Chave de validada com: [$KP_KEY]"  >&2
                fi

                # --- Validação da Sessão (Pass File) ---                 
                if [[ ! -f "$KP_PASS_FILE" ]]; then
                    echo -e "${C_YELLOW}  ⚠️  PASSWORD NOT FOUND:${C_OFF} Ficheiro de sessão ${C_BOLD}$KP_PASS_FILE${C_OFF} não encontrado."  >&2
                    return 1
                elif [[ ! -s "$KP_PASS_FILE" ]]; then
                    echo -e "${C_GREEN}  ⚠️ PASSWORD LOCKED:${C_OFF} Sessão ativa em: $KP_PASS_FILE"  >&2
                    return 1
                else
                    echo -e "${C_GREEN}  ✅ PASSWORD OK:${C_OFF} Sessão ativa em: $KP_PASS_FILE"  >&2                    
                fi

                echo -e "${C_BLUE} 🚀 Teste de Execução:${C_OFF} [${WRAP_TEST[*]}]"  >&2
                if ! res2=$(execute "${WRAP_TEST[@]}"); then
                    echo -e "${C_YELLOW}  ⚠️  SESSION NOT OK:${C_OFF}."  >&2
                    echo $res >&2
                    return 1                
                fi
                echo -e "${C_GREEN}  ✅ SESSION OK:${C_OFF} Sessão ativa"  >&2
                return 0
            }

            required() {                                   
                DEBUG="$debug" require_vars KP_OPEN_POLICY \
                                            KP_DB \
                                            KP_KEY \
                                            KP_PASS_FILE || { echo "export *UNDEF* vars"; return 1; }
            }            
            (
                if DEBUG="$debug" && ! require_vars KP_KEY && require_files KP_KEY; then
                    
                    echo -e "${C_RED}❗ ERRO CRÍTICO:${C_OFF} KP_KEY em falta no ambiente."  >&2
                    # Chama o teu debug_link_file (que já tem cores)
                    #local env_file="${!KENV}"
                    #debug_link_file "envfile" "$env_file" "^KP_KEY"
                fi
            )

            required && wrapper_test             
        }

        execute() {      
            local cmd="$1"
            shift
            local args=("$@") 
        
            if [[ -f "$KP_PASS_FILE" ]] ; then        
                local current_pass="$(cat "$KP_PASS_FILE")"
                ## OK it is hear. echo "$current_pass" >&2
                # Passar a password via stdin de forma segura
                #show_vars cmd KP_DB KP_KEY current_pass
                # 2. Agrupar todo o input para o keepassxc-cli
                {
                    # Primeiro enviamos a Master Password da base de dados
                    printf "%s\n" "$current_pass"
                    
                    # Depois enviamos quaisquer valores adicionais (ex: a nova password do entry)
                    for val in "${pipe_values[@]}"; do
                        printf "%s\n" "$val"
                    done
                } | keepassxc-cli "$cmd" "$KP_DB" --key-file "$KP_KEY" "${args[@]}"
            else
                echo "❌ Erro: Sessão não iniciada. Execute Falta definir (KP_PASS_FILE ausente)." >&2
                ## dev message echo "❌ Erro: Sessão não iniciada. Falta definir (KP_PASS_FILE ausente)." >&2
                return 1
            fi
        }
            
    }

    kp_init() {
        local force=false
        local check_only=false
        
        # Parse arguments
        for arg in "$@"; do
            case "$arg" in
                --force|-f)
                    force=true
                    ;;
                --check|-c)
                    check_only=true
                    ;;
                --help|-h)
                    echo "Usage: kp init [--force] [--check]"
                    echo "  --force, -f  Reinitialize even if DB exists"
                    echo "  --check, -c  Only validate setup, don't create"
                    return 0
                    ;;
            esac
        done
        
        echo "🚀 Initializing KeePass configuration..." >&2
        
        # Validate required variables
        if ! require_vars KP_DB KP_KEY 2>/dev/null; then
            echo "❌ Error: KP_DB and KP_KEY must be defined" >&2
            return 1
        fi
        
        # Create directories
        mkdir -p "$(dirname "$KP_DB")" || { echo "❌ Cannot create KP_DB directory"; return 1; }
        mkdir -p "$(dirname "$KP_KEY")" || { echo "❌ Cannot create KP_KEY directory"; return 1; }
        
        # Check existing setup
        if [[ -f "$KP_DB" ]]; then
            echo "✅ DB already exists: $KP_DB" >&2
            if [[ "$force" == "true" ]]; then
                echo "⚠️  Will reinitialize (--force)..." >&2
            fi
        else
            echo "ℹ️  DB not found: $KP_DB" >&2
        fi
        
        if [[ "$check_only" == "true" ]]; then
            [[ -f "$KP_KEY" ]] && echo "✅ Key file exists: $KP_KEY" || echo "❌ Key file missing: $KP_KEY"
            return 0
        fi
        
        # Generate key file if missing
        if [[ ! -f "$KP_KEY" ]] || [[ "$force" == "true" ]]; then
            echo "🔐 Generating key file: $KP_KEY" >&2
            if ! openssl rand -out "$KP_KEY" 256 2>/dev/null; then
                echo "❌ Error: Failed to generate key file" >&2
                return 1
            fi
            chmod 600 "$KP_KEY"
            echo "✅ Key file created" >&2
        else
            echo "✅ Key file already exists: $KP_KEY" >&2
        fi
        
        # Check if we should proceed (check mode)
        if [[ "$check_only" == "true" ]]; then
            return 0
        fi
        
        # Create DB if missing or force
        if [[ ! -f "$KP_DB" ]] || [[ "$force" == "true" ]]; then
            echo "📦 Creating KeePass database: $KP_DB" >&2
            
            # Get master password - support env var or stdin
            local master_pass=""
            
            if [[ -n "$KP_MASTER_PASSWORD" ]]; then
                master_pass="$KP_MASTER_PASSWORD"
                echo "🔑 Using KP_MASTER_PASSWORD from environment" >&2
            elif [[ ! -t 0 ]]; then
                # Read from stdin (pipe)
                read -r master_pass
            else
                runtime_init || return 1
                echo -n "🔑 Enter master password for new database: " >&2
                command read -rs master_pass
                echo "" >&2
            fi
            
            if [[ -z "$master_pass" ]]; then
                echo "❌ Error: Password cannot be empty" >&2
                return 1
            fi
            
            # Create DB with key file - pass password twice for confirmation
            if printf '%s\n%s\n' "$master_pass" "$master_pass" | keepassxc-cli db-create "$KP_DB" --set-key-file "$KP_KEY" -p 2>&1; then
                echo "✅ Database created successfully" >&2
                
                # Save session password
                echo -n "$master_pass" > "$KP_PASS_FILE"
                chmod 600 "$KP_PASS_FILE"
                
                # Activate session
                wrapper_lock || return 1
                export KP_SESSION=1
                
                echo "✅ KeePass initialized and session opened" >&2
                return 0
            else
                echo "❌ Error: Failed to create database" >&2
                return 1
            fi
        else
            echo "✅ Database already exists: $KP_DB" >&2
        fi
        
        return 0
    }

    # Lógica Principal de Inicialização
    if [[ "$cmd" == "close" ]]; then
        close_session 
        #return 0    
    elif [[ "$cmd" == "test" ]]; then            
        test "${args[@]}"
        return 0    
    elif [[ "$cmd" == "init" ]]; then
        kp_init "${args[@]}"
        return 0
    elif [[ "$cmd" == "create" ]]; then        
        local openHandler="open___${KP_OPEN_POLICY:-block}_policy"            
        return 0    
    elif [[ "$cmd" == "open" ]]; then       
        # 1. Se o ficheiro de password não existe, pede ao utilizador
        if [[ ! -f "$KP_PASS_FILE" ]] || [[ ! -s "$KP_PASS_FILE" ]]; then
            # a lógica de "unlock file" ou pedir pass novamente
            input_password || return 1
        fi
        local openHandler="open___${KP_OPEN_POLICY:-block}_policy"
        "$openHandler" || return 1
        export KP_SESSION=1
        return 0  
    fi
       
    ### Apply open KP_OPEN_POLICY
    if [[ ! -f "$KP_DB" ]] ; then
        local openHandler="open___${KP_OPEN_POLICY:-block}_policy"
        echo $openHandler  >&2
        "$openHandler" || return 1
        export KP_SESSION=1
    fi
    #### 

    # Execução do Comando    
    execute "$cmd" "${args[@]}" || return 1

}

# Function: List all entries

kp_list() {
    kp ls
}


# Function: Retrieve an entry's password
kp_show() {
    local entry="$1"
    if [[ -z "$entry" ]]; then
        echo "Usage: kp_skow <entry>" >&2
        return 1
    fi
    require_vars entry    

    kp open
    kp show "$entry"
}

# Function: Copy an entry's password to clipboard
kp_clip() {
    local entry="$1"
    if [[ -z "$entry" ]]; then
        echo "Usage: kp_clip <entry>" >&2
        return 1
    fi

    kp open
    kp clip "$entry"
}


## esta funcao kp open devera ser usada por funcoes que partilhem a session

# --- FUNÇÃO DE BUSCA (Silenciosa para capturas) ---




# --- Helper: Recursive MKDIR for KeePass ---

# OK
kp_mkdir_p() {
    local full_path="$1"
    require_vars full_path || return 1   

    if kp ls "$full_path" >/dev/null 2>&1; then
        return 0
    fi

    # 2. Se não existe, iteramos.
    local current_path=""
    IFS='/' read -ra PARTS <<< "$full_path"
    
    for part in "${PARTS[@]}"; do
        [[ -z "$part" ]] && continue
        
        if [[ -z "$current_path" ]]; then
            current_path="$part"
        else
            current_path="$current_path/$part"
        fi

        # 3. Só tentamos criar se o 'ls' falhar para este nível específico
        # Isso evita o overhead de escrita na DB se o grupo pai já existir
        if ! kp ls "$current_path" >/dev/null 2>&1; then
            kp mkdir "$current_path" >/dev/null 2>&1
        fi
    done
}
# ok test: kp_save_entry "vault/caminho/para/SECREDO" "uuuuuu"
kp_save_entry() {
    local entry_path="$1"
    local entry_value="$2"
    require_vars entry_path entry_value || return 1
    local group_path="${entry_path%/*}"
     
    kp open
    kp_mkdir_p "$group_path"    
   
    # 1. Tentar ADICIONAR
    # printf envia a password duas vezes (necessário para 'add')
    printf "%s\n%s\n%s\n" "$entry_value" "$entry_value" | \
    kp add --password-prompt "$entry_path" >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo "📝 kp Created: '$entry_path'"  >&2
    else
        # 4. Se falhar, o entry existe -> Editar (Edit)
        printf "%s\n%s\n" "$entry_value" | \
        kp edit --password-prompt "$entry_path" >/dev/null 2>&1
        echo "🔄 kp Updated: '$entry_path'"  >&2
    fi
}

# OK test kp_get_entry_value "vault/caminho/para/SECREDO" 
kp_get_entry_value() {
    local entry_path="$1"
    require_vars entry_path || return 1
    kp open

    # O segredo vai para o stdout, o resto para stderr
    kp show -q -a "Password" "$entry_path" 2>/dev/null
}

# OK test kp_save_approle "vault/AppRole/test" "THE_ROLE_ID" "THE_SECRET_ID"
kp_save_approle() {
    local entry_path="$1"
    local role_id="$2"
    local secret_id="$3"

    require_vars entry_path role_id secret_id || return 1
    kp open || return 1

    # Ensure Group exists
    local group_path="${entry_path%/*}"    
    kp_mkdir_p "$group_path"        

    # Add or Edit the entry
    printf "%s\n%s\n" "$secret_id" "$secret_id" | \
    kp add -q --password-prompt --username "$role_id" "$entry_path" >/dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        # If it exists, update the password and username
        kp edit -q --username "$role_id" "$entry_path" 2>/dev/null
        printf "%s\n" "$secret_id" | \
        kp edit -q --password-prompt "$entry_path" 2>/dev/null
        echo "🔄 kp AppRole '$entry_path' updated."  >&2
    else
        echo "📝 kp AppRole '$entry_path' created."  >&2
    fi
}

# OK test kp_get_approle "vault/AppRole/test"
kp_get_approle() {
    local entry_path="$1"

    require_vars entry_path || return 1
    kp open || return 1


    # 1. Recuperar o Username (RoleID)    
    local role_id=$(kp show -q -a username "$entry_path" 2>/dev/null)
    local secret_id=$(kp show -q -a password "$entry_path" 2>/dev/null)

    if [ -n "$role_id" ] && [ -n "$secret_id" ]; then
        echo "$role_id $secret_id"
    else
        return 1
    fi
}
# OK test kp_get_entry_user "vault/AppRole/test" 
kp_get_entry_user() {
    local entry_path="$1"

    require_vars entry_path || return 1
    kp open || return 1

    # 1. Recuperar o Username (RoleID)
    local role_id=$(kp show -q -a username "$entry_path" 2>/dev/null)

    if [ -n "$role_id" ]; then
        echo "$role_id"
    else
        return 1
    fi
}
# OK test kp_get_entry_pass "vault/AppRole/test" 
kp_get_entry_pass() {
    local entry_path="$1"

    require_vars entry_path || return 1
    kp open || return 1

    # 2. Recuperar a Password (SecretID)
    local secret_id=$(kp show -q -a Password "$entry_path" 2>/dev/null)

    if [ -n "$secret_id" ]; then
        echo "$secret_id"
    else
        return 1
    fi
}
# kp_save_ca_pair "vault/pki/test-ca" "111" "ssss"
kp_save_ca_pair___notes() {
    local entry_path="$1"
    local cert_val="$2"
    local key_val="$3"

    require_vars entry_path cert_val key_val || return 1
    kp open || return 1
    local group_path="${entry_path%/*}"
    kp_mkdir_p "$group_path"    
    
    # 2. Criar a entrada se não existir (com pass temporária)
    if ! kp ls "$entry_path" >/dev/null 2>&1; then
        printf "%s\n%s\n%" "temp" "temp" | \
        kp add --password-prompt "$entry_path" >/dev/null 2>&1
    fi

    printf "%s\n%s\n" "$key_val" "$key_val" | \
    kp edit --password-prompt "$entry_path" >/dev/null 2>&1

    # 4. ATUALIZAR AS NOTES (CERT)
    local tmp_cert=$(mktemp)
    echo "$cert_val" > "$tmp_cert"
    kp edit --notes "$(cat $tmp_cert)" "$entry_path" >/dev/null 2>&1
    rm "$tmp_cert"

    echo "🔒 Sucesso: Chave Privada na Password e Certificado nas Notes."  >&2
    return 0 
}
# kp_save_ca_pair "vault/pki/test-ca" "111" "ssss"
kp_save_ca_pair() {
    local entry_path="$1"
    local cert_val="$2"
    local key_val="$3"

    require_vars entry_path cert_val key_val || return 1
    
    # 1. Garante que o grupo existe
    local group_path="${entry_path%/*}"
    kp_mkdir_p "$group_path"    
    
    # 2. Criar ou Atualizar a Entrada (Password = Private Key)
    if ! kp ls "$entry_path" >/dev/null 2>&1; then
        printf "%s\n%s\n" "$key_val" "$key_val" | kp add -p -q "$entry_path" >/dev/null 2>&1
        echo "📝 Created: '$entry_path'"  >&2
    else
        printf "%s\n" "$key_val" | kp edit -p -q "$entry_path" >/dev/null 2>&1
        echo "🔄 Updated: '$entry_path'"  >&2
    fi

    # 3. Gerir Ficheiros Temporários para Anexos
    local tmp_dir
    tmp_dir=$(mktemp -d -t kp-vault-XXXXXX)
    
    # Criar os ficheiros reais na pasta temporária
    echo "$cert_val" > "$tmp_dir/cert.pem"
    echo "$key_val" > "$tmp_dir/key.pem"
    
    # 4. Importar como Anexos (Attachments)
    # Nota: O comando correto é 'attachment-import'
    local err=0
    kp attachment-import -q "$entry_path" "cert.pem" "$tmp_dir/cert.pem" || err=1
    kp attachment-import -q "$entry_path" "key.pem" "$tmp_dir/key.pem" || err=1

    # Limpeza imediata
    rm -rf "$tmp_dir"

    if [ $err -eq 0 ]; then
        echo "📎 Success: Cert and Key saved as attachments in '$entry_path'"  >&2
        return 0
    else
        echo "❌ Error: Failed to import attachments." >&2
        return 1
    fi
}


kp_archive_vault() {
    local SRC="vault"
    local TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    local DEST_ROOT="Backup/vault-archive-$TIMESTAMP"

    echo "📦 Starting Granular Archive of '$SRC'..."  >&2
    kp open || return 1

    local entries=$(kp ls -R -f "$SRC")
    
    if [ -z "$entries" ]; then
        echo "ℹ️  Vault is already empty or group does not exist."  >&2
        return 0
    fi
    ### target
    kp_mkdir_p "$DEST_ROOT" >/dev/null 2>&1 || true


    # 3. copiar cada entrada individualmente
    printf "%s\n" $entries | while read -r entry_rel_path; do
        # Ignorar se estiver vazio ou se for um diretório
        [[ -z "$entry_rel_path" || "$entry_rel_path" == */ ]] && continue
        
        local _src_path="$SRC/$entry_rel_path"
        
        # Determinar o grupo de destino
        local _target_path="$DEST_ROOT"
        if [[ "$entry_rel_path" == */* ]]; then
            _target_path="$DEST_ROOT/${entry_rel_path%/*}"
            # Criar subpastas no destino se necessário
            kp_mkdir_p "$_target_path" >/dev/null 2>&1 
        fi

        echo "  🚚 Copying: $entry_rel_path"  >&2
        
        # Mover a entrada para o grupo de destino
        kp cp "$_src_path" "$_target_path/" >/dev/null 2>&1
    done
    # -----------------------------

    echo "✅ Granular archive completed: $DEST_ROOT"  >&2
}

# --- Quick Test ---
# Usage: kp_tesp1
kp_tesp1() {
    echo "🧪 Testing Vault Functions..."  >&2
    kp_save_entry "Backup/Test-Context" "dev-secret-123"
    local val=$(kp_get_entry_value "Backup/Test-Context")
    echo "🔍 Retrieved Test Value: $val"  >&2
}

kp_sort_weights() {
    local rules_json
    rules_json=$(cat <<-'EOF'
[
  {
    "prefix": "kp_*",
    "weight": 20,
    "cat": "CLI"
  },
  {
    "prefix": "kp|*wrapper*",    
    "weight": 10,
    "cat": "CLI-WRAPPER"
  },
  {
    "prefix": "runtime*|*password*|*session*",
    "weight": 31,
    "cat": "CLI-FEATURES"
  },
  {
    "prefix": "*env*|*open*|*close*",
    "refine": "",
    "weight": 32,
    "cat": "CLI-REQ"
  },
  {
    "prefix": ".",
    "refine": "",
    "weight": 90,
    "cat": "MISC"
  }
]
EOF
)
    echo "$rules_json" | jq -c '
        map(. + {refine: (.refine // "")}) 
        | sort_by(.weight, .prefix) 
    '
}

kp_fn_catalog() {
    # core_fn_sort_json "${BASH_SOURCE[0]}" "kp_sort_weights" 
    core_fn_catalog "${BASH_SOURCE[0]}" "kp_sort_weights" 
}

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    if [[ -t 1 || -t 2 ]]; then      
        kp test
    fi
    
fi    