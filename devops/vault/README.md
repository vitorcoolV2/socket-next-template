# Vault & Secret Management

The Home2500 stack uses KeePass (`.kdbx`) as the primary offline source of truth for secrets, which are then synchronized to HashiCorp Vault for runtime access and OIDC integration.

## 📖 Modules

| Module                          | Description                                                               |
| :------------------------------ | :------------------------------------------------------------------------ |
| **[KeePass Guide](keepass.md)** | `keepass.sh`: Wrapper library for secure session-based secret management. |
| **[Vault Lib](vault_lib.sh)**   | Core library for Vault unsealing, authentication, and OIDC orchestration. |

## Configuration

The following variables define the KeePass environment:

```bash
KP_DB="/home/vitor/Documents/home2500.kdbx"      # Database path
KP_KEY="/media/vitor/Ventoy/home2500.key"        # Key file (optional)
KP_OPEN_POLICY="create"                          # create|block
```

## Usage

Source the library to enable commands:

```bash
source devops/vault/keepass.sh

kp open                   # Open database (unlocks with kp or KP_KEY)
kp ls                     # List entries
kp show <entry>           # Show entry details
kp clip <entry>           # Copy password to clipboard
kp get-entry-pass <path>  # Get password (programmatic)
kp get-entry-user <path>  # Get username
kp save-entry <path> <user> <pass>  # Save entry
kp save-ca-pair <path> <cert> <key> # Save cert + key
```

## Secret Flow

1.  **KeePass**: Manual entry of passwords/keys.
2.  **Vault**: `core.sh` syncs KeePass entries to Vault during the boot sequence.
3.  **Runtime**: Services (Traefik, Authentik, Apps) fetch secrets from Vault or Mem-storage via `core_secret_service_get`.

## Roles

Home2500 uses a role-based access control system for Vault:

| Role               | Purpose                    | TTL | Capabilities                            |
| ------------------ | -------------------------- | --- | --------------------------------------- |
| **steward-role**   | Full admin                 | 4h  | All secrets, PKI, Auth                  |
| **developer-role** | App provisioning (tool.sh) | 24h | R/W OIDC secrets, read Authentik tokens |
| **user-role**      | Read assigned secrets      | 24h | Read home2500/\* secrets                |
| **guest-role**     | Public secrets only        | 24h | Read public/\* only                     |

### Setup Roles

Run the policy creation script:

```bash
cd devops/vault
./_2-vault-policies.sh
```

### Getting Credentials

After creating a role, get the AppRole credentials:

```bash
# Developer role
vault read auth/approle/role/developer-role/role-id
vault write -f auth/approle/role/developer-role/secret-id
```

### Storing in KeePass

Store AppRole credentials at: `vault/AppRole/<role-name>`

| Entry                          | Username | Password  |
| ------------------------------ | -------- | --------- |
| `vault/AppRole/steward-role`   | role_id  | secret_id |
| `vault/AppRole/developer-role` | role_id  | secret_id |
| `vault/AppRole/user-role`      | role_id  | secret_id |
| `vault/AppRole/guest-role`     | role_id  | secret_id |

## Policy Definitions

### developer-policy (for tool.sh)

Required for running `devops/authentik/app/tool.sh` to provision client apps:

```hcl
# OIDC credentials for any app
path "secret/data/*/OIDC_*" { capabilities = ["create", "read", "update", "list"] }

# Database passwords (read)
path "secret/data/*/DATABASE_*" { capabilities = ["read", "list"] }
path "secret/data/*/POSTGRES_*" { capabilities = ["read", "list"] }

# Redis passwords (read)
path "secret/data/*/REDIS_*" { capabilities = ["read", "list"] }

# Authentik tokens (read)
path "secret/data/authentik/*" { capabilities = ["read", "list"] }
```
