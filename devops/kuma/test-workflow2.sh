# Clear old cookies and start fresh
rm -f cookies.txt

# 1. Access Kuma (should redirect to OIDC login)
echo "=== Step 1: Access Kuma (should redirect to OIDC) ==="
curl --insecure -I "https://kuma.home2500.local/"

# 2. Login via OIDC
echo -e "\n=== Step 2: Login via OIDC ==="
curl --insecure -X POST "https://auth.home2500.local/login" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin&password=admin123&client_id=kuma.home2500.local&redirect_uri=https://kuma.home2500.local/&scope=openid+profile" \
  -c cookies.txt -L -v

# 3. Check if session was created
echo -e "\n=== Step 3: Check sessions ==="
curl --insecure -b cookies.txt "https://auth.home2500.local/debug/sessions" | jq .

# 4. Test accessing Kuma with session
echo -e "\n=== Step 4: Access Kuma with session ==="
curl --insecure -b cookies.txt -I "https://kuma.home2500.local/dashboard"

# 5. Test accessing other services
echo -e "\n=== Step 5: Test Pi-hole (should work without OIDC) ==="
curl --insecure -I "https://pihole.home2500.local/"

echo -e "\n=== Step 6: Test Traefik dashboard (should use OIDC) ==="
curl --insecure -I "https://traefik.home2500.local/"