# 1. Test OIDC discovery endpoint
curl --insecure https://auth.home2500.local/.well-known/openid-configuration | jq .

# 2. Test authorization endpoint (should show login page)
curl --insecure "https://auth.home2500.local/authorize?client_id=kuma.home2500.local&redirect_uri=https://kuma.home2500.local/&response_type=code&scope=openid+profile"

# 3. Check kuma-auth logs to see what's happening
docker logs kuma-auth

# 4. Test accessing Kuma (should redirect to auth)
curl --insecure -I https://kuma.home2500.local/

# 5. Test Pi-hole (should work directly)
curl --insecure -I https://pihole.home2500.local/