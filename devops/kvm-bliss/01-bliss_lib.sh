
#!/bin/bash
# Filename: 00-kvm-bliss_lib.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source $(realpath ./00-bliss_env.sh)

show_vars \
    VM_NAME \
    VM_ISO_PATH \
    VM_HOST_MOUNT_LOCATION \
    VM_OS_VARIANT \
    VM_DISK0_FILE \
    VM_HD_SIZE \
    VM_GRAPH_MODE
require_vars \
    VM_NAME \
    VM_ISO_PATH \
    VM_HOST_MOUNT_LOCATION \
    VM_OS_VARIANT \
    VM_DISK0_FILE \
    VM_HD_SIZE \
    VM_GRAPH_MODE

require_locations \
    VM_HOST_MOUNT_LOCATION 

require_files \
    VM_DISK0_FILE \
    VM_ISO_PATH \
    VM_NVRAM_VARS_FILE \
    VM_NVRAM_CODE_FILE

require_binaries qemu-img virsh xmlstarlet pygmentize jq ip xargs grep
###
# network >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
# extra vars specific to the used image 
# Captura o MAC da interface de rede principal (a que tem rota padrão)
REAL_MAC=$(ip route get 8.8.8.8 | grep -Po 'dev \K\w+' | xargs ip link show | grep -Po 'link/ether \K[\da-f:]+')
echo "O MAC da minha placa real é: $REAL_MAC"
export VM_NETWORK_MAC=${REAL_MAC}

export ADB_SERVICE_PORT="${ADB_SERVICE_PORT,-"5555"}"
export ANDROID_CTL="/var/lib/libvirt/qemu/channel/android-control-$VM_NAME.sock"


### expect file vars
require_vars \
    VM_NETWORK_MAC \
    ADB_SERVICE_PORT
show_vars \
    VM_NETWORK_MAC \
    ADB_SERVICE_PORT


