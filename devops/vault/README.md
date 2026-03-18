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
