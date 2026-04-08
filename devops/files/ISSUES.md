# OCIS Files Integration Issues

## Current Status (2026-03-30)

### ✅ Working

- OCIS is running at https://files.home2500.local
- Health check passing: `/healthz` returns 200
- CSP disabled (handled at Traefik level via headers)
- LDAP write disabled (using service account instead)

### ❌ Current Problem

**Certificate trust issue** - OCIS browser can't access Authentik OIDC endpoint.

Browser error:

```
https://auth.home2500.local/application/o/files/.well-known/openid-configuration
[HTTP/2 404]
```

Works with curl -k (skip verify). Browser doesn't trust internal CA.

**Solutions:**

1. Install internal CA cert in browser/system
2. Add internal CA to system trust store

### Testing

Test at: https://files.home2500.local

## Traefik Integration - COMPLETED

OCIS now works through Traefik:

- OCIS runs in HTTP mode (PROXY_ENABLE_TLS=false)
- Traefik handles HTTPS termination
- Traefik config in `/home/vitor/nextjs-app-template/devops/traefik/traefik/config/`:
  - `dynamic.yml`: Contains ocis router (lines 115-120)
  - `_1-core-service.yml`: Contains ocis-service with insecure transport

### Access

- Direct: https://192.168.1.67 (with Host header: files.home2500.local)
- DNS: https://files.home2500.local (if DNS resolves to 192.168.1.67)

## CSP Configuration - BLOCKED

### Attempted Fix (FAILED)

- Updated `/home/vitor/nextjs-app-template/devops/files/config/csp.yaml` to include:
  - `connect-src`: Added `https://auth.home2500.local`, `http://auth.home2500.local`
  - `script-src`: Added `'unsafe-eval'`
  - `frame-src`: Added `http://auth.home2500.local`
- Added volume mount to docker-compose.yaml:
  ```yaml
  volumes:
    - ./config/csp.yaml:/etc/ocis/csp.yaml:ro
  ```
- Enabled CSP in environment:
  ```yaml
  - PROXY_CSP_CONFIG_FILE_LOCATION=/etc/ocis/csp.yaml
  ```

### Error

```
FTL Failed to load CSP configuration. error="read /etc/ocis/csp.yaml: is a directory"
```

### Root Cause

Docker is somehow mounting `./config/` directory instead of `./config/csp.yaml` file. This is a recurring issue with anonymous volumes or config hash caching.

### Current Status

CSP is DISABLED to allow OCIS to run. Need to investigate Docker volume mounting issue.

## Previous Issues (Partially Resolved)

### 1. LDAP Bind DN Mismatch - LIKELY RESOLVED

- **Problem**: Graph service defaults to wrong user
- **Fix Applied**: Added `OCIS_LDAP_BIND_DN=uid=reva,ou=sysusers,o=libregraph-idm` and `OCIS_LDAP_BIND_PASSWORD=${OCIS_IDM_REVA_PASSWORD}`

### 2. TLS Certificate - RESOLVED

- **Problem**: OCIS using self-signed certificate
- **Fix**: OCIS now uses HTTP mode, Traefik handles TLS

### 3. Traefik Routing - RESOLVED

- **Problem**: Browser getting wrong certificate
- **Fix**: Changed from TCP passthrough to HTTP router with Traefik TLS termination

## docker-compose.yaml Current Config

```yaml
services:
  ocis-server:
    image: owncloud/ocis:latest
    container_name: files
    restart: always
    networks:
      - app-network
    extra_hosts:
      - 'auth.home2500.local:192.168.1.67'
      - 'files.home2500.local:192.168.1.67'
    volumes:
      - ./data:/var/lib/ocis
      - /etc/localtime:/etc/localtime:ro
    ports:
      - '9200:9200'
    environment:
      - OCIS_URL=https://files.home2500.local
      - PROXY_ENABLE_TLS=false
      - PROXY_HTTP_ADDR=0.0.0.0:9200
      - OCIS_INSECURE=true
      - PROXY_INSECURE=true
      # CSP disabled - see above
```

## Next Steps

1. **Investigate CSP volume mount issue**
   - Try using named volume for config
   - Or mount csp.yaml to different path like `/etc/ocis/custom-csp.yaml`

2. **Test authentication**
   - Once CSP is fixed, test login with Authentik
   - Verify user provisioning works

3. **Add OCIS to Authentik**
   - Create application in Authentik if not exists
   - Set up OIDC provider