### >>>> VM functions
_vm_android_ip() {
    # 1. Check prioritário: O túnel QEMU User Net (127.0.0.1) está ativo?
    # Verificamos se o XML da VM contém a configuração de hostfwd
    if virsh dumpxml "$VM_NAME" | grep -q "hostfwd=tcp::5555-:5555"; then
        # Se a porta 5555 responder no localhost, usamos o loopback
        if nc -z 127.0.0.1 5555 2>/dev/null; then
            echo "127.0.0.1"
            export ANDROID_SERIAL=localhost:5555
            return 0
        fi
    fi

    # 2. Check secundário: Procura IP na bridge do Libvirt (Rede NAT)
    local discovered_ip
    discovered_ip=$(virsh domifaddr "$VM_NAME" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
    
    if [ -n "$discovered_ip" ]; then
        echo "$discovered_ip"
        export ANDROID_SERIAL="$discovered_ip:5555"
        return 0
    fi

    # 3. Check final: DHCP Leases (Fallback se o domifaddr falhar)
    discovered_ip=$(virsh net-dhcp-leases default | grep -i "$VM_NETWORK_MAC" | awk '{print $5}' | cut -d'/' -f1)
    
    if [ -n "$discovered_ip" ]; then
        echo "$discovered_ip"
        export ANDROID_SERIAL="$discovered_ip:5555"
        return 0
    fi

    # Se nada funcionar, retorna erro para o script saber que a VM está isolada
    return 1
}

_vm_is_running() {
    # Verifica o estado via virsh
    if virsh --connect qemu:///system domstate "$VM_NAME" 2>/dev/null | grep -q "running"; then
        return 0 # True
    else
        return 1 # False
    fi
}
_vm_is_android_control_ready() {
    # 1. Verifica se o ficheiro de socket existe
    require_vars || return 1
    
    # 2. Tenta uma conexão de teste silenciosa via sudo
    # O Android demora a "escutar" do outro lado, por isso o loop é essencial
    timeout 0.5 sudo -n socat - UNIX-CONNECT:"$ANDROID_CTL" </dev/null >/dev/null 2>&1
}

# Adiciona ou corrige esta função no topo do teu script
_vm_is_adb_ready() {
    local target=$(_vm_android_ip)
    local port=${ADB_SERVICE_PORT:-5555}

    # ESTADO 2: Inalcançável (Porta Fechada)
    if ! nc -z -w 1 "$target" "$port" > /dev/null 2>&1; then
        return 2
    fi

    # Tenta conectar (se já estiver ligado, o ADB ignora silenciosamente)
    adb connect "$target:$port" > /dev/null 2>&1

    # Captura o estado específico do dispositivo
    local adb_state=$(adb devices | grep "$target:$port" | awk '{print $2}')

    # ESTADO 1: Offline ou Unauthorized (Sistema a carregar ou à espera de RSA)
    if [[ "$adb_state" == "offline" || "$adb_state" == "unauthorized" || -z "$adb_state" ]]; then
        return 1
    fi

    # Se estiver "device", verificamos se o sistema de ficheiros está pronto
    local boot_completed=$(adb -s "$target:$port" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')

    if [[ "$boot_completed" == "1" ]]; then
        # ESTADO 0: Online e funcional
        return 0
    else
        # Ainda em boot (animação de entrada)
        return 1
    fi
}
_vm_wait4_adb_ready() {
    require_vars ADB_SERVICE_PORT
    local timeout=${1:-60}
    local count=0
    local status
    
    echo "⏳ A aguardar prontidão da rede (INET/ADB)..."

    while [ $count -lt $timeout ]; do
        # Chama a função e captura o código de saída (0, 1 ou 2)
        _vm_is_adb_ready
        status=$?

        if [ $status -eq 0 ]; then
            echo -e "\n✅ Android está 100% pronto (Desktop carregado)!"
            return 0            
        elif [ $status -eq 2 ]; then
            echo -n "🔌" # Porta fechada (Rede/Netdev ainda não subiu)
        elif [ $status -eq 1 ]; then
            echo -n "😴" # ADB ligado mas em 'offline' ou 'booting'
        fi

        sleep 2
        ((count+=2))
    done    
    echo -e "\n❌ Timeout: O Android não respondeu via rede em $timeout segundos."
    return 1
}

_vm_wait4_running() {
    local timeout_s=30
    local start=$(date +%s)

    while true; do
        if _vm_is_running; then
            echo "✅ VM is running"
            return 0
        fi

        if (( $(date +%s) - start > timeout_s )); then
            echo "❌ VM not running"
            return 1
        fi
        printf "."
        sleep 0.5
    done
}

_vm_wait4_android_control() {
    local timeout_s=60
    local start=$(date +%s)

    while true; do
        if _vm_is_android_control_ready; then
            echo "✅ Android control channel ready"
            return 0
        fi

        if (( $(date +%s) - start > timeout_s )); then
            echo "❌ Android control channel timeout"
            return 1
        fi
        printf "."
        sleep 0.5
    done
}
_vm_wait4_service_port_ready() {
    # Corrigida a sintaxe da expansão de variável: ${1:-60}
    local timeout_secs=${1:-60}
    local elapsed=0
    
    echo "⏳ Aguardando que o serviço ADB responda em 127.0.0.1:5555..."
 
    while ! nc -z 127.0.0.1 5555 >/dev/null 2>&1; do
        if [ "$elapsed" -ge "$timeout_secs" ]; then
            echo -e "\n❌ Timeout atingido ($timeout_secs s) sem resposta do ADB."
            return 1
        fi
        
        sleep 2
        echo -n "."
        ((elapsed+=2))
    done
    
    echo -e "\n✅ ADB Online e acessível!"
    return 0
}

_vm_log() {
    local raw_since="$1"
    local epoch_sec
    local fixed_since=$(echo "$raw_since" | tr ',' '.')
    echo "raw_since=$raw_since"
    # 1. Cálculo do Epoch com folga de 2 segundos para evitar race conditions
    if [ -z "$raw_since" ]; then
        # Fallback real: 30 segundos atrás em relação a AGORA
        epoch_exact=$(date --date='30 seconds ago' +%s.%3N)
        echo "⚠️  Aviso: Sem input. Usando fallback de 30s atrás."
    else
        # Uso exato do valor passado
        epoch_exact=$(date --date="$raw_since" +%s.%3N)
    fi


    # Extraímos apenas a parte inteira para o Journalctl (remove tudo após o ponto)
    local epoch_int=${epoch_exact%.*}

    echo -e "\n📂 [LOG EXATO: @$epoch_int]"
    echo "⏱️  Timestamp Original: $raw_since"
    echo "------------------------------------------------------------------"

    # --- Journalctl (Agora com Epoch Inteiro) ---
    # O @ só funciona de forma fiável com segundos inteiros no CLI
    journalctl --since "@$epoch_int" --no-pager -o short-precise

    # --- KERNEL (dmesg) ---
    echo -e "\n🛡️ [KERNEL DMESG]"
    echo "------------------------------------------------------------------"
    dmesg --since "$fixed_since" --time-format iso 2>/dev/null #| grep -iv "cups" | grep -iE "apparmor|nbd0|vfio|qemu|$VM_NAME" | tail -n 5

    # epoch_sec does not worksudo dmesg --since "@$epoch_sec" --time-format iso 2>/dev/null

    # --- QEMU GUEST LOG (Ficheiro Físico) ---
    local qemu_ts=$(echo "$raw_since" | tr ',' '.' | tr ' ' 'T' | cut -d'+' -f1)
    local log_file="/var/log/libvirt/qemu/${VM_NAME}.log"
    if [ -f "$log_file" ]; then
        echo -e "\n🖥️ QEMU Guest Log ($VM_NAME):"
        awk -v ts="$qemu_ts" '
            /^[0-9]{4}-[0-9]{2}-[0-9]{2}T/ {
                if ($1 >= ts) { found=1 } else { found=0 }
            }
            found { print $0 }
        ' "$log_file"
    fi
}
_vm_start() {
    virsh --connect qemu:///system start "$VM_NAME"
}

_vm_reboot() {
    virsh reset "$VM_NAME"
}

_vm_code_edit() {
    export EDITOR="code --wait"
    virsh --connect qemu:///system edit "$VM_NAME"
}

_vm_viewer() {
    virt-viewer --connect qemu:///system --attach -w "$VM_NAME" &
}
_vm_scrcpy2() {
    local target=$(_vm_android_ip)
    local port=${ADB_SERVICE_PORT:-5555}
    
    echo "📺 Lançando Scrcpy em $target:$port..."
    scrcpy -s "$target:$port" \
        --window-title "$VM_NAME" \
        --stay-awake \
        --power-off-on-close &
        
}
_vm_scrcpy() {
    local target=$(_vm_android_ip)
    local port=${ADB_SERVICE_PORT:-5555}
    
    echo "📺 Lançando Scrcpy (v1.25) via IP direto..."
    scrcpy -s "$target:$port" \
        --encoder 'OMX.google.h264.encoder' \
        --max-size 1024 \
        --window-title "$VM_NAME" \
        --always-on-top &
}

_vm_apparmor_fix() {
    # Remove o perfil do Libvirt que pode estar a bloquear a GPU
    #sudo apparmor_parser -R /etc/apparmor.d/usr.sbin.libvirtd 2>/dev/null
    #sudo apparmor_parser -R /etc/apparmor.d/libvirt/libvirt-* 2>/dev/null

    # 1. Remove o perfil problemático (já que não usas o Docker Desktop)
    sudo rm /etc/apparmor.d/docker-desktop
    # 2. Recarrega o AppArmor para limpar o erro da memória
    sudo systemctl restart apparmor
    # 3. Agora sim, coloca o libvirtd em modo permissivo sem erros
    sudo aa-complain /usr/sbin/libvirtd

    # Adicionar permissão ao ficheiro de abstração do qemu
    echo '  /dev/dri/renderD* rw,' | sudo tee -a /etc/apparmor.d/abstractions/libvirt-qemu

    # Reinicia o serviço de segurança
    #sudo systemctl restart apparmor

    # 3. Agora sim, coloca o libvirtd em modo permissivo sem erros
    sudo aa-complain /usr/sbin/libvirtd
    sudo aa-complain /usr/lib/libvirt/virt-aa-helper
}


_gl_fix_permissions_default() {
    echo "📺 Ajustando permissões para modo '$VM_GRAPH_MODE'..."
    require_vars USER VM_RENDER_DEVICE    
    # Permite que aplicações locais (como o QEMU) desenhem no teu X11
    xhost +si:localuser:$USER
    # Permite acesso ao X11 local
    xhost +si:localuser:libvirt-qemu

    # Dá permissão total ao teu user para o renderizador
    sudo chown $USER:render "$VM_RENDER_DEVICE"
    sudo chown $USER:render "$VM_CARD_DEVICE"
    sudo chmod 666 $VM_RENDER_DEVICE    
    sudo chmod 666 $VM_CARD_DEVICE    
                
    local channel_sock_folder=$(dirname $ANDROID_CTL)
    sudo rm -rf $channel_sock_folder
    sudo mkdir -p $channel_sock_folder
    sudo chown -R libvirt-qemu:libvirt-qemu $channel_sock_folder
    sudo chmod 777 $channel_sock_folder        
    #sudo ls -la $channel_sock_folder         

    # 3. Se quiseres criar o ficheiro manualmente para garantir:
    local log_file="/var/log/libvirt/qemu/${VM_NAME}.log"
    sudo touch $log_file
    sudo chown libvirt-qemu:kvm $log_file
    sudo chmod 644 $log_file    

    # permitir sudo socat com privilégios de root sem te pedir a senha e sem quebrar o loop:
    echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/socat" | sudo tee /etc/sudoers.d/socat-kvm
    
}

_gl_fix_permissions_nvidia() {
    echo "🎮 Forçando Ownership da GPU para $USER..."

    # Lista de dispositivos críticos detetados no teu log
    local nodes=(
        "/dev/nvidia0"
        "/dev/nvidiactl"
        "/dev/nvidia-modeset"
        "/dev/nvidia-uvm"
        "/dev/nvidia-uvm-tools"
        "/dev/dri/renderD128"
        "/dev/dri/card1"
    )

    for node in "${nodes[@]}"; do
        if [ -e "$node" ]; then
            sudo chown vitor:render "$node"
            sudo chmod 666 "$node"
        fi
    done
    
    echo "✅ Hardware mapeado para vitor:render"
}

_vm_clean_shutdown() {
    require_vars VM_NAME
    local vm_name="${1:-$VM_NAME}"
    local timeout=30

    echo "⏳ A solicitar encerramento seguro de: $vm_name..."
    virsh --connect qemu:///system shutdown
    # Envia sinal de desligamento via ACPI
    if virsh domstate "$vm_name" | grep -q "running"; then
        virsh shutdown "$vm_name"

        # Aguarda até que a VM se desligue ou atinja o timeout
        local count=0
        while [ $count -lt $timeout ]; do
            local state=$(virsh domstate "$vm_name")
            echo $state
            if ! echo "$state" | grep -q "running"; then
                echo "✅ VM desligada com sucesso."
                return 0
            fi
            sleep 1
            ((count++))
            echo -n "."
        done

        # Se não desligou no tempo previsto, força o encerramento
        echo -e "\n⚠️ Timeout atingido. A forçar encerramento ..."
        _vm_initialize
    else
        echo "ℹ️ A VM já se encontra desligada ou não existe."
    fi
}


_vm_initialize() {
    echo "♻️ Limpando instâncias de $VM_NAME..."
    # 1. Primeiro força a paragem da VM se estiver a correr
    virsh --connect qemu:///system destroy "$VM_NAME" 2>/dev/null || true
    # 2. Agora que o processo morreu, apaga a definição e o ficheiro VARS.fd
    # --nvram remove o ficheiro de variáveis EFI (onde o BIOS guarda o boot order e o estado)
    virsh --connect qemu:///system undefine "$VM_NAME" --nvram --managed-save --snapshots-metadata 2>/dev/null
    echo "🧹 Instância limpa e NVRAM eliminada."
}

_vm_prep_nvram_storage() {
    #require_locations VM_NVRAM_DIR 
    #require_vars VM_NVRAM_VARS_FILE VM_NVRAM_CODE_FILE USER
    
    # 1. Criar pasta se não existir
    local nvm_dir=$(dirname "$VM_NVRAM_VARS_FILE")    
    if [ ! -d "$VM_NVRAM_DIR" ]; then
        echo "🛠️ Criando diretório NVRAM em $VM_NVRAM_DIR..."
        sudo mkdir -p "$VM_NVRAM_DIR"        
    fi
    
    
    # 2. Templates originais
    local template_vars="/usr/share/OVMF/OVMF_VARS_4M.fd"
    local template_code="/usr/share/OVMF/OVMF_CODE_4M.fd"

    require_files template_vars template_code && {
        sudo cp "$template_vars" "$VM_NVRAM_DIR/VARS.fd"    
        sudo cp "$template_vars" "$VM_NVRAM_VARS_FILE"  
        sudo cp "$template_code" "$VM_NVRAM_CODE_FILE"

        sudo chmod -R 777 "$VM_NVRAM_DIR"         
    }
    # 3. Cópia e Permissões (O Libvirt precisa de escrever no VARS para salvar o boot)
            
    sudo chmod -R 775 "$VM_NVRAM_DIR"  
    sudo chown -R libvirt-qemu:kvm "$VM_NVRAM_DIR"
    

    # 4. Validação final
    #require_files VM_NVRAM_VARS_FILE VM_NVRAM_CODE_FILE && \
        echo "✅ NVRAM VARS CODE Prepared."
}

_hd_check_uefi_integrity() {
    require_vars VM_DISK0_FILE VM_HD_SIZE
    local disk_path="$VM_DISK0_FILE"
    echo "🔍 Verifing verificar estrutura interna: $disk_path"

    # 1. Verificar se o ficheiro é legível
    if [[ ! -r "$disk_path" ]]; then
        echo "❌ Erro: Sem permissão de leitura no ficheiro .qcow2"
        return 1
    fi

    # 2. Usar guestfish em modo RO (Read-Only) para listar partições
    # Adicionamos o export para forçar o guestfish a não usar KVM se falhar
    local parts
    parts=$(LIBGUESTFS_BACKEND=direct guestfish --ro -a "$disk_path" run : list-partitions 2>/dev/null)


    if echo "$parts" | grep -q "sda1" && echo "$parts" | grep -q "sda2"; then
        echo "✅ Partições sda1 (EFI) e sda2 (Data) detetadas."
        return 0
    else
        echo "❌ Estrutura não detetada via libguestfs. A tentar fallback rápido..."
        # Fallback usando qemu-img (menos detalhado, mas confirma se há dados)
        if qemu-img info "$disk_path" | grep -q "virtual size: $VM_HD_SIZE"; then
            echo "⚠️  Aviso: Disco existe e tem tamanho correto, mas partições estão ilegíveis para o Host."
            return 0
        fi
        return 1
    fi
}

_user_confirm_nuke() {
    echo -e "\n🔥 \033[1;31mPERIGO:\033[0m Estás prestes a fazer um NUKE no sistema (Clean Install)."
    echo "Isso apagará todas as partições e dados em $VM_DISK0_FILE."
    read -p "Tem a certeza que deseja continuar? (s/N): " confirm
    case "$confirm" in
        [sS][iI]|[sS]) return 0 ;;
        *) echo "❌ Abortado pelo utilizador."; exit 1 ;;
    esac
}
_vm_ensure_ready() {    
    _vm_is_running && _vm_initialize
    echo "Checking requirements..."
    if ! require_files "VM_DISK0_FILE" || ! _hd_check_uefi_integrity; then
        echo "⚠️ Disco base não encontrado ou inválido."
        echo "🚀 Iniciando reconstrução total (Clean Install)..."
        echo "Initializing vm disk at: $VM_DISK0_FILE"
        _vm_nuke_disk || exit 1
        # Instalação dos ficheiros do sistema
        bliss_blueprint "true" "default"
        # 3. Confirmação obrigatória antes de destruir/recriar
        
    else
        # boot hd direto para evitar o Shell
        _vm_clean_kernel_boot_vga_safe
        _vm_bridge_efi_to_vda2
        #_vm_patch_android_defaults
        #_vm_patch_vnc_qemu_device
        #_vm_inject_meogo        
        bliss_blueprint "false" 
    fi
    
    ! _vm_is_running && _vm_start
    _vm_wait4_running && \
    {
        _vm_viewer
        _ado_wait_and_unlock 
        _ado_install_meogo_if_missing
        _vm_scrcpy
    } &
}

