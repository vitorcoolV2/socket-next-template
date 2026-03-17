#!/bin/bash
# Load the library
. ./_0.pihole_lib.sh


# 1. Connect
ph_api password rotate
if ph_api auth; then
    echo "Session Active."

    # 2. Act (Example: Enable blocking)
    curl -s -k -X POST "$PIHOLE_URL/api/dns/blocking" \
        -H "X-FTL-SID: $X_FTL_SID" \
        -H "Content-Type: application/json" \
        -d '{"blocking": false}' 
    
    echo "Blocking is disabled."

    # 3. Disconnect (Optional but recommended)
    ph_api logout
    echo "Session closed safely."
else
    echo "Failed to prepare Pi-hole session."
    exit 1
fi