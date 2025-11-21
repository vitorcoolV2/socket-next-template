#!/bin/bash
docker compose down
# Backup and modify resolv.conf (corrected filename)
sudo chattr -i /etc/resolv.conf
sudo cp /etc/resolv.conf /etc/resolv.conf.backup
echo 'nameserver 8.8.8.8' | sudo tee /etc/resolv.conf

# Set trap to restore original config on exit
trap 'sudo cp /etc/resolv.conf.backup /etc/resolv.conf && sudo chattr +i /etc/resolv.conf' EXIT

# Reset pihole

sudo rm -rf ./etc-dnsmasq.d ./etc-pihole
sleep 1

docker compose up -d

sleep 5

docker logs --tail 2000 pihole


# Wait for setup to complete, then the trap will automatically restore resolv.conf