_vm_create_disk_skeleton() {    
    local disk_path=${1,-"$VM_DISK0_FILE"}
    local disk_size=${2,-"$VM_HD_SIZE"}
    local label="${3:-BlissOS}"

    echo "🏗️ Criando disco virtual [$disk_path] de tamanho [$disk_size]"

    # Criar o arquivo físico primeiro (se não existir)
    if [ ! -f "$disk_path" ]; then
        qemu-img create -f qcow2 "$disk_path" "$disk_size"
    fi    

    echo "🏗️ Criando partições a:EFI, b:ext4 em $disk_path..."

    guestfish -a "$disk_path" <<_EOF_
run
# 1. Tabela de partições GPT
part-init /dev/sda gpt

# 2. Criar partições
# sda1: EFI (512MB)
part-add /dev/sda primary 2048 1050623
# sda2: Data (Resto)
part-add /dev/sda primary 1052672 -2048

# 3. FIX CRÍTICO: Definir sda1 como EFI System Partition (ESP)
# O GUID C12A... é o padrão mundial para partições de boot UEFI
part-set-gpt-type /dev/sda 1 C12A7328-F81F-11D2-BA4B-00A0C93EC93B
part-set-bootable /dev/sda 1 true

# 2. Definir sda2 como Linux Filesystem (O tipo correto para ext4)
part-set-gpt-type /dev/sda 2 0FC63DAF-8483-4772-8E79-3D69D8477DE4

# 4. Formatação
mkfs-opts vfat /dev/sda1 label:EFI
mkfs ext4 /dev/sda2
set-label /dev/sda2 "$label"

sync
_EOF_
}

# 0
_vm_nuke_disk() {
    # give form to disk...
    require_vars VM_DISK0_FILE VM_NAME VM_NVRAM_VARS_FILE
    require_files "VM_DISK0_FILE" 

    if _user_confirm_nuke; then
            echo "🚀 Iniciando reconstrução total (Clean Install)..."
            echo "Initializing vm disk at: $VM_DISK0_FILE"                  
    else
        echo "🛑 Operação cancelada. Não existem discos válidos para arrancar."
        exit 1
    fi

    if _vm_is_running; then
        echo "⚠️  VM ligada! A desligar forçadamente..."
        _vm_initialize
    fi    
    echo "🧹 Limpando ficheiros antigos..."

    rm -f "$VM_DISK0_FILE"
    rm -f "$VM_NVRAM_VARS_FILE"
    
    _vm_create_disk_skeleton "$VM_DISK0_FILE" "$VM_HD_SIZE" "BlissOS"
    # 2. Prepara a NVRAM
    _vm_prep_nvram_storage  
    
    # 3. Valida se o esqueleto está lá
    _hd_check_uefi_integrity || return 1
    

    sudo chown $USER:$USER "$VM_DISK0_FILE"
    chmod 664 "$VM_DISK0_FILE"
    echo "✅ DISCO PRONTO PARA RECEBER INSTALAÇÃO."
    echo "run bliss_boot_cd"

    #_vm_log
      
}

## >>>>>>>>>>>>>>>>>>>>>>> AFTER BLISS INSTALED ON sda 1:EFI,2:ANDROID
# >>>>>>>>>>>>>>>
# >>>>>>>>
# >>>>>
_vm_clean_kernel_boot_vga_safe() {
    echo "🛡️ Configurando Boot Seguro (VGA Standard) em vda2..."
    local local_tmp="/tmp/android_vga.cfg"
    cat <<EOF > "$local_tmp"
set timeout=0
menuentry 'BlissOS 9.0 (Standard VGA)' {
    search --no-floppy --set=root -f /android-2024-10-12/kernel
    # vga=788 is 800x600@16, very stable for VESA
    # xforcevesa is an alternative to EXTMOD=vesa
    # Update the linux line in your script to this:
    # Adicione este parâmetro na linha linux do seu android.cfg: DATA=/data ou DATA=/android-2024-10-12/data
    linux /android-2024-10-12/kernel root=/dev/ram0 rw SRC=/android-2024-10-12 DATA=/data nomodeset xforcevesa HWACCEL=0 androidboot.selinux=permissive video=1024x768 androidboot.gui=ext    
    initrd /android-2024-10-12/initrd.img
}
EOF
    __hd_upload "vda2" "$local_tmp" "/boot/grub/android.cfg"
    __hd_cmd "vda2" "cat /boot/grub/android.cfg"
    
}

_vm_bridge_efi_to_vda2() {
    echo "🔗 Bridging EFI (vda1) to Config (vda2)..."
    
    local bridge_tmp="/tmp/bridge.cfg"
    cat <<EOF > "$bridge_tmp"
search --no-floppy --set=root -f /android-2024-10-12/kernel
configfile /boot/grub/android.cfg
EOF

    __hd_cmd "vda1" "mkdir-p /EFI/BOOT"
    __hd_cmd "vda1" "cp /EFI/BlissOS/grubx64.efi /EFI/BOOT/BOOTX64.EFI"
    __hd_upload "vda1" "$bridge_tmp" "/EFI/BOOT/grub.cfg"
    __hd_cmd "vda1" "cat /EFI/BOOT/grub.cfg"
    __hd_cmd "vda2" "cat /boot/grub/android.cfg"
}

################### >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<
_vm_spoof_device() {
    echo "🎭 Mascarando a VM como um dispositivo real..."
    
    # 1. Pescar a pasta que contém o kernel (indicação de que é a pasta do SO)
    local install_dir=$(guestfish -a "$VM_DISK0_FILE" -m /dev/sda2 find / | grep "/kernel" | cut -d/ -f2 | head -n 1)
    
    if [ -z "$install_dir" ]; then
        echo "❌ Erro: Pasta da instalação não encontrada."
        return 1
    fi

    echo "📂 Pasta detetada: /$install_dir"

    # 2. Como o system.img é comprimido/read-only no Bliss, a forma mais fácil 
    # de fazer spoofing é via CMDLINE no GRUB (adicionando propriedades de boot)
    # ou injetando um script init.sh
    
    guestfish -a "$VM_DISK0_FILE" -m /dev/sda2 <<_EOF_
# Criar um script de inicialização que o Android executa para mudar o modelo
mkdir-p /$install_dir/data
write /$install_dir/data/script_spoof.sh "setprop ro.product.model SM-X900\nsetprop ro.product.manufacturer samsung"
chmod 0755 /$install_dir/data/script_spoof.sh
sync
_EOF_
}

