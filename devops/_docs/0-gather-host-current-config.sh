# 1. Check current network status
echo "=== NETWORK INTERFACE ==="
ip addr show enp4s0

echo "=== ROUTING TABLE ==="
ip route show

echo "=== DNS CONFIG ==="
cat /etc/resolv.conf

# 2. Check service states
echo "=== SERVICE STATUS ==="
systemctl status NetworkManager --no-pager -l
systemctl status apparmor --no-pager -l
systemctl status systemd-resolved --no-pager -l
systemctl --failed --no-pager

# 3. Check NetworkManager connections
echo "=== NETWORKMANAGER CONNECTIONS ==="
nmcli connection show --active
nmcli device status

# 4. Check system state
echo "=== SYSTEM STATE ==="
systemctl is-system-running
cat /etc/X11/default-display-manager 2>/dev/null || echo "No display manager config found"

# 5. Check what we actually changed
echo "=== CRITICAL FILES ==="
ls -la /etc/resolv.conf
ls -la /etc/NetworkManager/


# Reset any remaining failed services
sudo systemctl reset-failed

# Check system state
systemctl is-system-running

# Should now say "running" or "degraded" but with desktop working