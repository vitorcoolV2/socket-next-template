#!/bin/bash
# Filename: ../../devops/pihole/./dns_utils.sh

# Top of dns_utils.sh
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ This is a library and should be sourced, not run directly." >&2
    return 1
fi


. ../core.sh

# Function to set DNS resolver via nmcli
set_nmcli_resolver() {
    local dns_ip="$1"
    local connection="${2:-$(detect_active_connection)}"
    local interface=detect_active__interface

    echo "🌐 Temp DNS from External unfiltered source..."
    sudo nmcli connection modify "$connection" ipv4.dns "$dns_ip"
    sudo nmcli connection modify "$connection" ipv4.ignore-auto-dns yes
    sudo nmcli connection down "$connection"
    sudo nmcli connection up "$connection"
}

# Example usage
#set_resolv_nameserver "8.8.8.8" true
#set_resolv_nameserver "1.1.1.1" true
#set_resolv_nameserver "127.0.0.1" false


# Function to detect the active connection profile name
detect_active_connection() {
    local device="${1:-$(detect_active__interface)}"  # Default to detected active interface
    >&2 echo "🔍 Searching for active connection profile associated with device: $device..."

    # Use grep and cut to extract the connection profile name
    local connection=$(nmcli -t -f NAME,DEVICE connection show --active | grep ":$device\$" | cut -d':' -f1)

    if [ -z "$connection" ]; then
        >&2 echo "❌ No active connection found for device $device."
        return 1
    fi

    >&2 echo "🌐 Detected active connection profile: $connection"
    echo "$connection"  # Only the connection profile name is printed to stdout
}


enable_pihole() {

    # 3. Se o ficheiro for gerido pelo systemd-resolved
    sudo systemctl stop systemd-resolved
    sudo systemctl disable systemd-resolved
    sudo systemctl start systemd-resolved
    sudo systemctl enable systemd-resolved
    sudo rm -f /etc/resolv.conf
    sudo tee /etc/resolv.conf << 'EOF'
nameserver 127.0.0.1
EOF

    # 4. Testar novamente
    nslookup pihole
    dig pihole
    nslookup pihole.local
    dig pihole.local
    
    nslookup caddy
    dig caddy
    nslookup caddy.local
    dig caddy.local
    sudo systemctl status systemd-resolved
}


disable_pihole() {
    # 2. Se o sistema não está a usar 127.0.0.1, corrigir
    sudo systemctl stop systemd-resolved
    sudo systemctl disable systemd-resolved
    sudo systemctl start systemd-resolved
    sudo systemctl enable systemd-resolved

    sudo tee /etc/resolv.conf << 'EOF'
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

    nslookup google.com
    dig google.com

    nslookup pihole
    dig pihole
    nslookup pihole.local
    dig pihole.local
}


test___pihole_inner_dns() {
    # 1. Verificar se o container está realmente a correr
    podman ps | grep pihole

    # 2. Verificar se o serviço systemd está ativo
    systemctl --user status pihole

    # 3. Ver logs do container
    podman logs pihole 2>&1 | tail -30

    # 4. Testar DNS dentro do container
    podman exec pihole dig google.com

    # 5. Testar se o pihole está a escutar
    podman exec pihole netstat -tlnp | grep 53
}