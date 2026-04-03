# Authentik Blueprint Management

The `_1-blueprints_lib.sh` library provides advanced management for Authentik Blueprints, template variable injection, and automated OIDC provisioning.

## Core Capabilities

### 1. Blueprint Lifecycle

- **`blue_apply <file>`**: Validates and applies a YAML blueprint to the Authentik API. It handles both creation and patching of existing blueprints.
- **`blue_delete <file>`**: Removes a blueprint and its associated configuration from Authentik.
- **`blue_template_list`**: Lists and validates all blueprint files in the `devops/authentik/blueprints/` directory.

### 2. Template Variable Injection

The system supports a powerful template engine that uses standard `{{VAR}}` syntax.

- **`blue_template_vars <template> <target>`**:
  1. Scans the template for `{{VAR}}` placeholders.
  2. Validates that the corresponding environment variables exist.
  3. Generates a final YAML file with all values injected.
  4. Automatically applies the correct permissions (`644`) so the Authentik container can read it.

### 3. Automated OIDC/Proxy Provisioning

- **`blue_authentik_oidc_provider <app_name>`**: Programmatically creates an OAuth2/OIDC provider with standard OIDC scopes and redirect URIs.
- **`blue_outpost_sync`**: Automatically finds all Proxy Providers and adds them to the Traefik Outpost, ensuring they are protected by the SSO edge layer.
- **`blue_vault_oidc_provider <app_name>`**: Orchestrates the integration between Authentik and HashiCorp Vault, setting up the OIDC mount, roles, and access policies.

## Integration Workflows

The blueprint system is typically used within a client app's `init.sh` through the **[App Framework](app/README.md)**.

Example flow:

```bash
# In devops/my-app/init.sh
source ../authentik/app/tool.sh

# This internally uses blue_template_vars and blue_apply
app_blue_apply
```

## Security and Validation

- **Idempotency**: All `blue_*` functions are designed to be idempotent. Running them multiple times will safely update existing configurations.
- **Validation**: `blue_file_valid` uses `yq` and `jq` to ensure YAML syntax and metadata (`metadata.name`, `metadata.slug`) are correct before sending data to the API.
