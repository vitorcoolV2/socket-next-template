#!/bin/bash

# Homelab Network Setup Script
echo "🏠 Homelab Network Setup"
echo "========================"

# 1. Check current Docker networks
echo "📋 Current Docker Networks:"
docker network ls

# 2. Get Pi-hole network details
PIHOLE_NETWORK=$(docker inspect pihole --format='{{.HostConfig.NetworkMode}}')
echo -e "\n🔍 Pi-hole Network: $PIHOLE_NETWORK"

# 3. Inspect the network
echo -e "\n🌐 Network Details:"
docker network inspect $PIHOLE_NETWORK | jq '.[] | {Name: .Name, Driver: .Driver, Subnet: .IPAM.Config[0].Subnet, Gateway: .IPAM.Config[0].Gateway}'

# 4. Check all containers on this network
echo -e "\n🐳 Containers on this network:"
docker network inspect $PIHOLE_NETWORK | jq -r '.[].Containers[] | "\(.Name): \(.IPv4Address)"'

# 5. Get host machine network info
echo -e "\n💻 Host Machine Network:"
ip route show default | head -1
hostname -I