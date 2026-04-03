# OCIS/Fotos Issues Log

## 2026-03-28

### Issue: Traefik returning 404 for OCIS

**Symptoms:**

- Browser returns 404 when accessing https://files.home2500.local
- curl from server works (returns OCIS HTML)

**Root Cause:**

- OCIS expects HTTPS requests (OCIS_URL=https://files.home2500.local)
- When Traefik uses HTTP router with `server.scheme=http`, OCIS rejects with "Client sent an HTTP request to an HTTPS server"
- When Traefik uses TCP router without passthrough, OCIS terminates TLS and returns 404

**Solution:**

- Use TCP router with TLS passthrough: `traefik.tcp.routers.ocis.tls.passthrough=true`
- This passes HTTPS directly to OCIS without terminating TLS

**Labels used:**

```yaml
labels:
  - 'traefik.enable=true'
  - 'traefik.tcp.routers.ocis.rule=HostSNI(`files.home2500.local`)'
  - 'traefik.tcp.routers.ocis.entrypoints=websecure'
  - 'traefik.tcp.routers.ocis.tls=true'
  - 'traefik.tcp.routers.ocis.tls.passthrough=true'
  - 'traefik.tcp.services.ocis.loadbalancer.server.port=9200'
```

### Issue: IDM LDAP "Invalid Credentials" (Code 49)

**Symptoms:**

- ERR invalid credentials when binding to LDAP
- Failed to add users

**Root Cause:**

- secrets.env wasn't being read properly (special characters like $ being interpreted)
- IDM database had old/wrong passwords

**Solution:**

- Use single quotes around password values in secrets.env
- Delete IDM database: `rm -rf ./data/idm`
- Restart container to recreate with correct passwords

### Issue: OIDC redirect_uri using HTTP

**Symptoms:**

- Warning: invalid redirect_uri http://files.home2500.local - make sure to use https

**Solution:**

- Set OCIS_URL=https://files.home2500.local

### Note: IDM Data Persistence

- The IDM database is stored in `/var/lib/ocis/idm/` inside the container
- This is mapped to `./data/idm` on host
- When volume is mounted from host, data persists
- When container is removed but volume stays, IDM uses existing passwords
- To reset IDM: `rm -rf ./data/idm` before starting container

### Certificate Verification

The OCIS certificate is signed by the internal CA (home2500.local Intermediate CA):

```bash
# Verify certificate
openssl x509 -in server.crt -noout -subject -issuer
# Output:
# subject=CN = files.home2500.local
# issuer=CN = home2500.local Intermediate CA
```

This is the SAME CA that Traefik uses. The certificate and key are stored in the ocis-config volume at `/etc/ocis/server.crt` and `/etc/ocis/server.key`.

To use without cert warnings in browser, install the root CA (`files/config/trusted-ca.pem`) in your browser's trust store.

### Solution: Configure PROXY TLS

The issue was that OCIS was using its self-generated self-signed certificate by default. To use the internal CA certificate:

```yaml
environment:
  # Enable TLS for proxy
  - PROXY_ENABLE_TLS=true
  # Point to the certificate
  - PROXY_TRANSPORT_TLS_CERT=/etc/ocis/server.crt
  - PROXY_TRANSPORT_TLS_KEY=/etc/ocis/server.key
```

Also ensure TLS passthrough is enabled in Traefik:

```yaml
labels:
  - 'traefik.tcp.routers.ocis.tls.passthrough=true'
```

### Important: Clean Restart Required

When changing Traefik labels (especially TCP vs HTTP), always do a full restart:

```bash
docker stop files && docker rm files
cd /home/vitor/nextjs-app-template/devops/files
/tmp/docker-compose --env-file secrets.env up -d
```

Cached router configurations can cause 404 errors if both TCP and HTTP routers coexist.

Also ensure TLS passthrough is enabled in Traefik:

```yaml
labels:
  - 'traefik.tcp.routers.ocis.tls.passthrough=true'
```
