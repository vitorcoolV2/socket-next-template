#!/bin/bash
# Filename: 00-kvm-bliss_lib.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source $(realpath ../core.sh)

check_main_mount


[ -f .env ] && source .env
## required .env file
export VM_ISO_PATH="${VM_ISO_PATH}"
export VM_HOST_MOUNT_LOCATION=${VM_HOST_MOUNT_LOCATION}

# VM_GRAPH_MODE can be: default, scrcpy, nvidia
export VM_GRAPH_MODE=${VM_GRAPH_MODE,-default}
export VM_RAM_MB=${VM_RAM_MB,-4096}
export VM_CPU_CORES=${VM_CPU_CORES,-4}

### expect .env file vars
require_vars \
    VM_HOST_MOUNT_LOCATION\
    BLISS_ISO_BROWSE_URL \
    VM_ISO_PATH \
    VM_NAME \
    VM_OS_VARIANT \
    VM_RAM_MB \
    VM_CPU_CORES \
    VM_GRAPH_MODE 


show_vars \
    VM_HOST_MOUNT_LOCATION\
    BLISS_ISO_BROWSE_URL \
    VM_ISO_PATH \
    VM_NAME \
    VM_OS_VARIANT \
    VM_RAM_MB \
    VM_CPU_CORES \
    VM_GRAPH_MODE 
require_locations "VM_HOST_MOUNT_LOCATION" 

require_binaries "whoami" "jq"
## define relative locations
#>>>>>>>>>>>>>>>>>> vm disk location
export VM_DISK0_FILE="$VM_HOST_MOUNT_LOCATION/$VM_NAME.qcow2"

#>>>>>>>>>>>>>>>>>> vm nvram for (whoami)(vm Instance name: $VM_NAME ) 
export VM_NVRAM_DIR=$(realpath ./nvram)
export VM_NVRAM_VARS_FILE="$VM_NVRAM_DIR/$VM_NAME-VARS.fd"
export VM_NVRAM_CODE_FILE="$VM_NVRAM_DIR/$VM_NAME-CODE.fd"

#>>>>>>>>>>>>>>>>>> nvidia
export VM_HOST_NVIDIA_CONF_FILE=$(nvidia_egl_json_file)
require_files VM_HOST_NVIDIA_CONF_FILE && cat $VM_HOST_NVIDIA_CONF_FILE | jq

# >>>>>>>>>>>>>>>>> devices
export VM_RENDER_DEVICE="/dev/dri/renderD128"
export VM_CARD_DEVICE="/dev/dri/card1"
export VM_NVCARD_DEVICE="/dev/nvidia0"
export VM_NVCTL_DEVICE="/dev/nvidiactl"
export VM_NVMODESET_DEVICE="/dev/nvidia-modeset"

require_devices \
    VM_RENDER_DEVICE \
    VM_CARD_DEVICE \
    VM_NVCARD_DEVICE \
    VM_NVCTL_DEVICE \
    VM_NVMODESET_DEVICE




# >>>>>>>>>>>>>>>>>>>>>>>>> nvidea real accel
if [ "$VM_GRAPH_MODE" = "nvidia" ]; then   
    export GDK_BACKEND=x11
    export SHM_RENDER_DEVICE=$VM_RENDER_DEVICE
    export __GLX_VENDOR_LIBRARY_NAME=$VM_GRAPH_MODE
    export __EGL_VENDOR_LIBRARY_FILENAMES="$VM_HOST_NVIDIA_CONF_FILE"

    show_vars GDK_BACKEND SHM_RENDER_DEVICE __GLX_VENDOR_LIBRARY_NAME __EGL_VENDOR_LIBRARY_FILENAMES
fi    

require_files \
    VM_DISK0_FILE \
    VM_NVRAM_VARS_FILE \
    VM_NVRAM_CODE_FILE \
    VM_ISO_PATH \
    VM_HOST_NVIDIA_CONF_FILE
 
### ######
###
# 1. fullfill requirements. not optimized for after success
os_package_setup() {
    require_binaries apt systemctl adduser
    
    sudo apt update
    # base kvm, virtlib
    sudo apt install qemu-kvm libvirt-daemon-system libvirt-clients virt-manager bridge-utils ovmf -y
    
    ## glx
    sudo apt install libva-glx2 libegl1-mesa-dev libgles2-mesa-dev -y

    ## som
    sudo apt install pavucontrol -y

    ## video accel3d
    sudo apt install libnvidia-egl-wayland1 libegl1-mesa-dev -y

    ## screen
    sudo apt install minicom -y

    ## vnc
    sudo apt install tigervnc-viewer -y

    ## disk tools
    sudo apt install libguestfs-tools -y
    sudo apt install guestfs-tools guestfish -y

    # Instala as ferramentas se não as tiveres
    sudo apt install -y apparmor-utils

    # Coloca o helper do libvirt em modo de permissão total
    sudo aa-complain /usr/lib/libvirt/virt-aa-helper

    # Adicionar utilizador aos grupos
    sudo adduser "$USER" libvirt
    sudo adduser "$USER" kvm

    # Garantir que o serviço e o socket estão ativos
    sudo systemctl enable --now libvirtd
    sudo systemctl enable --now libvirtd.socket
    
    echo "Pacotes instalados. Nota: Pode ser necessário Logout/Login para grupos surtirem efeito sem 'sg'."
}