_vm_extract_meogo() {
    echo "📤 A localizar APK do MEO GO..."
    local local_apk="$SCRIPT_DIR/meogo.apk"
    require_files "local_apk" && \
        echo "App file already exists, skiping..." && return 0

    # Procura o ficheiro (o find devolve algo como 'android-2024...')
    local remote_apk=$(guestfish -a "$VM_DISK0_FILE" -m /dev/vda2 find / | \
        grep "pt.ptinovacao.rma.meomobile" | grep "base.apk" | head -n 1)

    if [ -z "$remote_apk" ]; then
        echo "❌ Erro: APK não encontrado."
        return 1
    fi

    # O SEGREDO: Adicionar a / antes de "$remote_apk"
    echo "📂 Ficheiro encontrado: /$remote_apk"
    
    guestfish -a "$VM_DISK0_FILE" -m /dev/vda2 download "/$remote_apk" "$local_apk"
    
    if [ -f "$local_apk" ]; then
        echo "✅ Sucesso! O APK está em $local_apk"
        return 0
    else
        echo "❌ Falha no download do ficheiro."
        return 1
    fi
}

_vm_inject_meogo() {
    echo "📥 Preparando injeção do MEO GO..."
    require_vars VM_DISK0_FILE
    local PRT="vda2"
    local local_apk="$SCRIPT_DIR/meogo.apk"
    local DATA_DIR="/android-2024-10-12/data"
    local app_dest="$DATA_DIR/app/MEO_GO"

    if [ ! -f "$local_apk" ]; then
        echo "❌ Erro: meogo.apk não encontrado em $SCRIPT_DIR"
        return 1
    fi

    echo "📁 Criando diretório da App..."
    __hd_cmd "$PRT" "mkdir -p $app_dest"

    echo "🚀 Fazendo upload do APK..."
    __hd_upload "$PRT" "$local_apk" "$app_dest/base.apk"

    # Permissões essenciais para o Android conseguir ler e instalar
    echo "🔐 Ajustando permissões..."
    __hd_cmd "$PRT" "chmod 0755 $app_dest"
    __hd_cmd "$PRT" "chmod 0644 $app_dest/base.apk"
    
    echo "✅ MEO GO injetado. O Android irá processar a instalação no boot."
}
_ado_install_meogo_if_missing() {
    local PKG_NAME="pt.telecom.meogo"
    local APK_PATH="$SCRIPT_DIR/meogo.apk"

    echo "🔍 Verificando se o MEO GO já existe..."
    
    # O grep -q não imprime nada, apenas retorna sucesso (0) se encontrar
    if adb shell pm list packages | grep -q "$PKG_NAME"; then
        echo "✅ MEO GO já está instalado. Saltando instalação."
    else
        echo "📥 MEO GO não encontrado. Instalando..."
        if [ -f "$APK_PATH" ]; then
            # -r serve para reinstalar/manter dados se necessário
            # -g garante todas as permissões (Runtime Permissions) automaticamente
            adb install -r -g "$APK_PATH"
            echo "🎯 Instalação concluída."
        else
            echo "❌ Erro: Ficheiro $APK_PATH não encontrado para instalar."
        fi
    fi
}

#################### AQUI BOOT DISK FROM new INSTALL
########
####
##
#

_vm_launch() {
    require_files \
        VM_DISK0_FILE || return 1

    require_files VM_NVRAM_VARS_FILE \
        VM_NVRAM_CODE_FILE
   
    show_vars VM_RAM_MB VM_CPU_CORES VM_GRAPH_MODE
      
    _vm_initialize
    #etc_qemu__allow_virbr0
    # Definição de vídeo
    local graph_video_args
    if [ "$VM_GRAPH_MODE" = "nvidia" ]; then       
        graph_video_args="--video virtio --graphics spice,listen=none"          
        graph_video_args="--video virtio,accel3d=yes --graphics spice,listen=none,gl=on,rendernode=$VM_RENDER_DEVICE"        
    else    
        graph_video_args="--video virtio --graphics spice,listen=none"  
    fi

    echo "🚀 A lançar instalação do Bliss OS: $VM_NAME..."
    export VIRTINSTALL_OSINFO_DISABLE_REQUIRE=1

    # IMPORTANTE: Nota as barras invertidas \ no final de CADA linha
    if [ "$VM_GRAPH_MODE" = "nvidia" ]; then _gl_fix_permissions_nvidia; else _gl_fix_permissions_default; fi
    virt-install \
        --connect qemu:///system \
        --name "$VM_NAME" \
        --ram "$VM_RAM_MB" \
        --vcpus "$VM_CPU_CORES" \
        --boot uefi \
        --machine q35 \
        $graph_video_args \
        --os-variant "$VM_OS_VARIANT" \
        --disk path="$VM_DISK0_FILE",format=qcow2,bus=virtio \
        --cdrom "$VM_ISO_PATH" \
        --network bridge=virbr0,model=virtio \
        --channel spicevmc \
        --cpu host-passthrough \
        --check all=off \
        --noautoconsole

    # Pós-lançamento
    
    
    echo "📺 A abrir consola..."
    virt-viewer --connect qemu:///system --attach -w "$VM_NAME" &

    sleep 4
    _vm_log    
}

_vm_patch_vnc_qemu_device() {
       echo "🚀 Aplicando ENABLE developer usb debug & UNLOCK (Idempotent)..."
    require_vars VM_DISK0_FILE ADB_SERVICE_PORT

    local PRT=vda2
    local adb_key_pub="${HOME}/.android/adbkey.pub"
    local edit_prop_file="/tmp/local.prop.tmp"

    local DATA_DIR="/android-2024-10-12/data"
    local SYS_DIR="$DATA_DIR/system"

    # 1. Garantir que a chave existe no Host
    if [ ! -f "$adb_key_pub" ]; then
        echo "⚠️  ADB Key não encontrada. Gerando..."
        adb keygen "${HOME}/.android/adbkey" > /dev/null
    fi

    # 2. UPLOAD DA CHAVE
    echo "🔑 Injetando chave RSA..."
    __hd_upload $PRT "$adb_key_pub" $DATA_DIR/misc/adb/adb_keys
    __hd_cmd $PRT "chmod 0644 $DATA_DIR/misc/adb/adb_keys"

    # 3. CRIAR LOCAL.PROP (ADB + UNLOCK FLAGS)
    # Adicionei as flags de lockscreen e setupwizard aqui
    cat <<EOF > "$edit_prop_file"
ro.product.model=SM-X900
ro.product.manufacturer=samsung
persist.service.adb.enable=1
persist.service.debuggable=1
persist.sys.usb.config=adb
service.adb.tcp.port=$ADB_SERVICE_PORT
ro.lockscreen.disable.default=true
ro.setupwizard.mode=DISABLED
# --- FORÇAR LOCKSCREEN = NONE ---
ro.lockscreen.disable.default=true
config.disable_lockscreen=true
persist.wm.debug.unlocked=1
# Impede que o setup wizard resgate o lockscreen
ro.setupwizard.mode=DISABLED
# ---- Forçar renderização por CPU para estabilizar o MediaCodec
debug.stagefright.ccodec=0
debug.stagefright.omx_default_rank=0
# Desativar HW overlays que costumam crashar o scrcpy em VMs
debug.cpurend.enabled=1
# ------ # Mascarar a VM para evitar bloqueios da App
ro.build.selinux=1
ro.debuggable=0
persist.sys.strictmode.visual=0
persist.sys.strictmode.disable=1

# Forçar o player a não usar aceleração de hardware problemática
media.stagefright.thumbnail.prefer_hw_codecs=0
debug.stagefright.ccodec=0

# Enganar a deteção de Emulador/VM
ro.kernel.qemu=0
ro.kernel.android.checkjni=0
ro.hardware.audio.primary=goldfish
# Esconder que é KVM
ro.boot.hardware=android_x86_64
ro.hardware=android_x86_64
# Forçar estado de "Bootloader Locked"
ro.boot.flash.locked=1
ro.boot.verifiedbootstate=green

####
# Forçar o ExoPlayer a ignorar extensões de áudio problemáticas
media.stagefright.audio.sink=0
# Tentar desativar a verificação de "Secure Output" que causa o UnsupportedSetting
persist.sys.media.avsync=false
# Mascarar o erro de Thermal (evita ruído no log e throttling falso)
persist.sys.thermal.mode=disabled

## >>>>>>>>
# Impede que a App MEO GO bloqueie o screenshot/streaming do scrcpy
ro.config.low_ram=false
persist.sys.force_sw_gles=1
# Forçar o Android a ignorar a proteção de ecrã (DRM L3)
persist.google.widevine_level=3
EOF
    
    echo "📝 Configurando local.prop..."
    __hd_upload $PRT "$edit_prop_file" $DATA_DIR/local.prop
    __hd_cmd $PRT "chmod 0644 $DATA_DIR/local.prop"

    # 4. FORCE UNLOCK (Remover DB e Marcar como Provisionado)
    echo "🔓 Removendo travas de ecrã e setup..."    
    __hd_cmd $PRT "rm $SYS_DIR/locksettings.db"
    __hd_cmd $PRT "rm $SYS_DIR/locksettings.db-wal"
    __hd_cmd $PRT "rm $SYS_DIR/locksettings.db-shm"
    
    # Marcar como 'Provisioned' (Configurado) no sistema
    echo "1" > /tmp/p_val
    __hd_upload $PRT "/tmp/p_val" "$SYS_DIR/device_provisioned"
    __hd_cmd $PRT "chmod 644 $SYS_DIR/device_provisioned"
    
    # Garantir pasta do user 0 e marcar como completo
    #__hd_cmd $PRT "mkdir $SYS_DIR/users"
    #__hd_cmd $PRT "mkdir $SYS_DIR/users/0"
    __hd_upload $PRT "/tmp/val_one" "$SYS_DIR/users/0/user_setup_complete"
    
    # 5. Redundância em /property
    echo "1" > /tmp/adb_en
    __hd_upload $PRT "/tmp/adb_en" "$DATA_DIR/property/persist.service.adb.enable"    
    __hd_cmd $PRT "chmod 644  $DATA_DIR/property/persist.service.adb.enable"

    echo "$ADB_SERVICE_PORT" > /tmp/adb_service_port
    __hd_upload $PRT "/tmp/adb_service_port" "$DATA_DIR//property/persist.adb.tcp.port"    
    # replaced__hd_cmd $PRT "write $DATA_DIR/property/persist.adb.tcp.port $ADB_SERVICE_PORT"
    __hd_cmd $PRT "chmod 644 $DATA_DIR/property/persist.adb.tcp.port"

    _vm_hide_kernelsu

    rm -f "$edit_prop_file" "/tmp/val_one"
    echo "🎯 Patch de ADB e UNLOCK aplicado com sucesso."
}

