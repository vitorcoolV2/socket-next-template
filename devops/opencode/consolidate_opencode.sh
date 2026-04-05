# path: devops/opencode/consolidate_opencode.sh
#!/bin/bash

# --- CONSOLIDATE_OPENCODE.SH ---
# Este script limpa as duplicações e garante a estrutura de Atores 2.7.
# Atualizado para lidar com a transição de 'security' para 'vault-admin'.

BASE_DIR="/home/vitor/nextjs-app-template/devops/opencode/config/skills"

echo "🧹 Iniciando limpeza de Atores em $BASE_DIR..."

# 1. Remover pastas obsoletas ou duplicadas
# Removemos '02-devops-security' pois o novo padrão é '02-vault-admin'
if [ -d "$BASE_DIR/02-devops-security" ]; then
    echo "🗑️ Removendo Ator obsoleto: 02-devops-security"
    rm -rf "$BASE_DIR/02-devops-security"
fi

# Remover outras pastas sem ID ou redundantes da tua árvore (tree)
rm -rf "$BASE_DIR/network-admin"
rm -rf "$BASE_DIR/00-worker-explorer"

# 2. Limpar ficheiros de backup/lixo que poluem o contexto da IA
echo "🗑️ Limpando ficheiros de lixo (copy/md1)..."
find "$BASE_DIR" -name "SKILL copy.md" -delete
find "$BASE_DIR" -name "SKILL.md1" -delete
find "$BASE_DIR" -name "SKILL.md.*" -delete

# 3. Garantir nomes de pastas corretos e IDs únicos
if [ -d "$BASE_DIR/system-explorer" ]; then
    echo "📦 Normalizando: system-explorer -> 00-system-explorer"
    mv "$BASE_DIR/system-explorer" "$BASE_DIR/00-system-explorer"
fi

# 4. Ajuste de compatibilidade para o check_actors.sh
# O log mostrou que o script atual falhou ao detetar 'docker compose' e 'vault'
# Vou renomear para o padrão 'check_actors.sh' (sem o 'e')
if [ -f "/home/vitor/nextjs-app-template/devops/opencode/check_actores.sh" ]; then
    echo "🚚 Renomeando check_actores.sh -> check_actors.sh"
    mv "/home/vitor/nextjs-app-template/devops/opencode/check_actores.sh" "/home/vitor/nextjs-app-template/devops/opencode/check_actors.sh"
fi

echo "✅ Estrutura consolidada com sucesso."
echo "Nova hierarquia de Atores detetada:"
ls -F "$BASE_DIR"