# 2. run virtual machine manager
run_vmm(){
    require_binaries newgrp sg
    
    sg libvirt -c virt-manager
}

is_valid_iso() {
    local file_path="$1"
    if [ ! -s "$file_path" ]; then return 1; fi

    local mime_type=$(file -b --mime-type "$file_path")

    case "$mime_type" in
        *iso9660*|*octet-stream*|*x-executable*)
            return 0
            ;;
        *)
            echo "Aviso: Tipo de ficheiro inválido detetado: $mime_type"
            return 1
            ;;
    esac
}

bliss_image_download() {
    # Apenas valida se o ficheiro que baixaste manualmente está lá
    if [ -f "$VM_ISO_PATH" ]; then
        if is_valid_iso "$VM_ISO_PATH"; then
            echo "✅ ISO Seguro e Validado: $VM_ISO_PATH"
            # 1. Dá permissão de leitura ao ISO para o sistema
            chmod 644 "$VM_ISO_PATH"
            return 0
        fi
    fi
    echo "❌ ISO não encontrado ou inválido em: $VM_ISO_PATH"
    echo "⚠️  Não apagues o ficheiro! Move o download concluído para este local."

    local bip="$(dirname "$VM_ISO_PATH")"
    echo "----------------------------------------------------------------"
    echo "DOWNLOAD MANUAL NECESSÁRIO"
    echo "1. URL: $BLISS_ISO_BROWSE_URL"
    echo "2. Guarda como: $(basename "$VM_ISO_PATH")"
    echo "3. Move para: $bip"
    echo "----------------------------------------------------------------"

    ls -la "$bip"
    return 1
}

#VM_ISO_PATH="/var/lib/libvirt/images/Bliss-v14.10.3-x86_64-OFFICIAL-opengapps-20241012.iso"
#VM_OS_VARIANT="android-x86-9.0"
check_os_android() {
    require "VM_ISO_PATH" "OS_VARIANT"    
    local osv=virt-install --osinfo list | grep "$OS_VARIANT" | head -n 1
    if [ $osv == $OS_VARIANT ]; then
        return 0
    else
        return 1
    fi
}

etc_qemu__allow_virbr0() {
    echo "Create qemu bridge."
    # Criar o diretório que falta
    sudo mkdir -p /etc/qemu

    # Adicionar a permissão para a bridge padrão do libvirt
    echo "allow virbr0" | sudo tee /etc/qemu/bridge.conf

    # Ajustar as permissões do ficheiro
    sudo chmod 644 /etc/qemu/bridge.conf

    # Dar permissões de execução root ao helper
    sudo chmod u+s /usr/lib/qemu/qemu-bridge-helper
}
export -f etc_qemu__allow_virbr0