_vm_patch_android_defaults() {    
    echo "🚀 Aplicando ENABLE developer usb debug & UNLOCK (Idempotent)..."
    require_vars VM_DISK0_FILE ADB_SERVICE_PORT

    local PRT=vda2
    local adb_key_pub="${HOME}/.android/adbkey.pub"
    local edit_prop_file="/tmp/local.prop.tmp"

    local DATA_DIR="/android-2024-10-12/data"
    local SYS_DIR="$DATA_DIR/system"

    # 1. Garantir que a chave existe no Host
    if [ ! -f "$adb_key_pub" ]; then
        echo "⚠️  ADB Key não encontrada. Gerando..."
        adb keygen "${HOME}/.android/adbkey" > /dev/null
    fi

    # 2. UPLOAD DA CHAVE
    echo "🔑 Injetando chave RSA..."
    __hd_upload $PRT "$adb_key_pub" $DATA_DIR/misc/adb/adb_keys
    __hd_cmd $PRT "chmod 0644 $DATA_DIR/misc/adb/adb_keys"

    # 3. CRIAR LOCAL.PROP (ADB + UNLOCK FLAGS)
    # Adicionei as flags de lockscreen e setupwizard aqui
    cat <<EOF > "$edit_prop_file"
ro.product.model=SM-X900
ro.product.manufacturer=samsung
persist.service.adb.enable=1
persist.service.debuggable=1
persist.sys.usb.config=adb
service.adb.tcp.port=$ADB_SERVICE_PORT


# --- FORÇAR LOCKSCREEN = NONE ---
ro.lockscreen.disable.default=true
config.disable_lockscreen=true
persist.wm.debug.unlocked=1
# Impede que o setup wizard resgate o lockscreen
ro.setupwizard.mode=DISABLED
# Forçar estado de "Bootloader Locked"
ro.boot.flash.locked=1
ro.boot.verifiedbootstate=green


#debug.stagefright.ccodec=0
#debug.stagefright.omx_default_rank=0
# Isso força o Android a usar implementações de software puras

# Forçar o ExoPlayer a ignorar extensões de áudio problemáticas
#media.stagefright.audio.sink=0

# Tentar desativar a verificação de "Secure Output" que causa o UnsupportedSetting
#persist.sys.media.avsync=false

# Mascarar o erro de Thermal (evita ruído no log e throttling falso)
#persist.sys.thermal.mode=disabled
EOF
    
    echo "📝 Configurando local.prop..."
    __hd_upload $PRT "$edit_prop_file" $DATA_DIR/local.prop
    __hd_cmd $PRT "chmod 0644 $DATA_DIR/local.prop"

    # 4. FORCE UNLOCK (Remover DB e Marcar como Provisionado)
    echo "🔓 Removendo travas de ecrã e setup..."    
    __hd_cmd $PRT "rm $SYS_DIR/locksettings.db"
    __hd_cmd $PRT "rm $SYS_DIR/locksettings.db-wal"
    __hd_cmd $PRT "rm $SYS_DIR/locksettings.db-shm"
    
    # Marcar como 'Provisioned' (Configurado) no sistema
    echo "1" > /tmp/val_one
    __hd_upload $PRT "/tmp/val_one" "$SYS_DIR/device_provisioned"
    __hd_cmd $PRT "chmod 644 $SYS_DIR/device_provisioned"
    
    __hd_upload $PRT "/tmp/val_one" "$SYS_DIR/users/0/user_setup_complete"
    
    # 5. Redundância em /property
    __hd_cmd $PRT "write $DATA_DIR/property/persist.service.adb.enable 1"
    __hd_cmd $PRT "chmod 644  $DATA_DIR/property/persist.service.adb.enable"
    __hd_cmd $PRT "write $DATA_DIR/property/persist.adb.tcp.port $ADB_SERVICE_PORT"
    __hd_cmd $PRT "chmod 644 $DATA_DIR/property/persist.adb.tcp.port"    

    rm -f "$edit_prop_file" "/tmp/val_one"
    echo "🎯 Patch de ADB e UNLOCK aplicado com sucesso."

    __hd_cmd $PRT  "ls $DATA_DIR/property" | grep persist
    __hd_cmd $PRT  "cat $DATA_DIR/local.prop"
    __hd_cmd $PRT  "ls $SYS_DIR" | grep lock
}

_vm_hide_kernelsu() {
    echo "🛡️ Camuflando KernelSU (Fixing paths)..."
    local PRT="vda2"
    # O caminho deve começar com / para o guestfish não reclamar
    local ROOT="/android-2024-10-12/data"

    local ksu_folders=(
        "$ROOT/data/me.weishu.kernelsu"
        "$ROOT/user_de/0/me.weishu.kernelsu"
        "$ROOT/misc/profiles/cur/0/me.weishu.kernelsu"
        "$ROOT/misc/profiles/ref/me.weishu.kernelsu"
    )

    for folder in "${ksu_folders[@]}"; do
        echo "📍 Escondendo: $folder"
        # O sinal '-' no início do comando pode ser usado se o __hd_cmd permitir, 
        # para ignorar erros caso a pasta não exista.
        __hd_cmd "$PRT" "mv $folder ${folder}_bak"
    done
    
    echo "✅ KernelSU camuflado."
}

