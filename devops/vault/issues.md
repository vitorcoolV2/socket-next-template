# Vault Issues

## Active Issues

### 2026-03-29: Missing developer-role AppRole

**Problem**: tool.sh fails with "AppRole credentials not found" when trying to provision client apps

**Root Cause**: Only steward-role exists, no developer-role configured for development work

**Required For**: Running `devops/authentik/app/tool.sh` for client app OIDC provisioning

**Status**: TODO - Run `_2-vault-policies.sh` to create developer-role

**Solution**:

```bash
cd devops/vault
./_2-vault-policies.sh

# Get credentials
vault read auth/approle/role/developer-role/role-id
vault write -f auth/approle/role/developer-role/secret-id

# Store in KeePass at: vault/AppRole/developer-role
# - Username: role_id
# - Password: secret_id
```

---

## Resolved Issues

### 2026-03-28: Initial Vault Setup

**Status**: ✅ Resolved

- Vault initialized with root token
- PKI intermediate CA configured
- Steward role created
