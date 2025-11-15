# 1. Check if containers are running
docker ps | grep -E '(traefik|kuma-auth)'

# 2. Check Traefik logs
docker logs traefik | grep auth.home2500.local

# 3. Test from inside Traefik container
docker exec traefik curl -s http://kuma-auth:3000/health

# 4. Check Traefik API
curl --insecure https://traefik.home2500.local/api/http/routers | jq '.[] | select(.rule | contains("auth"))'

# 5. Verify SSL certificate
openssl s_client -connect auth.home2500.local:443 -servername auth.home2500.local < /dev/null