#!/bin/bash
# --- _9-nuke-and-rebuild.sh ---
# O objetivo deste script é a reconstrução total e automatizada.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"


. $(realpath ../vault/_0-authentik_lib.sh)
. $(realpath ./_2-enable-oidc-provider.sh)

ask_nuke_and_rebuild_authentik() {
    echo "☢️  Iniciando FULL NUKE AND REBUILD..."
    echo "Destruindo dados do Authentik e recriando via Steward/Vault..."
    
    # 1. Confirmação de Segurança
    read -p "Tem a certeza que deseja enable_oidc_well_known_openid_flowAPAGAR TUDO? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Operação abortada pelo utilizador."
        return 1
    fi
    
    return 0
}

nuke_and_rebuild_flow() {
    ask_nuke_and_rebuild_authentik && {
        # Coloca aqui os teus comandos de destruição:
        # --- 1. DESTRUCTION ---
        echo "🧹 Phase 1: Cleaning environment..."
        # Reinicia a base e o redis primeiro
        docker compose down -v  # Destrói containers e Named Volumes (DB/Redis/Media)

        # --- 2. SECRET INJECTION ---
        echo "🔑 Phase 2: Synchronizing Infrastructure Secrets..."
        # Garante que as passwords do Postgres e Secret Keys estão prontas
        . $(realpath ../authentik/_0-authentik_lib.sh)

        # --- 3. BOOTSTRAP STACK ---
        echo "🏗️  Phase 3: Starting Containers..."
        ak_up

        ak_wait4_instance && \
            echo -e "\n✅ Authentik Stack is up."

        # --- 5. SECURITY HANDSHAKE (OIDC Sync) ---
        echo "🔐 Phase 6: Synchronizing Vault <-> Authentik Trust..."
        # Este script sincroniza o client_secret entre o Provider criado e o Vault
        . ./_2-enable-oidc-provider.sh --renew-api 
        enable_oidc_well_known_openid_flow

        # --- 6. LOGICAL STRUCTURE (Blueprints) ---
        echo "🏗️  Phase 6: Enable Vault OIDC and Sync Blueprints groups..."
        . ./_3-enable-oidc-vault.sh 
        sync_vault_flow

        # --- 7. LOGICAL STRUCTURE (Blueprints) ---
        echo "🏗️  Phase 7: Initialize Home-Admins, Home-Developers, Home-Users..."
        ./_4-sync-oidc-home2500-team.sh --renew-admin  --sync-team # testing..

    }
}

nuke_and_rebuild_flow

# --- 7. FINAL VALIDATION ---
echo "------------------------------------------------"
echo "✨ REBUILD COMPLETE!"
echo "------------------------------------------------"
echo "🌍 Authentik: https://auth.${DOMAIN}"
echo "🛡️  Vault:     https://vault.${DOMAIN}"
echo ""
echo "👉 To verify OIDC Login, run"
echo "   vault login -method=oidc role=$AUTENTIK_OIDC_VAULT_STEWARD_ROLE"