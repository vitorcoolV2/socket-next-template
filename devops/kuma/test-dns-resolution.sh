# Test DNS resolution
nslookup auth.home2500.local
ping -c 2 auth.home2500.local

# Test HTTP access
curl -I http://auth.home2500.local/health

# Test HTTPS access (with insecure for self-signed cert)
curl --insecure -I https://auth.home2500.local/health