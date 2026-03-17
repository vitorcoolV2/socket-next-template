#!/bin/bash
# recover-snapshot.sh - Restore system from snapshot

echo "🔍 Available snapshots:"
BACKUP_DIR="/backup/snapshots"

if [ ! -d "$BACKUP_DIR" ]; then
    echo "❌ No backup directory found: $BACKUP_DIR"
    exit 1
fi

# List available snapshots
SNAPSHOTS=$(ls -t "$BACKUP_DIR"/*-state.txt 2>/dev/null | head -10)

if [ -z "$SNAPSHOTS" ]; then
    echo "❌ No snapshots found in $BACKUP_DIR"
    exit 1
fi

echo ""
echo "📋 Available snapshots:"
i=1
for snap in $SNAPSHOTS; do
    name=$(basename "$snap" "-state.txt")
    date=$(stat -c %y "$snap" 2>/dev/null | cut -d' ' -f1-2)
    echo "  $i) $name ($date)"
    i=$((i+1))
done

echo ""
read -p "🔄 Enter snapshot number to recover: " choice

# Get selected snapshot
SNAPSHOT_FILE=$(echo "$SNAPSHOTS" | sed -n "${choice}p")
SNAPSHOT_NAME=$(basename "$SNAPSHOT_FILE" "-state.txt")

if [ -z "$SNAPSHOT_NAME" ]; then
    echo "❌ Invalid selection"
    exit 1
fi

echo ""
echo "🚨 WARNING: This will restore system configuration from: $SNAPSHOT_NAME"
read -p "❓ Continue? (y/N): " confirm

if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "❌ Recovery cancelled"
    exit 0
fi

echo "🔄 Starting recovery from: $SNAPSHOT_NAME"

# Stop services that might interfere
echo "⏹️  Stopping services..."
sudo systemctl stop apparmor 2>/dev/null || true
sudo systemctl stop docker 2>/dev/null || true

# Extract configuration backup
CONFIG_FILE="$BACKUP_DIR/$SNAPSHOT_NAME-config.tar.gz"
if [ -f "$CONFIG_FILE" ]; then
    echo "📁 Restoring configuration files..."
    sudo tar -xzf "$CONFIG_FILE" -C /
else
    echo "⚠️  No config backup found: $CONFIG_FILE"
fi

# Restart services
echo "🔄 Restarting services..."
sudo systemctl daemon-reload
sudo systemctl start NetworkManager
sudo systemctl start apparmor 2>/dev/null || true
sudo systemctl start docker 2>/dev/null || true

echo ""
echo "✅ Recovery completed from: $SNAPSHOT_NAME"
echo "📊 Previous system state was:"
cat "$SNAPSHOT_FILE"

echo ""
echo "🔁 Please reboot for all changes to take effect: sudo reboot"