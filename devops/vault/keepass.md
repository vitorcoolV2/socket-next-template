# KeePass Documentation (`keepass.sh`)

The `keepass.sh` script is a specialized Bash library that wraps `keepassxc-cli` to provide secure, automated secret management for the Home2500 ecosystem. It acts as the "Offline Source of Truth" before secrets are synchronized to HashiCorp Vault.

## 🔒 Session Security Architecture

To avoid repeated password prompts while maintaining security, the library implements a **Watcher Singleton** pattern:

1.  **Runtime Directory**: Creates a private directory in `/run/user/$UID/home2500/` (RAM-backed `tmpfs`) to store temporary session data.
2.  **Session File**: Stores the master password in a strictly protected file (`600` permissions) during the active session.
3.  **Automatic Cleanup**: A background "Watcher" process (`wrapper_lock`) monitors the parent shell. When the shell exits or is killed, it immediately executes `shred` on the session file to ensure no traces remain in RAM or disk.

## 🛠️ Core Functions

### Session Management

- **`kp open`**: Initializes the session. Prompts for the master password if not already active.
- **`kp close`**: Manually destroys the session file and terminates the watcher.
- **`kp test`**: Runs a diagnostic suite to verify DB connectivity and session health.

### High-Level Helpers

- **`kp_get_entry_value <path>`**: Silently retrieves a password for programmatic use.
- **`kp_save_entry <path> <value>`**: Idempotent entry creation. Automatically creates parent groups using `kp_mkdir_p`.
- **`kp_save_approle <path> <role_id> <secret_id>`**: Specialized helper for Vault AppRole credentials (RoleID in username, SecretID in password).
- **`kp_save_ca_pair <path> <cert> <key>`**: Saves PKI pairs. The Private Key is stored as the entry password, and the full Certificate is added as a KeePass attachment.
- **`kp_mkdir_p <path>`**: Recursive group creation (mimics `mkdir -p` behavior inside the `.kdbx`).

## 🚀 Ecosystem Integration

The `keepass.sh` library is a low-level dependency used by:

1.  **`boot-sequence.sh`**: To unlock the master database at the start of the stack boot.
2.  **`vault_lib.sh`**: To synchronize local secrets (Authentik DB passwords, OIDC secrets, etc.) from KeePass into Vault's K/V engine.
3.  **`core.sh`**: Provides the base `core_secret_*` functions that abstract whether a secret comes from KeePass, Vault, or Memory.

## 📝 Configuration Requirements

The library requires the following environment variables (typically defined in `devops/.env`):

| Variable         | Description                                                  |
| :--------------- | :----------------------------------------------------------- |
| `KP_DB`          | Absolute path to the `.kdbx` file.                           |
| `KP_KEY`         | (Optional) Path to the `.key` file for 2FA.                  |
| `KP_OPEN_POLICY` | `block` (default) or `create` (auto-generate DB if missing). |

## 💻 Example Usage

```bash
source devops/vault/keepass.sh

# Programmatically fetch a secret
DB_PASS=$(kp_get_entry_value "infrastructure/postgres/admin")

# Save a new secret with auto-group creation
kp_save_entry "services/myapp/api_key" "super-secret-123"
```
