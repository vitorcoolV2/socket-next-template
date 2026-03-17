#!/bin/bash
# Load the library
. ./_0.pihole_lib.sh

ph_api password rotate
# 1. Connect
if ph_api auth; then
    echo "Session Active."
    ph_api logout
    echo "Session closed safely."
else
    echo "Failed to prepare Pi-hole session."    
fi