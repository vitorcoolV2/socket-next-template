#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"


docker compose down 
# 1. Load the Steward Token (No more Root Token needed)
# This provides the VAULT_TOKEN via AppRole login
. ../authentik/_0-authentik_lib.sh

# --- CONFIGURATION ---
DB_CONTAINER="authentik-db"
SUPER_USER="authentik"      
NETDATA_USER="netdata"      
GO_D_PATH=$(realpath "./go.d")
NETDATA_CONF_PATH="$GO_D_PATH/postgres.conf"

# 2. Get or Generate Password using Steward (Wildcard secret/* access)
# We store this under secret/netdata/postgres
NETDATA_DB_PASSWORD=$(vault kv get -field="NETDATA_DB_PASSWORD" "secret/netdata" 2>/dev/null || echo "")

if [ -z "$NETDATA_DB_PASSWORD" ]; then
    echo "✨ Generating new Postgres password for Netdata Steward..."
    NETDATA_DB_PASSWORD=$(openssl rand -base64 32)
    
    # Steward uses 'put' or 'patch' to save
    vault kv put "secret/netdata" "NETDATA_DB_PASSWORD=$NETDATA_DB_PASSWORD"
fi

# --- DATABASE EXECUTION ---
#### ????? @todo
# --- NETDATA CONFIG GENERATION ---
echo "Writing collector config to $NETDATA_CONF_PATH..."
GO_D_PATH=$(realpath "./go.d")
NETDATA_CONF_PATH="$GO_D_PATH/postgres.conf"

sudo mkdir -p "$GO_D_PATH"

# Write file with the generated password
sudo tee "$NETDATA_CONF_PATH" > /dev/null <<EOF
jobs:
  - name: "authentik-db-stats"
    dsn: "host=$DB_CONTAINER port=5432 user=$NETDATA_USER password='$NETDATA_DB_PASSWORD' dbname=postgres sslmode=disable"
EOF

# --- PERMISSIONS & RESTART ---
# Set ownership to Netdata user (999)
sudo chown -R 999:999 "$GO_D_PATH"
sudo chmod -R 755 "$GO_D_PATH"

# If the main go.d.conf exists, fix it too
if [ -f "./go.d.conf" ]; then
    sudo chown 999:999 ./go.d.conf
    sudo chmod 644 ./go.d.conf
fi

echo "✅ Done! Configuration written. Restarting Netdata..."

# Optional: Verify connection
# docker exec -it netdata /usr/libexec/netdata/plugins.d/go.d.plugin -d -m postgres