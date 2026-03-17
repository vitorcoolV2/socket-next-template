#!/bin/bash
# Filename: _1-provision-traefik-certs.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"


source "$SCRIPT_DIR/_0.traefik_lib.sh"

if tk_need_renewal; then
    echo "🚀 Starting renewal process..."
    tk_renew_certs

    echo "⏳ Aguardando reload do Traefik (5s)..."
    sleep 5 
    tk_test_tls
else
    echo "✅ System is up to date. Skipping Vault API calls."
fi
