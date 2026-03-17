# 1. Check current network status
echo "=== # Reset any remaining failed services ==="
# Reset any remaining failed services
sudo systemctl reset-failed

# Check system state
systemctl is-system-running

# Should now say "running" or "degraded" but with desktop working

# validate aquired caps
ping -c 2 google.com          # Internet connectivity ✓
curl -I https://google.com    # Web access ✓
systemctl is-system-running   # System state: "running" ✓
sudo aa-status                # AppArmor: loaded ✓