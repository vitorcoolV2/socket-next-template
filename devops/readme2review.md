# Vault, Authentik & Blueprints Libraries

## vault/vault_lib.sh

Secrets management with PKI and TLS certificates.

### Config

```bash
source vault/vault_lib.sh
```

### Functions

| Function                                   | Description                     |
| ------------------------------------------ | ------------------------------- |
| `vault_config_requirements()`              | Load vault config, TLS settings |
| `is_sealed()`                              | Check if vault is sealed        |
| `is_initialized()`                         | Check if vault is initialized   |
| `vault_up()`                               | Start vault container           |
| `vault_down()`                             | Stop vault container            |
| `vault_unseal()`                           | Unseal vault with keys          |
| `vault_request_stew_token()`               | Get steward token from KeePass  |
| `vault_validate_token()`                   | Validate current token          |
| `vault_request_root_token()`               | Get root token                  |
| `vault_logout()`                           | Clear vault token               |
| `vault_get_secret <path> <field>`          | Read secret                     |
| `vault_save_secret <path> <field> <value>` | Write secret                    |
| `vault_create_home_server_role()`          | Create PKI role                 |
| `vault__self_certificate()`                | Generate self-signed cert       |
| `vault_switch <http\|https>`               | Switch between HTTP/HTTPS       |

### Usage

```bash
# Start and unseal
vault_up
is_sealed && vault_unseal

# Get token
vault_request_stew_token

# Secrets
vault_get_secret "secret/path" "password"
vault_save_secret "secret/path" "password" "mysecret"
```

---

## authentik/\_0-authentik_lib.sh

Identity provider (OIDC/OAuth2).

### Functions

| Function                                 | Description                |
| ---------------------------------------- | -------------------------- |
| `ak_up()`                                | Start authentik containers |
| `ak_down()`                              | Stop authentik             |
| `ak_wait4_instance()`                    | Wait for admin user ready  |
| `ak_internal_service_ready()`            | Check API ready            |
| `ak_oidc_service_ready()`                | Check OIDC ready           |
| `ak_api_token_generate()`                | Generate API token         |
| `ak_api_token_validate()`                | Validate token             |
| `ak_api_token_restore()`                 | Restore from KeePass       |
| `ak_api_call <method> <endpoint> <data>` | Raw API call               |
| `ak_fix_proxied_redir()`                 | Fix redirect URIs          |
| `ak_secrets_show()`                      | Show configured secrets    |
| `ak_secrets_compose_get()`               | Get compose secrets        |
| `ak_theme_dark()`                        | Set dark theme             |
| `ak_theme_light()`                       | Set light theme            |
| `ak_login()`                             | Login to UI                |
| `ak_logout()`                            | Logout                     |
| `ak_reset()`                             | Reset authentik            |
| `ak_reboot()`                            | Restart containers         |
| `ak_system_health()`                     | Health check               |

### Usage

```bash
source authentik/_0-authentik_lib.sh

# Start
ak_up
ak_wait4_instance

# Token
ak_api_token_generate

# OIDC check
ak_oidc_service_ready
```

---

## authentik/\_1-blueprints_lib.sh

Blueprints for provisioning OIDC clients and proxies.

### Functions

| Function                               | Description               |
| -------------------------------------- | ------------------------- |
| `enable_oidc_well_known_openid_flow()` | Enable OIDC provider      |
| `check_well_known_openid_config()`     | Verify OIDC config        |
| `blue_authentik_oidc_provider()`       | Setup authentik OIDC      |
| `blue_vault_oidc_provider()`           | Setup vault OIDC          |
| `blue_template_list()`                 | List blueprints           |
| `blue_template_inject_vars()`          | Inject vars into template |
| `blue_file_valid()`                    | Validate blueprint file   |
| `blue_folder_valid_entries()`          | Validate folder           |
| `blue_template_vars()`                 | Show template vars        |
| `blue_template_extract_arguments()`    | Extract args              |
| `blue__get_current_json()`             | Get current app JSON      |
| `blue__get_all_json()`                 | Get all blueprints        |
| `blue__get_home2500_json()`            | Get home2500 blueprints   |
| `blue_apply()`                         | Apply blueprint           |
| `blue_delete()`                        | Delete blueprint          |
| `blue_outpost_add_provider()`          | Add outpost provider      |
| `blue_outpost_sync()`                  | Sync outpost              |
| `blue_outpost_remove_provider()`       | Remove provider           |

### Blueprints Template Variables

```bash
CLIENT_APP_NAME         # e.g., "netdata"
CLIENT_APP_NS          # namespace
CLIENT_APP_BLUE_LABEL  # UI label
CLIENT_APP_BLUE_GROUP  # UI group
CLIENT_APP_CONTAINER_NAME
```

### Usage

```bash
source authentik/_1-blueprints_lib.sh

# Check OIDC
check_well_known_openid_config

# Apply blueprint
blue_apply "blueprints/blueprint-home2500.yaml"

# Sync outpost
blue_outpost_sync
```

---

## Dependencies

```
vault/keepass.sh → vault/vault_lib.sh → authentik/_0-authentik_lib.sh → authentik/_1-blueprints_lib.sh
```

---

## traefik/\_0.traefik_lib.sh

Reverse proxy with automatic TLS from Vault PKI.

### Functions

| Function                           | Description                  |
| ---------------------------------- | ---------------------------- |
| `tk_show_desired_names()`          | Show desired TLS names       |
| `tk_need_renewal()`                | Check if cert renewal needed |
| `tk_renew_certs()`                 | Request new certs from Vault |
| `tk_test_tls <host>`               | Test TLS for a host          |
| `tk_is_service_ready <service>`    | Check if service ready       |
| `tk_wait4_service_ready <service>` | Wait for service             |
| `tk_check_renewal()`               | Check and renew if needed    |
| `tk_up()`                          | Start traefik container      |
| `tk_down()`                        | Stop traefik                 |
| `tk_logs()`                        | View traefik logs            |
| `tk_logs_cert_tls_error()`         | View TLS error logs          |
| `tk_test_authentik_outpost()`      | Test authentik outpost       |
| `tk_switch2_authentik_routes()`    | Switch to authentik routes   |
| `tk_switch2_unprotected_routes()`  | Switch to unprotected routes |

### Certs Location

```
TRAEFIK_CERT_DIR/traefik/certs/
  - traefik-fullchain.pem
  - traefik.key
  - ca-chain.pem
```

### Usage

```bash
source traefik/_0.traefik_lib.sh

# Check if renewal needed
tk_need_renewal

# Renew certs from Vault
tk_renew_certs

# Wait for service
tk_wait4_service_ready "whoami"

# Start
tk_up

# Logs
tk_logs
```
