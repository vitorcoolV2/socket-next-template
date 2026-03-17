#!/bin/bash
# activate-snapshot.sh - Create system snapshot before risky changes

echo "🔍 Checking system state..."
SNAPSHOT_NAME="snapshot-$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="/backup/snapshots"

mkdir -p "$BACKUP_DIR"

echo "📸 Creating system snapshot: $SNAPSHOT_NAME"

# Capture critical system state
{
    echo "=== SNAPSHOT: $SNAPSHOT_NAME ==="
    echo "Time: $(date)"
    echo "System: $(systemctl is-system-running)"
    echo "--- Services ---"
    systemctl list-units --state=failed
    echo "--- Network ---"
    ip addr show enp4s0
    nmcli connection show --active
    echo "--- AppArmor ---"
    aa-status 2>/dev/null | head -10
    echo "--- Docker ---"
    docker ps --format "table {{.Names}}\t{{.State}}" 2>/dev/null
} > "$BACKUP_DIR/$SNAPSHOT_NAME-state.txt"

# Backup critical config files
tar -czf "$BACKUP_DIR/$SNAPSHOT_NAME-config.tar.gz" \
    /etc/NetworkManager/system-connections/ \
    /etc/apparmor.d/ \
    /etc/docker/ \
    /etc/resolv.conf 2>/dev/null

echo "✅ Snapshot created: $BACKUP_DIR/$SNAPSHOT_NAME-*"
echo "📝 State saved to: $SNAPSHOT_NAME-state.txt"
echo "⚙️  Config saved to: $SNAPSHOT_NAME-config.tar.gz"

# List recent snapshots
echo ""
echo "📋 Recent snapshots:"
ls -lt "$BACKUP_DIR"/*-state.txt 2>/dev/null | head -5