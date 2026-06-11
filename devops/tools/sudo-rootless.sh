#!/bin/bash

# Exit on error
# set -e

set +e

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ This is a library and should be sourced, not run directly."  >&2
    echo "     Try: source ./$(realpath --relative-to="$PWD" "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
    return 1 2> /dev/null || exit 1
fi

init_rootless_user() {
    local name="$1"
    local start_uid="$2"
    local range="${3:-65536}"
    local end_uid=$((start_uid + range - 1))
    
    # Verificar se já existe
    if grep -q "^${name}:" /etc/subuid 2>/dev/null; then
        echo "ℹ️  User $name already has sub-UID mappings: $(grep "^${name}:" /etc/subuid)"
        return 0
    fi
    
    echo "🔧 Configuring $name: ${start_uid}-${end_uid} (${range} sub-IDs)"
    
    sudo usermod --add-subuids ${start_uid}-${end_uid} \
                 --add-subgids ${start_uid}-${end_uid} \
                 "$name"
    
    if grep -q "^${name}:" /etc/subuid; then
        echo "✅ Rootless user $name ready"
        return 0
    else
        echo "❌ Failed to configure $name"
        return 1
    fi
}
# Validar que o user atual tem sub-IDs configurados
validate_sudo() {
    local username="$1"
    local expected_start="$2"
    local expected_range="${3:-65536}"
    
    if ! id $username &>/dev/null; then
        echo "❌ User $username does not exist"
        return 1
    fi
    id

    # Verificar se tem sub-IDs configurados
    if grep "${username}:" /etc/subuid; then        
        return 0
    fi
    
    # Verificar user range atual
    if ! grep "${username}:${expected_start}:${expected_range}" /etc/subuid ; then
        local current_range=$(grep "${username}:" /etc/subuid | cut -d: -f3)
        if [[ "$current_range" -lt "$expected_range" ]]; then
            echo "⚠️  User $username range ($current_range) < expected ($expected_range)"
            return 1
        fi
    else
        ## wrong user context ? check it out        
        grep "${username}:" /etc/subuid
    fi
    
    echo "✅ User $username validated (range: $current_range sub-IDs)"
    return 0
}
validate_sudo() {
    local username="$1"
    local expected_start="${2:-624288}"
    local expected_range="${3:-65536}"
    
    if ! id "$username" &>/dev/null; then
        echo "❌ User $username does not exist"
        return 1
    fi
    
    local subuid_entry=$(grep "${username}:" /etc/subuid 2>/dev/null)
    
    if [[ -z "$subuid_entry" ]]; then
        echo "🔧 Configuring sub-IDs for $username..."
        echo "${username}:${expected_start}:${expected_range}" | sudo tee -a /etc/subuid > /dev/null
        echo "✅ Sub-IDs configured"
    else
        local current_start=$(echo "$subuid_entry" | cut -d: -f2)
        local current_range=$(echo "$subuid_entry" | cut -d: -f3)
        
        if [[ "$current_start" != "$expected_start" ]] || [[ "$current_range" -lt "$expected_range" ]]; then
            echo "⚠️  Updating sub-IDs for $username..."
            sudo sed -i "/${username}:/d" /etc/subuid
            echo "${username}:${expected_start}:${expected_range}" | sudo tee -a /etc/subuid > /dev/null
            echo "✅ Sub-IDs updated"
        fi
    fi
    
    echo "✅ User $username ready for podman rootless"
    return 0
}
validate_sudo() {
    local username="$1"
    
    if [[ -z "$username" ]]; then
        echo "❌ Usage: validate_sudo <username>"
        return 1
    fi
    
    # Check if user exists
    if ! id "$username" &>/dev/null; then
        echo "❌ User $username does not exist"
        return 1
    fi
    
    # Show user profile
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 User Profile: $username"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Show UID, GID, groups
    echo "🔹 UID/GID: $(id -u "$username")/$(id -g "$username")"
    echo "🔹 Groups: $(id -nG "$username" | tr ' ' ', ')"
    
    # Show sub-UID configuration
    local subuid_entry=$(grep "${username}:" /etc/subuid 2>/dev/null)
    if [[ -n "$subuid_entry" ]]; then
        local sub_start=$(echo "$subuid_entry" | cut -d: -f2)
        local sub_range=$(echo "$subuid_entry" | cut -d: -f3)
        echo "🔹 Sub-UIDs: start=$sub_start, range=$sub_range"
    else
        echo "🔹 Sub-UIDs: none configured"
    fi
    
    # Show sub-GID configuration
    local subgid_entry=$(grep "${username}:" /etc/subgid 2>/dev/null)
    if [[ -n "$subgid_entry" ]]; then
        local subg_start=$(echo "$subgid_entry" | cut -d: -f2)
        local subg_range=$(echo "$subgid_entry" | cut -d: -f3)
        echo "🔹 Sub-GIDs: start=$subg_start, range=$subg_range"
    else
        echo "🔹 Sub-GIDs: none configured"
    fi
    
    # Check sudo capability
    local has_sudo=1  # default: no sudo
    
    # Method 1: Check if user is in sudo group
    if id -nG "$username" | grep -qw "sudo"; then
        has_sudo=0
        echo "🔹 Sudo: YES (member of 'sudo' group)"
    fi
    
    # Method 2: Check if user has sudo privileges via sudo -l (non-interactive)
    if sudo -l -U "$username" 2>/dev/null | grep -q "may run" 2>/dev/null; then
        has_sudo=0
        echo "🔹 Sudo: YES (has sudo privileges)"
    fi
    
    # Method 3: Check if sub-IDs are configured (for rootless podman)
    if [[ -n "$subuid_entry" ]]; then
        echo "🔹 Rootless Podman: YES (sub-IDs configured)"
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Return: 0 = has sudo/capability, 1 = no sudo
    if [[ $has_sudo -eq 0 ]]; then
        echo "✅ $username is sudo"
        return 0
    else
        echo "⚠️  $username is NOT privileged (no sudo/sub-IDs)"
        return 1
    fi
}