_vm_show_kernelsu() {
    echo "🛡️ Expondo KernelSU para destravar o Boot..."
    local PRT="vda2"  # Atenção: No teu XML é vda, não sda
    local ROOT="/android-2024-10-12/data"

    local ksu_folders=(
        "data/me.weishu.kernelsu"
        "user_de/0/me.weishu.kernelsu"
        "misc/profiles/cur/0/me.weishu.kernelsu"
        "misc/profiles/ref/me.weishu.kernelsu"
    )

    for folder in "${ksu_folders[@]}"; do
        local bak_path="${ROOT}/${folder}_bak"
        local orig_path="${ROOT}/${folder}"
        
        echo "📍 Restaurando: $bak_path -> $orig_path"
        # Comando para mover de volta retirando o _bak
        __hd_cmd "$PRT" "mv $bak_path $orig_path"
    done
    
    echo "✅ KernelSU restaurado. O boot deve prosseguir agora."
}
_ado_wait_and_unlock() {
    local SERIAL="localhost:5555"
    local MAX_RETRIES=15
    local COUNT=0

    echo "⏳ Tentando conectar ao ADB em $SERIAL..."
    
    until adb connect $SERIAL | grep -q "connected" || [ $COUNT -eq $MAX_RETRIES ]; do
        sleep 2
        ((COUNT++))
        echo "   (Tentativa $COUNT/$MAX_RETRIES...)"
    done

    if [ $COUNT -eq $MAX_RETRIES ]; then
        echo "❌ ERRO: Não foi possível conectar ao Android via rede."
        return 1
    fi

    adb -s $SERIAL wait-for-device
    echo "⚡ Android detectado! Forçando inicialização da interface..."
    
    # Comando 'magic' para BlissOS em VMs: força o modo desktop
    adb -s $SERIAL shell settings put global stay_on_while_plugged_in 7
    adb -s $SERIAL shell input keyevent KEYCODE_WAKEUP
    adb -s $SERIAL shell wm dismiss-keyguard
    
    # Abre as configurações para garantir que o buffer de vídeo atualize
    adb -s $SERIAL shell settings put global hdmi_control_enabled 0
    #adb -s $SERIAL shell am start -a android.intent.action.MAIN -n com.android.settings/.Settings

    # 3. Força o brilho no máximo (ajuda na captura do encoder virtual)
    adb -s $SERIAL shell settings put system screen_brightness 255

    # 4. Acelera a renderização forçando a GPU (se disponível no BlissOS)
    adb -s $SERIAL shell setprop debug.hwui.renderer opengl
    echo "✅ Pronto!"

    if adb -s localhost:5555 shell getprop sys.boot_completed | grep -q "1"; then
        echo "🚀 Otimizando interface Android..."
        adb -s localhost:5555 shell wm density 160  # Ajusta DPI para ficar legível
        adb -s localhost:5555 shell svc power stayon true
        
        # Lança o scrcpy em background sem travar o terminal
        nohup scrcpy -s localhost:5555 --window-title "BlissOS Dev" -m 1024 -b 2M > /dev/null 2>&1 &
        echo "🖥️ Scrcpy iniciado!"
    fi
}
convert_mb_to_kib() {
    # 1. Pega no valor, remove 'mb', 'MB' ou espaços
    local raw_mb=$(echo "$1" | sed 's/[a-zA-Z ]//g')
    
    # 2. Multiplica por 1024 (1 MB = 1024 KiB)
    # Usamos o (( )) do bash para aritmética simples
    local kib=$(( raw_mb * 1024 ))
    
    echo "$kib"
}
export -f convert_mb_to_kib
bliss_blueprint() {
   
    # --- 3. Segmentos XML (Declarar ANTES de preencher) ---
    local channel_spice_xml=""
    local graphics_xml=""
    local video_xml=""
    local cpu_xml=""
    local sound_xml=""    
    local hd_xml=""
    local cdrom_xml=""    
    local qemu_xml=""
    local controller_xml=""    
    local os_xml=""
    local features_xml=""
 
    
    local network_xml=""
    # 1. Função que define as variáveis para o XML
    # 1. Sub-função para a Ordem de Boot
    local install_mode=${1:-"false"}
    _set_boot_order() {        
        require_files VM_DISK0_FILE VM_ISO_PATH        
        echo "💿 Configurando Ordem de Boot (Modo Instalação: $install_mode)..."

        local hd_boot_order=""        
        if [ "$install_mode" = "true" ]; then    
            cdrom_xml="<disk type='file' device='disk'>
            <driver name='qemu' type='raw'/>
                <source file='$VM_ISO_PATH'/>
                <target dev='vdb' bus='virtio'/>        
                <readonly/>
                <boot order='1'/>
            </disk>"    
            hd_boot_order="2"
        else
            hd_boot_order="1"               
        fi

        hd_xml="<disk type='file' device='disk'>
            <driver name='qemu' type='qcow2' cache='writeback' discard='unmap'/>
            <source file='$VM_DISK0_FILE'/>
            <target dev='vda' bus='virtio'/> 
            <boot order='$hd_boot_order'/>
        </disk>"
  
        
        # sata may promote priority boot issues. trying to use virtio with cdrom boot order
    }    
    _set_sound_spice_mode() {        
        echo "🔊 Configurando Hardware de Áudio (ICH9 + Spice)..."        
        sound_xml="<sound model='ich9'>
            <address type='pci' domain='0x0000' bus='0x00' slot='0x1b' function='0x0'/>
        </sound>

        <audio id='1' type='spice'/>"  
               
    } 
    _set_sound_pulse_mode() {        
        echo "🔊 Configurando Hardware de Áudio (ICH9)..."
        
        sound_xml="<sound model='ich9'>
            <address type='pci' domain='0x0000' bus='0x00' slot='0x1b' function='0x0'/>
        </sound>
        <audio id='1' type='pulseaudio' serverName='/run/user/1000/pulse/native'/>"        
               
    }    
    _set_os_mode() {
        require_vars VM_NVRAM_CODE_FILE VM_NVRAM_VARS_FILE
        echo "🏗️  Configurando Firmware UEFI (OVMF 4MB)..."

        # Definição dos templates padrão do sistema
        local template_vars="$VM_NVRAM_DIR/VARS.fd"        
        show_vars VM_NVRAM_CODE_FILE VM_NVRAM_VARS_FILE template_vars
        
        require_files VM_NVRAM_CODE_FILE VM_NVRAM_VARS_FILE || \     
            _vm_prep_nvram_storage 
    
        # 2. Valida se a preparação correu bem
        require_vars VM_NVRAM_CODE_FILE VM_NVRAM_VARS_FILE    
        # 3. Monta o XML com os caminhos dinâmicos gerados pela _vm_prep_nvram_storage
        os_xml="<os>
            <type arch='x86_64' machine='q35'>hvm</type>
            <loader readonly='yes' type='pflash'>$VM_NVRAM_CODE_FILE</loader>
            <nvram template='$template_vars'>$VM_NVRAM_VARS_FILE</nvram>                           
        </os>"        
    }    
    _set_qemu_mode() {   
        qemu_xml="<qemu:commandline>
            <qemu:arg value='-netdev'/>
            <qemu:arg value='user,id=adbnet,hostfwd=tcp::$ADB_SERVICE_PORT-:5555'/>
            <qemu:arg value='-device'/>
            <qemu:arg value='virtio-net-pci,netdev=adbnet,mac=$VM_NETWORK_MAC,bus=pcie.0,addr=0x10'/>                                
        </qemu:commandline>"       
    }
    _set_cpu_mode() {
        echo "🧠 Otimizando CPU para Stealth e Software Rendering..."
        
        # VM_CPU_CORES deve ser 4 ou mais para o Bliss não engasgar
        cpu_xml="<cpu mode='host-passthrough' check='none'>
            <topology sockets='1' dies='1' cores='$VM_CPU_CORES' threads='1'/>
            <feature policy='require' name='x2apic'/>
        </cpu>
        <clock offset='utc'>
            <timer name='rtc' tickpolicy='catchup'/>
            <timer name='pit' tickpolicy='delay'/>
            <timer name='hpet' present='no'/>
            <timer name='kvmclock' present='yes'/>
            <timer name='hypervclock' present='yes'/>
        </clock>"
    }
    _set_vesa_mode() {
        require_vars VM_CPU_CORES
        echo "🔧 Preparando variáveis XML para Modo VESA (Software Rendering)..."

        video_xml="<video>
        <model type='vga' vram='65536' heads='1' primary='yes'/>
        </video>"

        graphics_xml="<graphics type='spice' autoport='yes' listen='127.0.0.1' gl='off'>
            <listen type='address' address='127.0.0.1'/>
        </graphics>"
        
        channel_spice_xml="<channel type='spicevmc'>
            <target type='virtio' name='com.redhat.spice.0'/>
        </channel>"
        _set_sound_pulse_mode
    
    }
    _set_virtio_mode() {
        require_vars VM_RENDER_DEVICE VM_NAME
        require_devices VM_RENDER_DEVICE

        export VM_SOCKET="/tmp/virtio-$VM_NAME.sock"
        echo "🚀 Configurando Spice com Socket Unix em /tmp/virtio-$VM_NAME.sock..."


        graphics_xml="<graphics type='spice' autoport='no'>
            <listen type='socket' socket='$VM_SOCKET'/>
            <gl enable='yes' rendernode='$VM_RENDER_DEVICE'/>
        </graphics>"
        # No video_xml, mantém o cket encontrado em /tmp/virtio-bvirtio
        video_xml="<video>
            <model type='virtio' vram='262144' heads='1'>
                <acceleration accel3d='yes'/>
            </model>
        </video>"

        ### ON
        graphics_xml="<graphics type='spice' autoport='yes' listen='127.0.0.1' gl='off'>
            <listen type='address' address='127.0.0.1'/>
        </graphics>"
    
        video_xml="<video>
            <model type='virtio' vram='65536' heads='1' primary='yes'>             
            </model>
        </video>"
        _set_sound_pulse_mode
    }
    _set_nvidia_mode() {
        require_vars VM_RENDER_DEVICE
        require_devices VM_RENDER_DEVICE

        # MODO SDL (Janela direta, melhor performance Nvidia)
        graphics_xml="<graphics type='sdl' display=':0'>
            <gl enable='yes' rendernode='$VM_RENDER_DEVICE'/>
        </graphics>"
        video_xml="<video>
          <model type='virtio' vram='131072' primary='yes'>
            <acceleration accel3d='yes'/>
          </model>
        </video>"
        graphics_xml="<graphics type='spice' autoport='yes'>
          <listen type='none'/>
          <gl enable='yes' rendernode='$VM_RENDER_DEVICE'/>
        </graphics>"


        video_xml="<video>
          <model type='virtio' vram='131072' primary='yes'>
            <acceleration accel3d='yes'/>
          </model>
        </video>"
        graphics_xml="<graphics type='sdl' display=':0' xauth='/home/vitor/.Xauthority'>
            <gl enable='no'/> 
        </graphics>"
        video_xml="<video>
          <model type='virtio' vram='131072' primary='yes'/>
        </video>"

        # No modo NVIDIA (Spice), mantemos o canal
        channel_spice_xml="<channel type='spicevmc'>
          <target type='virtio' name='com.redhat.spice.0'/>          
        </channel>"
        channel_spice_xml=""
                        
        # Garante acesso ao X11 no momento da definição
        export DISPLAY=:0
        export XAUTHORITY=/home/vitor/.Xauthority
        xhost +si:localuser:$(whoami) > /dev/null 2>&1
    }
    # --- 4. Segmento de Features (Anti-Detection / Stealth) ---
    _set_features_mode() {
        echo "🛡️  Configurando Features Anti-VM (Stealth Mode)..."
        features_xml="<features>
            <acpi/>
            <apic/>
            <kvm>
                <hidden state='on'/>
            </kvm>
            <hyperv mode='custom'>
                <relaxed state='on'/>
                <vapic state='on'/>
                <spinlocks state='on' retries='8191'/>
                <vendor_id state='on' value='genuineintel'/>
            </hyperv>            
        </features>"
    }

    _set_control_mode() {
        echo "🔌 Configurando apenas Android Control (VirtIO)..."    
        local xxx="<serial type='unix'>
            <source mode='bind' path='$ANDROID_CTL'/>
            <target port='0'/>
        </serial>
        <console type='unix'>
            <source mode='bind' path='$ANDROID_CTL'/>
            <target type='serial' port='0'/>
        </console>"
        
    }
    _set_network_mode() {
        network_xml="<interface type='user'>
        <mac address='08:60:6e:7c:2b:66'/>
        <model type='virtio'/>
        <qemu:commandline>
            <qemu:arg value='-netdev'/>
            <qemu:arg value='user,id=adbnet,hostfwd=tcp::5555-:5555'/>
        </qemu:commandline>
        </interface>"
    }
    local install_mode=${1:-"false"}

    echo "🔍 DEBUG: Modo Instalação: $install_mode "
    
    if [ ! -f "$VM_DISK0_FILE" ]; then
        echo "💾 O disco virtual não existe em: $VM_DISK0_FILE"
        return 1
    fi

    local KIB_VALUE=$(convert_mb_to_kib "$VM_RAM_MB")
    show_vars \
        install_mode \
        VM_NAME \
        KIB_VALUE \
        VM_ISO_PATH \
        VM_DISK0_FILE \
        VM_GRAPH_MODE

    require_vars \
        VM_NAME \
        KIB_VALUE \
        VM_ISO_PATH \
        VM_DISK0_FILE \
        VM_GRAPH_MODE \
        || return 1

    require_devices \
        VM_RENDER_DEVICE     

    local vm_xml="/tmp/${VM_NAME}.xml"

    _set_boot_order "$install_mode"   
    _set_os_mode                           
    _set_cpu_mode    
    _set_features_mode

    
    #_set_control_mode
    if [[ "$VM_GRAPH_MODE" == "nvidia" ]]; then                
        _set_nvidia_mode   
    elif [[ "$VM_GRAPH_MODE" == "scrcpy" ]]; then                
        _set_virtio_mode        
        echo ""
        _set_qemu_mode
    else 
        _set_vesa_mode 
        _set_qemu_mode
    fi

    # --- 1. Limpeza e Garantia de Rede,video,sound,sock,files,permissions ---    
    _vm_initialize  
    
    if [ "$install_mode" != "true" ]; then   
        _gl_fix_permissions_default           
    fi

    # --- 4. Montagem Final (Versão Estabilizada) ---
    cat <<EOF > "$vm_xml"
<domain type="kvm" xmlns:qemu="http://libvirt.org/schemas/domain/qemu/1.0">
  <name>${VM_NAME}</name>
  <memory unit='KiB'>$KIB_VALUE</memory>
  <vcpu>$VM_CPU_CORES</vcpu>
  $os_xml
  $features_xml
  $cpu_xml  
  
  <devices>
    <emulator>/usr/bin/qemu-system-x86_64</emulator>    
    <controller type='pci' index='0' model='pcie-root'/>
    <controller type='virtio-serial' index='0'/>

    $hd_xml
    $cdrom_xml
    
    $graphics_xml
    $video_xml
    $channel_spice_xml    
    $sound_xml    
    <input type='tablet' bus='usb'/>
    <input type='keyboard' bus='ps2'/>
  </devices>
  <qemu:commandline>
    <qemu:arg value='-netdev'/>
    <qemu:arg value='user,id=adbnet,hostfwd=tcp::$ADB_SERVICE_PORT-:5555'/>
    <qemu:arg value='-device'/>
    <qemu:arg value='virtio-net-pci,netdev=adbnet,mac=$VM_NETWORK_MAC,bus=pcie.0,addr=0x10'/>
    <qemu:arg value='-smbios'/>
    <qemu:arg value='type=1,manufacturer=Samsung,product=SM-X900,serial=988D12444554465241'/>
  </qemu:commandline>
</domain>
EOF

    # --- 5. Aplicação ---
    # Formata o XML de forma limpa para o Libvirt
    xmlstarlet fo "$vm_xml" > "${vm_xml}.tmp" && mv "${vm_xml}.tmp" "$vm_xml"
    # view xml
    cat "$vm_xml" | pygmentize -l xml
    # machine validate
    xmllint --noout "$vm_xml" && {
            echo "$vm_xml validated with xmllint: OK" 
        } || {
            echo "xmllint invalidated $vm_xml" && return 1
        }

    # apply xml
    virsh define "$vm_xml" && echo "✅ VM definida com sucesso."         
}


