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


#. $(realpath  ./vault/keepass.sh) ## include password retrivel

# FULL BOOT SEQUNECE 

__docker_reset__clean() {
  core_desired_domain_names_json # static result json
  docker_app_network_json   # dynamic result json 

  stop() {
    # Ensure the Docker daemon configuration file exists
    DOCKER_DAEMON="/etc/docker/daemon.json"
    if [[ ! -f "$DOCKER_DAEMON" ]]; then
      echo "Error: $DOCKER_DAEMON does not exist."
      return 1
    fi

    # Stop all running containers (if any)
    echo "Stopping all running containers..."
    docker ps -aq | xargs -r docker stop >/dev/null 2>&1 || true
  }
  
  reset() {
    # Remove all stopped containers
    echo "Removing all stopped containers..."
    docker ps -aq | xargs -r docker rm >/dev/null 2>&1 || true

    # Prune unused containers and networks
    echo "Pruning unused containers and networks..."
    docker container prune -f >/dev/null 2>&1
    docker network prune -f >/dev/null 2>&1
  }
  
  restart() {
      # Restart Docker service to ensure a clean state
    echo "Restarting Docker service..."
    sudo systemctl restart docker
  }

  create_network() {
    # Recreate the app-network with proper IPAM configuration
    echo "Recreating $INTERNAL_DOMAIN..."
    docker network inspect $INTERNAL_DOMAIN >/dev/null 2>&1 && docker network rm $INTERNAL_DOMAIN >/dev/null 2>&1 || true

    docker network create \
      --driver=bridge \
      --subnet=172.28.0.0/16 \
      --gateway=172.28.0.1 \
      --attachable \
      --internal=false \
      --ip-range=172.28.0.0/16 \
      $INTERNAL_DOMAIN >/dev/null 2>&1

    echo "Docker reset complete. $INTERNAL_DOMAIN has been recreated."
  }

  stop
  remove
  reset
  create_network


}
[[ " $@ " == *" --cleanup "* ]] && __docker_reset__clean


###### BOOT HARD CORE (PIHOLE + VAULT) - boot before authentik. 
kp open
source $(core_resolve_file "pihole/_0.pihole_lib.sh")  
##ph api open
wait4_http_url_ready "$PIHOLE_URL/admin/" || \
  ph down && ph up && \
    wait4_http_url_ready "$PIHOLE_URL/admin/" 10 || exit 1
## pihole trial requiremens
ph api auth     && echo "Ready to register names" \
ph api dns sync && echo "Desired names + Pihole" \
  echo "PIHOLE ONLINE" || exit 1

####### VAULT
source $(core_resolve_file "vault/vault_lib.sh")  
restart_vault() {
  (
    cd "$DEVOPS_DIR/vault"                                          
    docker compose up -d   ## KEEP THIS LINE !!!!!!!!! important. Will not start vault without

    
    
  ) || return 1
}  
wait4_http_url_ready $VAULT_ADDR || restart_vault || exit 1
is_sealed && vault_unseal || return 1    
    ### NO https no request
vault_request_stew_token || return 1
vault_validate_token || return 1
require_vars "VAULT_CACERT"
is_sealed && vault_unseal || return 1    
wait4_http_url_ready $VAULT_ADDR 5 && echo "VAULT ONLINE" || exit 1


###### AUTHENTIK RESTART
source $(core_resolve_file "authentik/_0-authentik_lib.sh")
ak_up || return 1
ph api auth && \
ph api dns sync && \
wait4_http_url_ready "$AUTHENTIK_INTERNAL_URL" 10 || exit 1
# after start. request last token or generate one
# will fail when authentik is not available HEAR. ! very important
ak_api_token_restore \
  || ak_api_token_generate


###### TRAEFIK, AUTHENTIK, 
source $(core_resolve_file "traefik/_0.traefik_lib.sh") > /dev/null
tk_up 
ph api auth
ph api dns sync





# authentik fully ready
wait4_http_url_ready $AUTHENTIK_INTERNAL_URL 50


# no TOKEN to continue. next fase apply blue Authentik blueprint
ak_api_token_validate || return 1

#### WAIT whoami (service container) is the first (little stone|step) to OIDC TESTING REQUIREMENTS GROUD. 
#### if not available y better review Authentik from simpler setup
wait4_http_url_ready "whoami.$DOMAIN" || (tk_down && tk_up)
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

COMPOSE_STACK_FILES=( "opencode" "backup" "fotos" "files")

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
    . ./init.sh > /dev/null
    app_up
    sleep 5   
  )
}

# Relaunch each service
for file in "${COMPOSE_STACK_FILES[@]}"; do
  upCompose "$file"
done

# sync
ph api auth
ph api dns sync
ak_fix_proxied_redir

echo "All services relaunched."