etc_libvirt_qemu() {
    echo "🛠️  A verificar permissões do Hypervisor (/etc/libvirt/qemu.conf)..."
    

    echo "⚠️  Ajuste necessário: O KVM precisa de correr como '$USER' para aceder à tua Home/SSD."
    echo "📝 Vou atualizar user/group para: \"$USER\""

    # 1. Remove todas as linhas existentes de user/group/dynamic_ownership para limpar o lixo
    sudo sed -i '/^user =/d' /etc/libvirt/qemu.conf
    sudo sed -i '/^group =/d' /etc/libvirt/qemu.conf
    sudo sed -i '/^dynamic_ownership =/d' /etc/libvirt/qemu.conf
    sudo sed -i '/^security_driver =/d' /etc/libvirt/qemu.conf

    sudo sed -i '/^vnc_allow_host_audio =/d' /etc/libvirt/qemu.conf
    sudo sed -i '/^nographics_allow_host_audio =/d' /etc/libvirt/qemu.conf
    sudo sed -i '/^#virt_aa_helper =/d' /etc/libvirt/qemu.conf
    sudo sed -i '/^remember_owner =/d' /etc/libvirt/qemu.conf

    # 2. Adiciona as configurações limpas no final do ficheiro
    echo "user = \"$USER\"" | sudo tee -a /etc/libvirt/qemu.conf
    echo "group = \"$USER\"" | sudo tee -a /etc/libvirt/qemu.conf
    
    echo 'dynamic_ownership = 0' | sudo tee -a /etc/libvirt/qemu.conf
    echo 'security_driver = "none"' | sudo tee -a /etc/libvirt/qemu.conf

    echo 'vnc_allow_host_audio = 1' | sudo tee -a /etc/libvirt/qemu.conf
    echo 'nographics_allow_host_audio = 1' | sudo tee -a /etc/libvirt/qemu.conf
    echo "virt_aa_helper = \"\"" | sudo tee -a /etc/libvirt/qemu.conf
    # Garante que o isolamento de memória não interfira
    echo "remember_owner = 0" | sudo tee -a /etc/libvirt/qemu.conf

    
    # Garante que o cgroup permite a GPU
    if ! sudo grep -q "renderD128" /etc/libvirt/qemu.conf; then
        echo 'cgroup_device_acl = ["/dev/null", "/dev/full", "/dev/zero", "/dev/random", "/dev/urandom", "/dev/ptmx", "/dev/kvm", "/dev/dri/renderD128", "/dev/dri/card0", "/dev/nvidia0", "/dev/nvidiactl", "/dev/nvidia-modeset"]' | sudo tee -a /etc/libvirt/qemu.conf
    fi    

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<
    # DISPLAY CHANGES

    #sudo grep -E "cgroup_device_acl =" /etc/libvirt/qemu.conf

    
    # 1. Adiciona o teu utilizador aos grupos de virtualização
    sudo usermod -aG libvirt,kvm,libvirt-qemu $USER
    # 2. Atribui permissões de leitura ao ficheiro de configuração para o grupo libvirt
    sudo chown root:libvirt /etc/libvirt/qemu.conf
    sudo chmod 640 /etc/libvirt/qemu.conf

    sudo setfacl -m u:vitor:rw /run/user/$(id -u)/pulse/native
    sudo setfacl -m u:vitor:rw /dev/dri/renderD128
    sudo setfacl -m u:vitor:rw /dev/dri/card1

    sudo chown -R libvirt-qemu:kvm "$VM_NVRAM_DIR"
    sudo chown root:$USER /usr/lib/qemu/qemu-bridge-helper
    sudo chmod 4755 /usr/lib/qemu/qemu-bridge-helper

    # 3. Reiniciar o serviço para validar a nova identidade
    sudo systemctl restart libvirtd
}



# Exemplo de uso do jq para validar o driver
check_nvidia_driver_config() {
    require_functions _nvidia_egl_json
    require_binaries jq
    local json_file=$(_nvidia_egl_json)
    require_files $json_file
    local driver_path=$(jq -r '.ICD.library_path' "$json_file")
    
    if [[ "$driver_path" == *"nvidia"* ]]; then
        echo "✅ Driver NVIDIA detetado no JSON: $driver_path"
        cat $nvidia_json | jq .
    else
        echo "❌ Erro: O ficheiro JSON não aponta para o driver NVIDIA."
    fi
}

### offline volume VM_DISK0_FILE guestfish base tools
__hd_cmd() {    
    require_vars VM_DISK0_FILE
    local device="${1:-vda2}" 
    local input_cmd="$2"    
    
    # Converte a string num array (split por espaço)
    read -r -a cmd_array <<< "$input_cmd"

    echo "📝 Executando [${cmd_array[*]}] em /dev/$device via guestfish nativo..."
    echo "${cmd_array[@]}"
    # Usamos printf para formatar os argumentos corretamente para o interpretador do guestfish
    guestfish -a "$VM_DISK0_FILE" <<EOF
run
mount "/dev/$device" /
${cmd_array[@]}
quit
EOF
}
# Função rápida para upload (podes adicionar ao teu script)
__hd_upload() {
    require_vars VM_DISK0_FILE
    local device="${1:-vda2}"    
    local src="$2"
    local dest="$3"

    echo "📥 Uploading  [$src] to: /dev/$device  [$dest]..."
    
    guestfish -a "$VM_DISK0_FILE" <<EOF
run
mount /dev/$device /
upload "$src" "$dest"
quit
EOF
}
__hd_download() {
    require_vars VM_DISK0_FILE
    local device="${1:-vda2}"
    local remote_path="$2"
    local local_path="${3:-./$(basename "$remote_path")}"
    
    if [ -z "$remote_path" ]; then
        echo "❌ Erro: Caminho remoto não fornecido."
        return 1
    fi

    echo "📥 Downloading [$remote_path] from: /dev/$device para [$local_path]..."
    
    guestfish -a "$VM_DISK0_FILE" <<EOF
run
mount "/dev/$device" /
download "$remote_path" "$local_path"
quit
EOF
}
__cd_cmd() {
    require_vars VM_ISO_PATH
    local iso_path="${VM_ISO_PATH}"
    local cmd="${1:-"ls /"}"

    echo "💿 Inspecionando ISO: [$iso_path]..."

    guestfish --ro -a "$iso_path" <<EOF
run
# ISOs geralmente são montados diretamente no dispositivo /dev/sda ou /dev/sdb
# O comando 'list-filesystems' ajuda a encontrar o ponto certo
mount /dev/sda /
$cmd
quit
EOF
}



require_functions etc_qemu__allow_virbr0



