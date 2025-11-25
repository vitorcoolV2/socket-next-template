#!/bin/bash

# Exit on error
set -e

#!/bin/bash

# Change to script directory
cd "$(dirname "$0")"

echo "Working directory: $(pwd)"


# STOP ALL running containers
# STOP ALL running containers (if any)
docker ps -aq | xargs -r docker stop
docker ps -aq | xargs -r docker rm

# clean docker containers, network
docker container prune -f
docker network prune -f  

# Create or ensure app-network exists
echo "Creating app-network..."
# Recreate with proper IPAM config
docker network create \
  --driver=bridge \
  --subnet=172.28.0.0/16 \
  --gateway=172.28.0.1 \
  --ip-range=172.28.0.0/16 \
app-network  

####### PIHOLE, required default system 8.8.8.8 replacement
# firsttime - pihole up, we need system resolution from google 8.8.8.8
#!/bin/bash
echo "🌐 Temp DNS to Google..."
sudo nmcli connection modify "wired-enp4s0" ipv4.dns "8.8.8.8"
sudo nmcli connection modify "wired-enp4s0" ipv4.ignore-auto-dns yes
sudo nmcli connection down "wired-enp4s0"
sudo nmcli connection up "wired-enp4s0"

echo "🐳 Start Pi-hole..."
cd pihole && docker compose up -d && cd ..

echo "⏳ Waiting for Pi-hole..."
until curl -s http://172.28.0.2/admin/ > /dev/null; do
    sleep 5
done

echo "✅ Pi-hole ready, switching DNS..."
sudo nmcli connection modify "wired-enp4s0" ipv4.dns "172.28.0.2"
sudo nmcli connection down "wired-enp4s0"
sudo nmcli connection up "wired-enp4s0"


echo "The "ALL POINT", step certification, protection, to be able to crypt connection"
cd step-ca
docker compose up -d step-ca
sleep 3
./iknew-traefik.host2500.local.sh
./iknew-openldap.app-network.sh
cd ..

ls -la

######## OPENLDAP
echo "🐳 Start openldap..."
cd openldap/
#### requirements of this setup
#docker compose up -d openldap
#echo "waiting for openldap"
./firsttime-run.sh

sleep 4
docker network inspect app-network

# Register Working docker containers on pihole 
echo "Working directory: $(pwd)"
node authelia-ldap/stage0-docker-app-network.js
nslookup openldap.app-network
nslookup step-ca.app-network
nslookup pihole.app-network

# register docker containers of app-network
# means:
#   it will register containers ips into pihole as <container_name>.app.external
#   expected available and resolvable after bellow script run: pihole.app-network, postgres.app-network, openldap.app-network


#### 
# AT THIS POINT THE home2500 CORE SYSTEM MUST BE UP, and can


# NOW pihole should be able to resolve internet && the registered ones
# to fully enable pihole protection

##### AFTER docker pihole is running on docker container running on network app-network
### sudo cat to /etc/resolv.conf
#nameserver 127.0.0.1
#search app-network


### register pihole *.home2500.local. make *.home2500.local resolvable
node authelia-ldap/stage2-update-pihole-dns.js
cd ..

#### AUTHELIA

echo "🐳 Start Authelia..."
cd authelia
docker compose up -d postgres
docker compose up -d authelia
cd ..

###### TRAEFIK is home2500.local inner certification

cd traefik
docker compose up -d
#./copy-certs.sh  -------- changed behavior. certification traefit is part of step-ca script
./test-1-certs.sh
./test-2-available.sh
docker compose up -d
cd ..



COMPOSE_STACK_FILES=( "stack/portainer" "stack/kuma" "stack/phpldapadmin")
# "socket.io" "react-app" "hedgedoc"  "kuma" )

upCompose() {
  local dir=$1
  echo "Processing $dir..."
  cd "$dir" || { echo "Directory $dir not found"; exit 1; }
  docker-compose up -d
  sleep 5
  cd - > /dev/null || exit 1
}


# Relaunch each service
for file in "${COMPOSE_STACK_FILES[@]}"; do
  upCompose "$file"
done

echo "All services relaunched."

##### update pihole registration of *.home2500.local
cd openldap
node authelia-ldap/stage2-update-pihole-dns.js
./test-user.sh
cd ..