etc_systemd__libvirtd_service() {
    echo "--- Iniciando Override ---"
    local nvidia_json
    nvidia_json=$(nvidia_egl_json_file)
    
    if [ -z "$nvidia_json" ]; then
        echo "❌ Erro: Ficheiro JSON da NVIDIA não encontrado."
        return 1
    fi

    echo "✅ Ficheiro: $nvidia_json"
    check_nvidia_driver_config || true
    sudo mkdir -p /etc/systemd/system/libvirtd.service.d/

    # Atenção: O EOF tem de estar encostado à esquerda no ficheiro!
    sudo bash -c "cat <<EOF > $VM_HOST_NVIDIA_CONF_FILE
[Service]
Environment=\"LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu\"
Environment=\"__GLX_VENDOR_LIBRARY_NAME=nvidia\"
Environment=\"__EGL_VENDOR_LIBRARY_FILENAMES=$nvidia_json\"
EOF"

    echo "🔄 Reiniciando Libvirtd..."
    sudo systemctl daemon-reload
    sudo systemctl restart libvirtd
    echo "✅ Sucesso!"
}
export -f etc_systemd__libvirtd_service



bliss_base_flow() {
    require_binaries "qemu-img" "virt-install" && echo "tools installed" || \
        os_package_setup  # Instala dependências e aa-complain

    is_valid_iso || (bliss_image_download || return 1)  # Valida o ISO e sai quando nao resolve imagem
    
    if [ "$VM_GRAPH_MODE" = "nvidia" ]; then       
        require_files VM_HOST_NVIDIA_CONF_FILE && etc_systemd__libvirtd_service            
    fi
    
    etc_libvirt_qemu      # Configura user=$USER e security=none

    # define boot sequence
    _vm_initialize && {
        _hd_check_uefi_integrity || \
        { echo "run: prep_disk_boot to init disk file"; return 1; }     
        require_files "VM_DISK0_FILE" || \
        { echo "❌ Missing VM_DISK0_FILE=$VM_DISK0_FILE"; return 1; }

        _vm_clean_kernel_boot_vga_safe
        _vm_bridge_efi_to_vda2
        _vm_patch_android_defaults
    }
}

bliss_run_flow() {    
    require_vars VM_DISK0_FILE
    bliss_base_flow

    # 1. Se o disco não existe ou está vazio, preparamos a estrutura    
    #    prep_disk_partition  # Aqui corres os comandos 'parted'
    #    prep_disk_boot   # Aqui montas o nbd0p1 e geres as pastas EFI
    
    
    # apply xml
    local BOOT_TIME=$(date +"%Y-%m-%d %H:%M:%S.%3N")
    #args, means. boot hd with default graphics
    bliss_blueprint "false" || return 1

    ! _vm_is_running && _vm_start
    sleep 2
    _vm_is_running && \
    {   
        _vm_viewer
        sleep 4
        _vm_log "$BOOT_TIME"
    }
    _vm_is_running && \
    {
        #_ado_wait_and_unlock         
        #_ado_install_meogo_if_missing
        #_vm_scrcpy
        _vm_log "$BOOT_TIME"
    } &
    
    
}
    
