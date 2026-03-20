#!/bin/bash

# Exit on error
set -e


cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Working directory: $(pwd)"  >&2

source ./vault/keepass.sh > /dev/null 2>&1 

show_vars DOMAIN \
    INTERNAL_DOMAIN \
    PUBLIC_SERVICES_LIST \
    AUTHENTIK_ADMIN_USER \
    VAULT_PKI_CN \
    VAULT_ROOT_CA_NAME 

core_desired_domain_names_json # static result json
docker_app_network_json   # dynamic result json 

#. $(realpath  ./vault/keepass.sh) ## include password retrivel

# FULL BOOT SEQUNECE 
__docker_reset_not_volumes_not_images() {
  DOCKER_DAEMON="/etc/docker/daemon.json"
  require_files DOCKER_DAEMON

  # STOP ALL running containers (if any)
  docker ps -aq | xargs -r docker stop
  docker ps -aq | xargs -r docker rm

  # clean docker containers, network
  docker container prune -f
  docker network prune -f  

  sudo systemctl restart docker
  # Create or ensure app-network exists
  echo "Creating app-network..."
  # Recreate with proper IPAM config
  docker network create \
    --driver=bridge \
    --subnet=172.28.0.0/16 \
    --gateway=172.28.0.1 \
    --attachable \
    --internal=false \
    --ip-range=172.28.0.0/16 app-network  
}
__docker_reset_not_volumes_not_images

###### BOOT HARD CORE (PIHOLE + VAULT) - boot before authentik. 
source $(core_resolve_file "pihole/_0.pihole_lib.sh")  
ph api open
ph down
ph up
ph api auth     && echo "Ready to register names"
ph api dns sync && echo "Desired names + Pihole"
echo "PIHOLE ONLINE"


####### VAULT
restart_vault() {
  (
    cd "$DEVOPS_DIR/vault"                                          
    docker compose up -d   ## KEEP THIS LINE !!!!!!!!! important. Will not start vault without

    source $(core_resolve_file "vault/vault_lib.sh")  
    require_vars "VAULT_CACERT"
    is_sealed && vault_unseal || return 1
    ### NO https no request
    vault_request_stew_token || return 1
    vault_validate_token || return 1
  ) || return 1
}  
restart_vault && echo "VAULT ONLINE" || return 1

###### TRAEFIK, AUTHENTIK, 
source $(core_resolve_file "traefik/_0.traefik_lib.sh")
tk_up 
ph api auth
ph api dns sync

###### AUTHENTIK RESTART
source $(core_resolve_file "authentik/_0-authentik_lib.sh") 
ak_up
ph api auth
ph api dns sync

# after start. request last token or generate one
# will fail when authentik is not available HEAR. ! very important
ak_api_token_restore \
  || ak_api_token_generate

# authentik fully ready
wait4_http_url_ready $AUTHENTIK_INTERNAL_URL 50

# no TOKEN to continue. next fase apply blue Authentik blueprint
ak_api_token_validate || return 1

#### WAIT whoami (service container) is the first (little stone|step) to OIDC TESTING REQUIREMENTS GROUD. 
#### if not available y better review Authentik from simpler setup
wait4_http_url_ready "whoami.$DOMAIN"          
wait4_http_url_ready "$AUTHENTIK_URL" 50  

set_authentik_theme()  {
  (
    source $(core_resolve_file "authentik/theme/_builder.sh")  
    vault_validate_token
    _build_brand_theme "emotion"     
  )
}
set_authentik_theme


# review stack when authentik https app can be deployed by understandable composition manifest

COMPOSE_STACK_FILES=( "backup" "fotos" "files")

upCompose() {
  local name=$1
  echo "Processing $name..."
  local project="$DEVOPS_DIR/$name"
  (

    if ! require_locations project; then
      echo "Directory $project not found"; return 1;
    fi

    cd $project
    . ./init.sh > /dev/null 
    . ./init.sh 
    app_up
    sleep 5   
  )
}

# Relaunch each service
for file in "${COMPOSE_STACK_FILES[@]}"; do
  upCompose "$file"
done




echo "All services relaunched."



