#!/bin/bash
# Filename: ../../devops/pihole/./dns_utils.sh

# Top of dns_utils.sh
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ This is a library and should be sourced, not run directly." >&2
    return 1
fi


# Function to set DNS resolver via nmcli
set_nmcli_resolver() {
    local dns_ip="$1"
    local connection="${2:-$(detect_active_connection)}"
    local interface=detect_active_interface

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


# Function to detect the active network interface
detect_active_interface() {
    local interface=$(ip route | grep default | awk '{print $5}')
    if [ -z "$interface" ]; then
        >&2  echo "❌ No active network interface found."
        return 1
    fi
    >&2 echo "🌐 Detected active network interface: $interface"
    echo "$interface"
}
# Nova função que reusa a anterior
detect_active_ipv4() {
    # Chama a função original e captura o resultado (stdout)
    # Redirecionamos o stderr para /dev/null para evitar mensagens duplicadas se desejar
    local interface=$(detect_active_interface)
    
    # Verifica se a função anterior falhou
    if [ $? -ne 0 ] || [ -z "$interface" ]; then
        return 1
    fi

    # Extrai o IP da interface retornada
    local ip_address=$(ip -4 addr show "$interface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)

    if [ -z "$ip_address" ]; then
        >&2 echo "❌ No IPv4 address found for $interface"
        return 1
    fi

    echo "$ip_address"
}
# Function to detect the active connection profile name
detect_active_connection() {
    local device="${1:-$(detect_active_interface)}"  # Default to detected active interface
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
