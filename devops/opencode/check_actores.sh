#!/bin/bash

# path: opencode/check_actors.sh
# --- CHECK_ACTORS.SH ---
# Script para validar a prontidão dos Atores e Skills do OpenCode no ambiente Home2500.
# Versão: 1.1 (Nomenclatura Limpa & Zero-Leak)

# 1. Carregar Core e Cores
if [ -f "../core.sh" ]; then
    source "../core.sh"
    echo "✅ [01-Core Architect] Core Lib encontrada e carregada."
else
    # Fallback simples se não encontrar a lib para não quebrar o script de check
    echo "❌ [01-Core Architect] ERRO: ../core.sh não encontrada."
    exit 1
fi

echo "--- Iniciando Auditoria de Atores ---"

# 2. Validar Estrutura de Skills (Configuração da IA)
SKILLS_DIR="./config/skills"
ACTORS=("00-system-explorer" "01-core-architect" "02-vault-admin" "03-auth-authentik" "04-network-admin" "05-release-manager")

for actor in "${ACTORS[@]}"; do
    if [ -d "$SKILLS_DIR/$actor" ] && [ -f "$SKILLS_DIR/$actor/SKILL.md" ]; then
        echo "✅ [Actor $actor] Skill definida e documentada."
    else
        echo "⚠️  [Actor $actor] AVISO: Pasta ou SKILL.md em falta em $SKILLS_DIR/$actor"
    fi
done

# 3. Validar Binários e Dependências de Runtime (Necessários para os Atores operarem)
echo "--- Validando Ferramentas de Runtime ---"

check_tool() {
    if command -v "$1" >/dev/null 2>&1; then
        echo "✅ [Tool] $1 instalada."
    else
        echo "❌ [Tool] $1 NÃO ENCONTRADA. (Obrigatória para Ator $2)"
    fi
}


check_tool "yq" "00-System Explorer"
check_tool "jq" "00-System Explorer"
check_tool "vault" "02-Vault Admin"
check_tool "docker-compose" "01-Core Architect"
check_tool "curl" "03-Auth Authentik"

# 4. Validar Regra Zero-Leak (Caminho de Memória)
if [[ -d "$MEM_ROOT_DIR" ]]; then
    echo "✅ [Zero-Leak] MEM_ROOT_DIR disponível em $MEM_ROOT_DIR"
else
    echo "⚠️  [Zero-Leak] MEM_ROOT_DIR não existe. Criando em subshell..."
    ( mkdir -p "$MEM_ROOT_DIR" && chmod 700 "$MEM_ROOT_DIR" )
fi

echo "--- Check Finalizado ---"