bliss_boot_cd() {
    bliss_base_flow

    _hd_check_uefi_integrity || \
        { echo "run: prep_disk_boot to init disk file"; return 1; }

     require_files "VM_DISK0_FILE" || \
        { echo "❌ Missing VM_DISK0_FILE=$VM_DISK0_FILE"; return 1; }
    

    #args, means. boot by cd with default graphics
    bliss_blueprint "true" "default" || return 1
    _vm_start        # Liga a VM
    _vm_viewer       # Abre o ecrã
}

_vm_disable_cd() {
    virt-xml "$VM_NAME" --remove-device --disk target=sdb
    #virt-xml "$VM_NAME" --edit --disk target=sda,boot_order=1
    # Para mudar o boot para o disco como prioritário:
    #virt-xml "$VM_NAME" --edit --disk target=sda,boot_order=1
}

_gl_enable_default() {
    require_vars "VM_NAME"
    # 1
    virt-xml --connect qemu:///system "$VM_NAME" --edit --video accel3d=yes    
    # NVidea
    virt-xml --connect qemu:///system "$VM_NAME" --edit --graphics gl.enable=yes 

    
    # Adiciona o teu utilizador ao grupo de renderização
    sudo usermod -aG render $USER
    sudo usermod -aG render,video $USER
    # IMPORTANTE: Para o grupo ser ativado, precisas de fazer Logout/Login
    # ou usar este comando para a sessão atual:
    
    newgrp render
    

    _gl_fix_permissions_default

        # O restart do libvirtd é necessário para ler o novo qemu.conf se houver alterações
    sudo systemctl restart libvirtd
}
_gl_enable_nvidia() {
    # 1. Ativa o 3D e o OpenGL no SPICE    
    virt-xml --connect qemu:///system "$VM_NAME" --edit --video accel3d=yes    
    # NVidea
    virt-xml --connect qemu:///system "$VM_NAME" --edit --graphics gl.enable=yes 

    # Adiciona o teu utilizador ao grupo de renderização
    sudo usermod -aG render $USER
    sudo usermod -aG render,video $USER
    # IMPORTANTE: Para o grupo ser ativado, precisas de fazer Logout/Login
    # ou usar este comando para a sessão atual:
    
    newgrp render
    newgrp video

    # Aplica permissões nos ficheiros de hardware da NVIDIA
    _gl_fix_permissions_nvidia
        # O restart do libvirtd é necessário para ler o novo qemu.conf se houver alterações
    sudo systemctl restart libvirtd
}        
_egl_test() {
     eglinfo | grep -i "EGL version"
     glxinfo | grep "OpenGL vendor"
}
_launch_viewer() {
    local VM_SOCKET="/tmp/virtio-$VM_NAME.sock"
    
    echo "🔍 Aguardando inicialização do hardware gráfico..."
    sleep 3
    _vm_is_running && echo "VM Is Running" || echo "VM Not running" 
    if [ -S "$VM_SOCKET" ]; then
        echo "✅ Socket encontrado. Ajustando permissões..."
        
        # No teu script, logo após a VM iniciar:
        sudo chown $USER:libvirt $VM_SOCKET
        sudo chown $USER:libvirt $VM_RENDER_DEVICE
        
        sudo chmod 666 $VM_SOCKET
        sudo chmod 666 $VM_RENDER_DEVICE
        sudo setfacl -m u:$USER:rw $VM_RENDER_DEVICE

        echo "🚀 Abrindo Remote Viewer..."
        # Variáveis de ambiente integradas para evitar o erro de EGL surface

        export LIBGL_ALWAYS_SOFTWARE=1
        export __GLX_VENDOR_LIBRARY_NAME=nvidia
        export __EGL_VENDOR_LIBRARY_FILENAMES=$VM_HOST_NVIDIA_CONF_FILE
        export GDK_BACKEND=x11

        remote-viewer "spice+unix://$VM_SOCKET" > /tmp/viewer.log 2>&1 &
    else
        echo "❌ Erro: O socket $VM_SOCKET não apareceu. Verifique os logs da VM."
    fi
}

_launch_scrcpy()  {    
    _vm_is_running || virsh --connect qemu:///system start "$VM_NAME"   

    # 1. Espera que a VM esteja a correr  
    _vm_wait4_running || return 1    

}        



_vm_check_health() {
    local vm_status="[OFFLINE]"
    local control_status="[OFFLINE]"
    local adb_status="[OFFLINE]"

    _vm_is_running && vm_status="[  RUNNING   ]"
    #_vm_is_android_control_ready && control_status="[  OK   ]"

    _vm_is_adb_ready && adb_status="[  OK  ]"

    echo -e "📊  Status check:"
    echo -e "   VM $VM_NAME : $vm_status "
    echo -e "   GRAPH MODE : $VM_GRAPH_MODE "
    echo -e "   adb   : $adb_status "
}
_vm_is_running && {
    _vm_check_health 
    } || { \
        echo "VM $VM_NAME Not Running" 
        echo "run: "
        echo "  bliss_blueprint "
        echo "  bliss_run_flow"
        echo "  vm_ensure_ready"
    }



require_functions \
    os_package_setup \
        bliss_image_download \
        bliss_blueprint \
        _vm_code_edit \
    _vm_launch \
        etc_systemd__libvirtd_service \
    bliss_base_flow \
        _vm_nuke_disk \
        bliss_run_flow \
        bliss_boot_cd     

bliss_view() {
    echo "📺 A iniciar visualização Bliss OS..."
    
    # Aguarda o estado 'device' (evita crashes se ainda estiver a bootar)
    adb -s 127.0.0.1:5555 wait-for-device
    
    # Lança scrcpy com tweaks de performance
    scrcpy -s 127.0.0.1:5555 \
        --window-title "Bliss OS - $VM_NAME" \
        --always-on-top \
        --turn-screen-off \
        --stay-awake \
        --power-off-on-close \
        --encoder 'OMX.google.h264.encoder' \
        --max-fps 60
}        
_vm_reset() {
    require_vars VM_NAME
    local vm_xml="/tmp/${VM_NAME}.xml"
    require_files vm_xml || bliss_blueprint
    require_files vm_xml || return 1
    _vm_initialize
    sleep .1
    # Agora sim, define e arranca
    cat "$vm_xml" | pygmentize -l xml

    local BOOT_TIME=$(date +"%Y-%m-%d %H:%M:%S.%3N")
    virsh define "$vm_xml" && echo "✅ VM definida com sucesso."

    ! _vm_is_running && _vm_start
    sleep 2
    _vm_is_running && \
    {
        _ado_wait_and_unlock 
        #_ado_install_meogo_if_missing
        #_vm_scrcpy
    } &
    _vm_is_running && \
    {   
        _vm_viewer
        sleep 4
        _vm_log "$BOOT_TIME"
    }
    

     #_vm_wait4_android_control &&  {sleep 15 && _android_control_set}
     
        
     #OBS_BOOT
}

ALT_BOOT(){
    _vm_start    
    echo "⏳ Aguardando Android Control ficar ONLINE..."
    _vm_wait4_android_control # Espera o socket existir
    echo "☕ Pausa de 15s para o Android carregar o sistema base..."
    sleep 15
    echo -e "\n✅ Canal pronto! Injetando comandos..."
    _android_control_set      # Envia setprops
    
    # ESTE É O PASSO CRUCIAL:
    # Não fazemos o check de saúde imediatamente. 
    # Esperamos o ADB acordar primeiro.
    _vm_wait4_adb_ready 90 

    # Agora sim, o check de saúde vai dar [ONLINE]
    _vm_check_health
    
    # NOVO: Aguardar o serviço ADB responder na porta 5555
    
    
    echo ""
    _vm_check_health

    # Se não tiveres o virt-viewer instalado: sudo apt install virt-viewer
    _vm_wait4_running && {
        virt-viewer --connect qemu:///system bliss-os-dev &
    }
   
}


_android_control_set() {
    require_vars ANDROID_CTL
    echo "📡 Injetando persistência via SQL Settings (Global)..."
    {
        # O segredo da persistência: injetar na base de dados global, não apenas no setprop
        echo "settings put global adb_enabled 1"
        echo "settings put global development_settings_enabled 1"
        
        # Propriedades de sistema para o daemon adbd
        echo "setprop persist.adb.tcp.port 5555"
        echo "setprop persist.sys.usb.config adb"
        
        # Remove a necessidade de clicar em "Permitir" no ecrã (RSA bypass)
        echo "setprop ro.adb.secure 0"
        
        # Reinicia o daemon para ler as novas tabelas SQL
        echo "stop adbd"
        echo "start adbd"
    } | sudo -n socat - UNIX-CONNECT:"$ANDROID_CTL"
}