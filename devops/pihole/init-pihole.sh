#!/bin/bash
docker compose down

PIHOLE_SPARK_DNS="1.1.1.1"
PIHOLE_DNS_IP="172.28.0.2"

####### PIHOLE, required default system 8.8.8.8 replacement
# firsttime - pihole up, we need system resolution from google 8.8.8.8
#!/bin/bash
echo "🌐 Temp DNS from External unfiltered source..."
sudo nmcli connection modify "wired-enp4s0" ipv4.dns "$PIHOLE_SPARK_DNS"
sudo nmcli connection modify "wired-enp4s0" ipv4.ignore-auto-dns yes
sudo nmcli connection down "wired-enp4s0"
sudo nmcli connection up "wired-enp4s0"

echo "🐳 Start Pi-hole..."
docker compose up -d && cd ..

echo "⏳ Waiting for Pi-hole..."
until curl -s http://$PIHOLE_DNS_IP/admin/ > /dev/null; do
    sleep 2
done

echo "✅ Pi-hole ready, switching DNS..."
sudo nmcli connection modify "wired-enp4s0" ipv4.dns "$PIHOLE_DNS_IP"
sudo nmcli connection down "wired-enp4s0"
sudo nmcli connection up "wired-enp4s0"
########################
sleep 1

docker compose up -d

sleep 5

docker logs --tail 2000 pihole


# Wait for setup to complete, then the trap will automatically restore resolv.conf