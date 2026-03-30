#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

NEW_SEAL=false
[[ "$1" == "--new-seal" ]] && NEW_SEAL=true

set -e
echo "🚀 Iniciando Vault em modo HTTP para configuração..."
. ./keepass.sh

. ./vault_lib.sh # unsealif needed and gen token
vault_switch http


# 1. Localização e Validação
certs_dir=$(realpath ./config/certs/)

if [ "$NEW_SEAL" = true ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  CRITICAL OPERATION: VAULT TOTAL WIPE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # --- FASE 1: PREPARAÇÃO & BACKUP ---
    echo "🔐 Autenticação necessária para Backup e Validação..."

    echo "💾 Realizando backup dos segredos antigos no KeePass..."
    # Sugestão: Adicionar timestamp ao nome da pasta de backup

    kp_archive_vault # current vault archive before go on

    # --- FASE 3: DESTRUIÇÃO (Controlo Atómico) ---
    echo "🧨 DESTROYING VAULT DATA..."

    # Para containers
    docker compose down    
    
    # Limpa certificados (Força password com -k)
    echo "🧹 Eliminando certificados em $certs_dir..."
    #sudo -k rm -f "${certs_dir:?}"/*
    sudo rm -f "${certs_dir:?}"/*
    
    # Limpa Volume (Força password novamente com -k)
    echo "🗑️  Removendo volume Docker..."
    docker volume rm vault_home2500_data 
    
    echo "✨ Vault storage wiped."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi
####### MUST test each stEP oF tHE aWY WiTh feedback from a dot or cursor
docker compose up -d
set +e

. ./vault_lib.sh

set -e
echo "⏳ Waiting for Vault API..."
until curl -s "$VAULT_ADDR/v1/sys/health" > /dev/null; do printf "." && sleep 2; done

STATUS=$(curl -s "$VAULT_ADDR/v1/sys/health")
INITIALIZED=$(echo "$STATUS" | jq -r '.initialized')

# 4. Inicialização
if [ "$INITIALIZED" = "false" ]; then
    echo "🏗️  Initializing new Vault instance..."  
    echo "VAULT_ADDR=$VAULT_ADDR"
    INIT_OUTPUT=$(docker exec -e VAULT_ADDR="http://127.0.0.1:8200" vault vault operator init -key-shares=1 -key-threshold=1 -format=json)    
    UNSEAL_KEY=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[0]')
    VAULT_TOKEN=$(echo "$INIT_OUTPUT" | jq -r '.root_token')
    
    set +e
    kp_save_entry "vault/root/VAULT_TOKEN" "$VAULT_TOKEN"
    kp_save_entry "vault/root/UNSEAL_KEY" "$UNSEAL_KEY"
    set -e
    echo "✅ Keys saved to KeePass."
fi

# 5. Unseal
if [ "$(echo $(curl -s $VAULT_ADDR/v1/sys/health) | jq -r '.sealed')" = "true" ]; then
    echo "🔓 Unsealing..."
    UNSEAL_KEY=$(kp_get_entry_value "vault/root/UNSEAL_KEY")
    docker exec -e VAULT_ADDR="http://127.0.0.1:8200" vault vault operator unseal "$UNSEAL_KEY"
fi

echo "🟢 Vault is ready!"