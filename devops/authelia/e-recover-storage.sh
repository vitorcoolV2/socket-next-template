#!/bin/bash

###### RECOVER from MESSED UP existing postgress 

# Change to script directory
cd "$(dirname "$0")"
echo "Working directory: $(pwd)"

docker-compose down


docker rm -f authelia postgresql  ## realy down
sudo rm -rf ./data/postgres       ## volume out 
# get UNLOCK_PASSWORD,ADMIN_PASSWORD
. .env
mkdir -p data/authelia/secrets    ## make sure

sudo chown $USER:$USER data/authelia/secrets   

# recover .env secrets
echo "$UNLOCK_PASSWORD" > ./data/authelia/secrets/STORAGE_PASSWORD
echo "$ADMIN_PASSWORD" > ./data/authelia/secrets/AUTHENTICATION_BACKEND_LDAP_PASSWORD

# Set permissions for secrets
chmod 600 ./data/authelia/secrets/*


# dramatic new postgresql instance
sudo chown root:root data/authelia/secrets   
sudo mkdir -p data/postgres


# Validate the configuration.yml file
#docker compose down authelia
# Validate config using run (recommended approach)
docker compose run --rm authelia \
  authelia config validate --config /config/configuration.yml

docker compose up -d

sleep 5

docker logs authelia
docker logs postgresql

# Define constants
AUTHELIA_CONTAINER_NAME="authelia"
run_storage_command() {
    local command="$1"
    
    # Read secrets from container and pass as environment variables
    docker compose exec "$AUTHELIA_CONTAINER_NAME" "$command"
}
run_storage_command "authelia storage user --help"

./net-recover.sh