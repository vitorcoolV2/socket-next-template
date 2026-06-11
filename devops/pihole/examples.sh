#!/bin/bash
# Load the library
. ./pihole_lib.sh

auth_exit() {
    ph_api password rotate
    # 1. Connect
    if ph_api auth; then
        echo "Session Active."
        ph_api logout
        echo "Session closed safely."
    else
        echo "Failed to prepare Pi-hole session."    
    fi
}

block() {
    ph_api password rotate
    if ph_api auth; then
        echo "Session Active."
        RESPONSE=$(curl -s -k -X GET "$PIHOLE_URL/api/dns/blocking" \
            -H "X-FTL-SID: $X_FTL_SID")
        # Parse the boolean result
        STATUS=$(echo "$RESPONSE" | jq -r '.blocking')

        if [ "$STATUS" == "true" ]; then
            echo "🛡️ Pi-hole is ACTIVE (Blocking Enabled)"
        else
            echo "⚠️ Pi-hole is DISABLED (Blocking Paused)"
        fi

        # 2. Act (Example: Enable blocking)
        curl -s -k -X POST "$PIHOLE_URL/api/dns/blocking" \
            -H "X-FTL-SID: $X_FTL_SID" \
            -H "Content-Type: application/json" \
            -d '{"blocking": true}' 
        
        echo "Blocking is enabled."

        # 3. Disconnect (Optional but recommended)
        ph_api logout
        echo "Session closed safely."
    else
        echo "Failed to prepare Pi-hole session."
        exit 1
    fi
}


unnlock() {
    ph_api password rotate
    if ph_api auth; then
        echo "Session Active."
        echo "Accessing Pi-hole with SID: $X_FTL_SID"
        
        # Example: docker gather container names on app-network
        curl -s -k -X GET "$PIHOLE_URL/api/stats/summary" \
            -H "X-FTL-SID: $X_FTL_SID" | jq .


        ph_api logout
    else
        echo "Failed to prepare Pi-hole session."
        exit 1
    fi
}


enable() {
    .  ./dns_utils.sh

    # Uma vez no host, como root
    sudo sysctl -w net.core.rmem_default=114688
    sudo sysctl -w net.core.wmem_default=114688

    # Para persistir após reboot
    echo "net.core.rmem_default=114688" | sudo tee -a /etc/sysctl.conf
    echo "net.core.wmem_default=114688" | sudo tee -a /etc/sysctl.conf

    ph down
    ph disable
    set_nmcli_resolver ("${PIHOLE_SPARK_DNS[@]}")

    ph up
    ph enable

    echo "⏳ Waiting for Pi-hole..."
    until curl -s http://$PIHOLE_DNS_IP/admin/ > /dev/null; do
        sleep 2
    done

}