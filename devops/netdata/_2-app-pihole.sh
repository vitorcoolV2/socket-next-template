#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

docker compose down 
# 1. Load Steward Token
. ../vault/vault_lib.sh 
vault_request_stew_token

# 2. Get or Generate Password
get_current_pihole_password() {
  # 2. Get or Generate Password
  TARGET_PW=$(vault_get_secret "pihole" "WEB_API_PASSWORD")
  echo $TARGET_PW
}

echo "🔄 use existing pihole password..."
TARGET_PW=$(get_current_pihole_password)

# 4. Write Netdata Config using sudo tee to bypass permissions
NETDATA_CONF="./go.d/pihole.conf"
GO_D_DIR="./go.d"

echo "Updating Netdata configuration..."

# Create directory if it doesn't exist
sudo mkdir -p "$GO_D_DIR"

# Use sudo tee to write the file
sudo tee "$NETDATA_CONF" > /dev/null <<EOF
jobs:
  - name: pihole_local
    url: "http://pihole.app-network"
    password: "$TARGET_PW"
    timeout: 2s
EOF

#url: "http://pihole.app-network/api/legacy/stats/summary"

# 5. Correct Ownership and Permissions
sudo chown -R 999:999 "$GO_D_DIR"
sudo chmod 755 "$NETDATA_CONF"

# 6. Restart
docker compose restart netdata

echo "✅ Pi-hole and Netdata are now fully synced."
echo $NETDATA_CONF


# docker exec netdata /usr/libexec/netdata/plugins.d/go.d.plugin -d -m pihole
