# OCIS Files Integration Issues

## Current Problem

OCIS returns 500 on `/ocs/v2.php/cloud/capabilities` after OIDC login from Authentik.

## Root Cause

LDAP bind failures - OCIS can't authenticate to its internal IDM service to create users.

## Error Log Sample

```
LDAP Result Code 49 "Invalid Credentials":
bind_dn: uid=reva,ou=sysusers,o=libregraph-idm
```

## Issues Discovered

### 1. LDAP Bind DN Mismatch

- **Problem**: Graph service defaults to `uid=libregraph,ou=sysusers,o=libregraph-idm` but this user doesn't exist in IDM
- **Fix Applied**: Added `OCIS_LDAP_BIND_DN=uid=reva,ou=sysusers,o=libregraph-idm` and `OCIS_LDAP_BIND_PASSWORD=${OCIS_IDM_REVA_PASSWORD}`
- **Status**: Fix added to docker-compose.yaml but container needs recreate

### 2. GRAPH_LDAP_BIND_PASSWORD Override

- **Problem**: `GRAPH_LDAP_BIND_PASSWORD` was set to `${OCIS_IDM_IDM_PASSWORD}` instead of `${OCIS_IDM_REVA_PASSWORD}`
- **Fix Applied**: Changed to use REVA password
- **Status**: Fix added to docker-compose.yaml but container needs recreate

### 3. Container Not Recreated

- **Problem**: Changes to docker-compose.yaml not applied because container wasn't recreated
- **Required Action**: Run `docker compose up -d --force-recreate`

## Current Status

- `PROXY_AUTOPROVISION_ACCOUNTS=true` enabled
- `GRAPH_LDAP_SERVER_WRITE_ENABLED=true` enabled
- LDAP bind configured to use `reva` user

## Issue

User "vitor" not found - need to recreate container to apply latest config

## docker-compose.yaml Changes Made

- Line 17: `OCIS_INSECURE=false`
- Line 122: `# - OCIS_EXCLUDE_RUN_SERVICES=idp` (commented out)
- Line 111: `PROXY_AUTOPROVISION_ACCOUNTS=true`
- Line 117: `GRAPH_LDAP_SERVER_WRITE_ENABLED=true`
- Lines 44-48: LDAP bind settings for reva user

## Next Steps

1. Run: `cd /home/vitor/nextjs-app-template/devops/files && docker-compose up -d --force-recreate`
2. Test login at https://files.home2500.local

## Env Vars Expected in Container

After recreate, verify:

- `OCIS_LDAP_BIND_PASSWORD` should equal `IDM_REVA_PASSWORD`
- `GRAPH_LDAP_BIND_PASSWORD` should equal `IDM_REVA_PASSWORD`
