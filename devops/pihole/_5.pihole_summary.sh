#!/bin/bash

# Load the library
. ./_0.pihole_lib.sh

# 1. Connect
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