# Authentik Identity Management

This directory contains the central configuration and libraries for the Authentik identity provider in the Home2500 stack.

## Core Library: `_0-authentik_lib.sh`

The `_0-authentik_lib.sh` script is the primary backend library for Authentik management. It handles lifecycle, API token generation, and database-level fixes.

### Key Capabilities

- **Lifecycle Management**: `ak_up` and `ak_down` to manage the Docker stack.
- **API Token Automation**: `ak_api_token_generate` creates an idempotent superuser token directly via the Authentik Python shell.
- **Security Fixes**: `ak_fix_proxied_redir` applies SQL-level fixes to provider redirect URIs and proxy modes.
- **Health Checks**: `ak_api_token_validate` and `ak_system_health` provide diagnostic insights.

## Documentation Index

| Module                              | Description                                                         |
| :---------------------------------- | :------------------------------------------------------------------ |
| **[Blueprints](blueprints.md)**     | `_1-blueprints_lib.sh`: Blueprint management and OIDC provisioning. |
| **[App Framework](app/README.md)**  | Tool for onboarding new client applications with SSO.               |
| **[Theme System](theme/README.md)** | Custom branding, UI assets, and theme-toggle JS.                    |

## Quick Commands

```bash
# Load the library
source devops/authentik/_0-authentik_lib.sh

# Status check
ak_system_health

# Generate new API token (if expired)
ak_api_token_generate
```

## Internal Files

- `docker-compose.yml`: Core service definition (Server, Worker, DB, Redis).
- `_9-nuke-and-rebuild.sh`: Recovery script for total system reset.
