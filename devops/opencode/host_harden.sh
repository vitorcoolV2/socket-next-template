# path: devops/opencode/host_harden.sh
#!/bin/bash


. ../core.sh
# --- CONFIGURAÇÃO DE IDENTIDADE ---
# O GID 2500 deve existir no host para coincidir com o container
. .env
APP_UID=2500
APP_GID=2500
APP_GROUPS="stewards"
APP_USER="steward"
APP_USER_HOME="/home/$APP_USER"

# Identidade do Dono (Host)
APP_OWNER=${USER}
APP_OWNER_UID=${UID}

echo "🚀 Iniciando provisionamento e hardening para $APP_USER..."

# 1. Garantir que o grupo e o utilizador existem no Host
if ! getent group $APP_GROUPS > /dev/null; then
    echo "⚠️ Criando grupo $APP_GROUPS ($APP_GID) no host..."
    sudo groupadd -g $APP_GID $APP_GROUPS
fi

if ! id "$APP_USER" &>/dev/null; then
    echo "👤 Criando utilizador $APP_USER ($APP_UID)..."
    sudo useradd -m -u $APP_UID -g $APP_GROUPS -s /bin/bash -d "$APP_USER_HOME" $APP_USER
    sudo chown -R $APP_USER:$APP_GROUPS "$APP_USER_HOME"
    sudo chmod -R 570 "$APP_USER_HOME"
else
    echo "ℹ️ Identidade '$APP_USER' já existe."
fi

# Adicionar vitor ao grupo stewards e steward ao grupo vitor para partilha total
echo "🔗 Sincronizando grupos entre $APP_OWNER e $APP_USER..."
sudo usermod -aG $APP_GROUPS $APP_OWNER
sudo usermod -aG $APP_GROUPS $APP_USER

# 2. Desbloquear motores para o Steward (Zero-Sudo)
ENGINE_GROUPS=("docker" "kvm" "libvirt" "render")
for grp in "${ENGINE_GROUPS[@]}"; do
    if getent group "$grp" > /dev/null; then
        sudo usermod -aG "$grp" $APP_USER
    fi
done

# 3. Ajuste de Soberania da Home do Owner (vitor)
# Remove acesso ao "mundo" (outros) e dá acesso de leitura ao grupo stewards
echo "🛡️  Protegendo Home de $APP_OWNER contra terceiros..."
sudo chmod 750 "/home/$APP_OWNER"
sudo chown $APP_OWNER:$APP_OWNER "/home/$APP_OWNER"

echo "🛡️ Aplicando perfil de segurança para pastas de credenciais..."

# 4. Pastas de Credenciais e Configuração
# Definimos vitor:stewards e permissão 750 (Dono: tudo, Grupo: ler/entrar)
READONLY=(    
    "/home/$APP_OWNER/.docker"    
    "/home/$APP_OWNER/.cargo"
)

for dir in "${TARGETS[@]}"; do
    if [ -d "$dir" ]; then
        echo "✅ RO: $dir"
        sudo chown -R $APP_OWNER:$APP_GROUPS "$dir"
        sudo chmod -R 750 "$dir"
        # Garantir que chaves privadas continuam protegidas (640 - grupo lê, outros nada)
        find "$dir" -type f -name "*id_rsa*" -o -name "*.key" -o -name "*.conf" -exec sudo chmod 640 {} +
    fi
done


SHARE=(
    /home/$APP_OWNER/.local/share/opencode
    /home/$APP_OWNER/.local/state/opencode
    /home/$APP_OWNER/.opencode
)

for dir in "${SHARE[@]}"; do
    if [ -d "$dir" ]; then
        echo "✅ Partilhar RW: $dir"
        sudo chown -R $APP_OWNER:$APP_GROUPS "$dir"
        sudo chmod -R 770 "$dir"
        # Garantir que chaves privadas continuam protegidas (640 - grupo lê, outros nada)
        find "$dir" -type f \
          -name "*id_rsa*" -o \
          -name "*.key" -o \
          -name "*.conf" \
          -exec sudo chmod 640 {} +
    fi
done


# 5. Ficheiros Isolados na Home do Owner
SHARABLES=(
    "/home/$APP_OWNER/.ssh"
    "/home/$APP_OWNER/keys"
    "/home/$APP_OWNER/.wireguard"
    "/home/$APP_OWNER/privatekey"
    "/home/$APP_OWNER/publickey"
    "/home/$APP_OWNER/presharedkey"
    "/home/$APP_OWNER/client_mobile.conf"
    "/home/$APP_OWNER/peer_mobile.conf"
    "/home/$APP_OWNER/.config"
)

# NOT SHARED...
for path in "${SHARABLES[@]}"; do
    if [ -f "$path" ]; then
        sudo chown $APP_OWNER:$APP_GROUPS "$path"
        sudo chmod 600 "$path"
    elif [ -d "$path" ]; then
        sudo chown -R $APP_OWNER:$APP_GROUPS "$path"
        sudo chmod -R 700 "$path" # just can add new files. can not change existing files.        
    fi
done

# 6. Corrigir a pasta do projeto real
PROJECT_DIR="/mnt/ssd980/Projects/nextjs-app-template/devops"
if [ -d "$PROJECT_DIR" ]; then
    echo "🏗️ Corrigindo ownership do projeto: $PROJECT_DIR"
    sudo chown -R $APP_OWNER:$APP_OWNER "$PROJECT_DIR"
    sudo chmod -R 755 "$PROJECT_DIR"
fi

# 7. Garantir permissões na Home do Steward
echo "🛠️  Auditando permissões em $APP_USER_HOME..."
sudo chown -R $APP_USER:$APP_GROUPS "$APP_USER_HOME"
sudo chmod 770 "$APP_USER_HOME"

echo "---"
echo "✨ Provisionamento completo."
echo "Steward e Vitor sincronizados. Acesso de 'outros' removido da Home."