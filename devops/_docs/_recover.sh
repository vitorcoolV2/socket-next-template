# 1. Start with working system
./3-host-critical-snapshot.sh

# 2. Try fixing DNS
sudo nmcli connection modify "wired-enp4s0" ipv4.dns "8.8.8.8"

# 3. Test - if internet broken:
./2-host-system-gain.sh
