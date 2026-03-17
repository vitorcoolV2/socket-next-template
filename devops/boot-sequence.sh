#!/bin/bash

# Exit on error
set -e


cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Working directory: $(pwd)"  >&2

source ./core.sh > /dev/null 2>&1 

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
restart_pihole() {
  cd "$DEVOPS_DIR/pihole"
  docker compose up -d                                    ## KEEP THIS LINE

  source $(core_resolve_file "pihole/_0.pihole_lib.sh")  > /dev/null 2>&1
  ph_down
  ph_up
}
restart_pihole

####### VAULT
restart_vault() {
  cd "$DEVOPS_DIR/vault"                                               ## KEEP THIS LINE
  docker compose up -d                                    ## KEEP THIS LINE

  source $(core_resolve_file "vault/vault_lib.sh")  > /dev/null 2>&1
  set -e
  require_vars "VAULT_CACERT"
  is_sealed && vault_unseal
  ### NO https no request
  vault_request_stew_token
  vault_validate_token
  set +e
}  
restart_vault

###### PIHOLE
pihole_dns_sync() {
  docker_app_network_json
  ph_api password rotate
  ph_api auth
  ph_api dns sync
}
pihole_dns_sync

###### TRAEFIK, AUTHENTIK
restart_traefik() {
  source $(core_resolve_file "traefik/_0.traefik_lib.sh")  > /dev/null 2>&1
  tk_up
}

###### AUTHENTIK
restart_authentik() {
  source $(core_resolve_file "authentik/_0-authentik_lib.sh")  > /dev/null 2>&1
  vault_request_stew_token
  ak_up
  ak_api_token_generate
}
restart_authentik



#### WAIT whoami service
restart_wait4_basic_service() {
  ###### PIHOLE REGISTER names of current docker formation
  pihole_dns_sync
  tk_wait4_service_ready "whoami"
          
  cr_wait4_service_middleware_ready "auth" 2 || {          
      echo "fail to start cr_wait4_service_middleware_ready auth"   >&2
      return 1                         
  } 
}
restart_wait4_basic_service


restart_set_authentik_theme()  {
  source $(core_resolve_file "authentik/theme/_builder.sh")  > /dev/null 2>&1
  vault_validate_token || vault_request_stew_token
  ak_api_token_generate
  ak_api_token_validate
  _build_brand_theme "emotion"     
}

restart_set_authentik_theme
# review stack when authentik https app can be deployed by understandable composition manifest

COMPOSE_STACK_FILES=( "netdata" "backup" "fotos")

upCompose() {
  local name=$1
  echo "Processing $name..."
  cd "$DEVOPS_DIR/$name" || { echo "Directory $name not found"; exit 1; }
  . ./tool.sh
  app_up_template__proxy
  sleep 5
  cd $DEVOPS_DIR
}

# Relaunch each service
for file in "${COMPOSE_STACK_FILES[@]}"; do
  upCompose "$file"
done




echo "All services relaunched."



