
# 1. Parar todos os containers que usam a rede app-network
echo "1. Parando todos os containers..."
docker stop $(docker ps -q --filter network=app-network) 2>/dev/null || echo "Nenhum container para parar"


docker network rm app-network

# Recreate with proper IPAM config
docker network create \
  --driver=bridge \
  --subnet=172.28.0.0/24 \
  --gateway=172.28.0.1 \
  --ip-range=172.28.0.0/24 \
  app-network  
