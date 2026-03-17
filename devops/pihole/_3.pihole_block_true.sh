#!/bin/bash
# Load the library
. ./_0.pihole_lib.sh


# 1. Connect
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