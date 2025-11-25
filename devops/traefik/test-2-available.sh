#!/bin/bash

# Change to script directory
cd "$(dirname "$0")"

echo "Working directory: $(pwd)"


##### RUN CODE REAL WEB, with rooted authentication
curl -k -H "Host: auth.home2500.local" https://localhost/ 

# Test whoami service. ingress inner,local whoami,
curl -k -H "Host: whoami.home2500.local" https://localhost/

# Test traefik service to proxy docker services to *.home2500.local step-ca 
curl -k -H "Host: traefik.home2500.local" https://localhost/

# Test name local register, the meams to block name services
curl -k -H "Host: pihole.home2500.local" https://localhost/ 


# Test STACK TOOLS
curl -k -H "Host: kuma.home2500.local" https://localhost/
curl -k -H "Host: portainer.home2500.local" https://localhost/

