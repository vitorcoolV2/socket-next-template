# Chat Init Report

## Overview

`init.sh` is the client initialization library for the Chat stack (Open WebUI + Ollama).

## Usage

```bash
# Source the init script
source devops/chat/init.sh

# Deploy the stack
deploy

# Provision secrets
provision_secrets

# Deploy secrets to memory
deploy_secrets

# List all functions
funcs

# Reset secrets
reset_secret
```

## Environment Variables Mapping

The `authentik/app/tool.sh` transforms `.env` variables:

| .env Variable             | CLIENT*APP*\* Variable           | Example Value                     |
| ------------------------- | -------------------------------- | --------------------------------- |
| APP_BLUE_GROUP            | CLIENT_APP_BLUE_GROUP            | Ferramentas                       |
| APP_CONTAINER_NAME        | CLIENT_APP_CONTAINER_NAME        | chat                              |
| APP_SERVICE_PORT          | CLIENT_APP_SERVICE_PORT          | 8080                              |
| APP_BLUE_LABEL            | CLIENT_APP_BLUE_LABEL            | ChatAI                            |
| APP_BLUE_META_DESCRIPTION | CLIENT_APP_BLUE_META_DESCRIPTION | Home internal chat ai service     |
| APP_BLUE_TEMPLATE_MODULE  | CLIENT_APP_BLUE_TEMPLATE_MODULE  | oidc                              |
| APP_WAIT_RETRY            | CLIENT_APP_WAIT_RETRY            | 15                                |
| (derived)                 | CLIENT_APP_NAME                  | chat (basename of CLIENT_APP_DIR) |

## Functions

### Main Functions

| Function              | Description                                                |
| --------------------- | ---------------------------------------------------------- |
| `deploy()`            | Main deployment - calls `app_up` from tool.sh              |
| `provision_secrets()` | Provisions secrets: WEBUI_SECRET_KEY, OIDC_ID, OIDC_SECRET |
| `deploy_secrets()`    | Deploys secrets from Vault → mem → .secret file            |
| `reset_secret()`      | Clears all secrets from Vault, Keepass, and mem            |
| `funcs()`             | Lists all available functions                              |

### Error Handlers (Callbacks)

| Function                      | Trigger                      |
| ----------------------------- | ---------------------------- |
| `on_vault_login_fail()`       | Vault login fails            |
| `on_script_fail()`            | Script execution fails       |
| `on_login_fail()`             | Credential validation fails  |
| `on_provision_secrets_fail()` | Secret provisioning fails    |
| `on_deploy_secrets_fail()`    | Secret deployment fails      |
| `on_provision_oidc_fail()`    | OIDC provisioning fails      |
| `on_expose_fail()`            | Traefik exposure fails       |
| `on_name_register_fail()`     | Name registration fails      |
| `on_authentik_login_fail()`   | Authentik login fails        |
| `on_blue_apply_fail()`        | Blueprint application fails  |
| `on_running_fail()`           | Container health check fails |
| `on_compose_fail()`           | Docker compose fails         |

### Internal Functions

| Function                    | Description                                          |
| --------------------------- | ---------------------------------------------------- |
| `_export_secrets_to_file()` | Exports secrets to `.secret` file for Docker Compose |
| `context()`                 | Validates required environment variables             |

## Secrets Flow

```
provision_secrets()
    │
    ├─► KeePass ──► Vault ──► mem
    │   (if exists)    (sync)
    │
    └─► Generate if missing:
        ├─ OIDC_ID     → UUID
        ├─ OIDC_SECRET → openssl rand -hex 32
        └─ WEBUI_SECRET_KEY → openssl rand -hex 32

deploy_secrets()
    │
    ├─► Vault ──► mem (tool_provision__secret_vars)
    │
    └─► mem ──► .secret file (core_secret_export2_env_vars)
```

## Secrets Managed

| Secret           | Type          | Description               |
| ---------------- | ------------- | ------------------------- |
| WEBUI_SECRET_KEY | hex (64 char) | Open WebUI session secret |
| OIDC_ID          | UUID          | OIDC Client ID            |
| OIDC_SECRET      | hex (64 char) | OIDC Client Secret        |

## .secret File

After `deploy_secrets()`, the following file is created:

```
/run/user/1000/home2500/chat/.secret
```

Contents:

```bash
CLIENT_ID=open-webui
CLIENT_SECRET=<OIDC_SECRET>
WEBUI_SECRET_KEY=<WEBUI_SECRET_KEY>
```

## Required Context Variables

For `context()` validation:

- INTERNAL_DOMAIN
- DOMAIN
- CLIENT_APP_NAME
- CLIENT_APP_DIR
- CLIENT_APP_BLUE_LABEL
- CLIENT_APP_BLUE_GROUP
- CLIENT_APP_SERVICE_PORT
- CLIENT_APP_BLUE_APPLY_TPL
- CLIENT_APP_BLUE_CLEANUP_TPL
- CLIENT_APP_BLUE_APPLY
- CLIENT_APP_BLUE_CLEANUP
- CLIENT_APP_COMPOSE_FILE

## History

| Date       | Change                                            |
| ---------- | ------------------------------------------------- |
| 2026-03-29 | Initial report created                            |
| 2026-03-29 | Added OIDC_ID, OIDC_SECRET to provision_secrets   |
| 2026-03-29 | Fixed copy/paste error (Stack Fotos → Stack Chat) |