create_rootless_user() {
    ## current sudo delegate a role:sysgroups based. i hope it works as think it does
    local name="$1"
    local start_uid="$2"
    local range="${3:-65536}"
    shift 3
    local sysgroups=("$@")  # Grupos do sistema (ex: libvirt)
    
    # Validar argumentos
    if [[ -z "$name" || -z "$start_uid" ]]; then
        echo "❌ Usage: create_rootless_user <name> <start_uid> [range] [groups...]"
        echo "   Example:  create_rootless_user builder 231072 65536 libvirt"
        return 1
    fi
    
    # Criar user se não existir
    if ! id "$name" &>/dev/null; then
        echo "👤 Creating user: $name"
        
        # Criar com grupos especificados
        if [[ ${#sysgroups[@]} -gt 0 ]]; then
            sudo useradd -m -G "${sysgroups[*]}" -s /bin/bash "$name"
        else
            sudo useradd -m -s /bin/bash "$name"
        fi
        
        # Lock password (sem login direto)
        sudo passwd -l "$name" 2>/dev/null || true
        echo "✅ User $name created (use 'sudo -u $name' to access)"
    else
        echo "✅ User $name already exists"
        id ## ja exist e é
    fi
    
    # Configurar sub-IDs para rootless Podman
    init_rootless_user "$name" "$start_uid" "$range" 
    
    # Habilitar linger para serviços user persistirem
    echo "sudo loginctl enable-linger \"$name\""
    sudo loginctl enable-linger "$name"
    
    echo "✅ Rootless user $name ready"
    echo "📝 Test: sudo -u $name bash -c \"cd ~ && podman info | head -5\""
}

# Configurar ambiente de trabalho, para cada serviço

# Fleet: dns-network + unbound + pihole + pihole + caddy
# Nomeado em honra a Gerardus Mercator - o todo é feito do conjunto das partes

setup_service_user() {   
    if [[ -z "$_USER" ]]; then
        echo "❌ Usage: setup_service_user <name>"
        echo "   Example: setup_service_user gerardus"
        return 1
    fi
    
    # Ensure user exists first
    if ! id "$_USER" &>/dev/null; then
        echo "📦 User $_USER not found. Creating..."
        create_fleet_user "$_USER" || return 1
    fi
    
    # Verify sudo privileges for current user
    validate_sudo "$(whoami)" || return 1

    # Directory structure for distributed navigation:
    # - .config/containers/systemd    -> Blueprint fleet (.service, .network)
    # - .config/containers/storage    -> Persistent state for each part
    # - .config/systemd/user          -> Runnable services from quadlet
    
    local _HOME="/home/${_USER}"
    local _CONFIG="/home/${_USER}/.config"
    local _CONTAINERS="${_CONFIG}/containers"      # Fleet coordination layer
    local _QUADLET="${_CONFIG}/systemd/user"       # Executable services layer
    local _BLUEPRINT="${_CONTAINERS}/systemd"      # Service definitions (the parts)
    local _STORAGE="${_CONTAINERS}/storage"        # Persistent volume mount points
    
    echo "🌊 Setting up fleet for $_USER at $_HOME"
    echo "   'The whole is made of the sum of its parts' - G. Mercator"
    
    # Create the distributed navigation structure
    sudo mkdir -p "$_CONTAINERS" "$_STORAGE" "$_BLUEPRINT" "$_QUADLET"
    
    # Set ownership - each part under fleet command
    sudo chown -R "$_USER:$_USER" "$_CONTAINERS" "$_QUADLET"
    
    # Verify the fleet workspace
    sudo -u "$_USER" ls . > /dev/null 2>&1
    
    echo "✅ Fleet $_USER ready with all parts at $_HOME"
    echo "   📍 Blueprints: $_BLUEPRINT"
    echo "   💾 Storage:    $_STORAGE"
    echo "   ⚙️  Services:   $_QUADLET"
}


# Listar apenas users "normais" (UID >= 1000, tipicamente users humanos/serviço)
get_users_for_deletion() {
    echo "🔍 Users with UID >= 1000 (potential fleet/service users):"
    echo "============================================"
    awk -F: '$3 >= 1000 && $3 < 65534 {print "   " $1 " (UID: " $3 ")"}' /etc/passwd
}

# Listar todos os users (incluindo sistema)
list_all_users() {
    echo "📋 ALL system users:"
    echo "============================================"
    cut -d: -f1 /etc/passwd | column
}

# Listar apenas users com home directory
list_users_with_home() {
    echo "🏠 Users with home directories:"
    echo "============================================"
    ls /home/ 2>/dev/null | while read user; do
        if id "$user" &>/dev/null; then
            echo "   $user"
        fi
    done
}

# Listar users que pertencem a grupos específicos (podman, docker)
list_container_users() {
    echo "🐳 Users in podman/docker groups:"
    echo "============================================"
    for group in podman docker; do
        if getent group "$group" >/dev/null 2>&1; then
            echo "   $group: $(getent group "$group" | cut -d: -f4)"
        fi
    done
}
# Fleet user management
list_fleet_users() {
    echo "🌊 Potential fleet users (from /home/):"
    echo "============================================"
    
    local found=0
    for user in $(ls /home/ 2>/dev/null); do
        if id "$user" &>/dev/null 2>&1; then
            local uid=$(id -u "$user" 2>/dev/null)
            local shell=$(getent passwd "$user" | cut -d: -f7)
            echo "   ✓ $user (UID: $uid, shell: $shell)"
            found=1
        fi
    done
    
    if [[ $found -eq 0 ]]; then
        echo "   (no users found in /home/)"
    fi
    echo ""
}

delete_fleet_user() {
    local _USER="$1"
    
    if [[ -z "$_USER" ]]; then
        echo "❌ Usage: delete_fleet_user <username>"
        echo "   Example: delete_fleet_user gerardus"
        echo ""
        echo "Available users:"
        list_fleet_users
        return 1
    fi
    
    # Check if user exists
    if ! id "$_USER" &>/dev/null 2>&1; then
        echo "❌ User $_USER does not exist"
        return 1
    fi
    
    # Warning
    echo "⚠️  WARNING: You are about to delete user: $_USER"
    echo "   Home directory: /home/$_USER"
    echo "   This action is IRREVERSIBLE!"
    read -p "   Type 'DELETE' to confirm: " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        echo "❌ Cancelled."
        return 1
    fi

    # Kill all user processes
    sudo pkill -u "$_USER" 2>/dev/null || true
    sleep 2
    
    # Force kill if still running
    sudo pkill -9 -u "$_USER" 2>/dev/null || true
    
    # Delete user and home directory
    echo "🗑️  Deleting user $_USER..."
    sudo userdel -r "$_USER" 2>/dev/null || {
        echo "⚠️  Could not delete home dir, removing user only..."
        sudo userdel "$_USER"
    }
    
    echo "✅ User $_USER has been deleted"
}

# Usage examples:

#delete_fleet_user "gerardus"             # Delete specific user
#delete_fleet_user ""                     # Will show help and list users

validate_sudo "$(whoami)" 
list_fleet_users                          # List all potential fleet users

