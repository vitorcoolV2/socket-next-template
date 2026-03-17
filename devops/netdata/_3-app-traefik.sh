#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

docker compose down 
# --- CONFIGURAÇÃO ---
GO_D_PATH=$(realpath "./go.d")
TRAEFIK_CONF_PATH="$GO_D_PATH/traefik.conf"

# O Traefik geralmente expõe métricas em uma porta separada (ex: 8082)
# Certifique-se que o Traefik está na mesma rede 'app-network'
TRAEFIK_URL="http://traefik.app-network:8082/metrics"

echo "Writing Traefik collector config to $TRAEFIK_CONF_PATH..."

# 1. Criar diretório se não existir
sudo mkdir -p "$(dirname "$TRAEFIK_CONF_PATH")"

# 2. Escrever a configuração
sudo tee "$TRAEFIK_CONF_PATH" > /dev/null <<EOF
jobs:
  - name: traefik_local
    url: "$TRAEFIK_URL"
EOF

# 3. Ajustar permissões para o usuário do Netdata (ID 999)
sudo chown -R 999:999 "$GO_D_PATH"
sudo chmod -R 755 "$GO_D_PATH"

echo "✅ Done! Traefik configuration written."
echo "👉 IMPORTANTE: Verifique se o Traefik tem os flags '--metrics.prometheus=true' ativos."
echo "👉 Now run: docker restart netdata"


#docker exec netdata /usr/libexec/netdata/plugins.d/go.d.plugin -d -m traefik