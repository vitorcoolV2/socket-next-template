# Core Library Functions

Documentation for functions in `core.sh`.

## Secret Service Functions

### core_secret_service_get

```bash
core_secret_service_get "service/secret_name"
```

Retrieves a secret from the specified provider (mem, vault, or keepass).

**Providers**: `mem`, `vault`, `keepass` (set via `PROVIDER_SELECT`)

### core_secret_service_put

```bash
core_secret_service_put "service/secret_name" "secret_value"
```

Stores a secret in the specified provider.

### core_secret_service_delete

```bash
core_secret_service_delete "service/secret_name"
```

Deletes a secret from the provider.

### core_secret_mem_delete

```bash
core_secret_mem_delete "service/secret_name"
```

Securely deletes a secret from memory (shreds file before removal).

### core_secret_load_vars

```bash
core_secret_load_vars "provider://service/var_name" [...]
```

Loads secrets from a provider into memory. Example:

```bash
core_secret_load_vars "vault://authentik/API_TOKEN" "keepass://files/DB_PASSWORD"
```

### core_secret_export2_env_vars

```bash
core_secret_export2_env_vars "app/.secret" "VAR1" "VAR2" "VAR3"
```

Exports secrets to a `.secret` file as environment variables.

### core_secret_mapper_mem

```bash
core_secret_mapper_mem "service" "secret_name"
```

Returns the full path for a secret in memory: `$MEM_ROOT_DIR/service/secret_name`

### core_secret_mapper_vault

```bash
core_secret_mapper_vault "service" "secret_name"
```

Returns the Vault path: `secret/service/secret_name`

### core_secret_mapper_keepass

```bash
core_secret_mapper_keepass "service" "secret_name"
```

Returns the KeePass path: `$KEEPASS_ROOT_DIR/service/secret_name`

---

## File & Path Functions

### core_resolve_file

```bash
core_resolve_file "filename.sh"
```

Resolves a file path relative to DEVOPS_DIR. Strips `../` for security.

### core_relative_path2

```bash
core_relative_path2 "/full/path/to/file"
```

Returns relative path from DEVOPS_DIR.

### core_transform_inject_env_file_vars

```bash
core_transform_inject_env_file_vars ".env" "APP_" "CLIENT_APP_"
```

Reads an env file and exports variables with prefix transformation.

---

## Network Functions

### detect_active__interface

```bash
detect_active__interface
```

Detects the active network interface (default route interface).

### detect_active__ipv4

```bash
detect_active__ipv4
```

Returns the IPv4 address of the active interface.

### detect_active__ipv6

```bash
detect_active__ipv6
```

Returns the IPv6 address of the active interface.

### core_http_url_status

```bash
core_http_url_status "https://example.com"
```

Returns HTTP status code (200, 404, etc.) for a URL.

---

## URL Functions

### core_url_encode

```bash
core_url_encode "string to encode"
```

URL-encodes a string.

---

## Domain Functions

### core_set\_\_domain_name

```bash
core_set__domain_name "example.com"
```

Patches `/etc/hosts` with the domain pointing to the active interface IP.

### core_get\_\_domain_name

```bash
core_get__domain_name
```

Reads the current DOMAIN from `/etc/hosts` or environment.

### core_desired_domain_names_json

```bash
core_desired_domain_names_json
```

Returns JSON array of domain names from configuration.

### core**container_name**url

```bash
core__container_name__url "container-name"
```

Generates URL candidates for a container name.

---

## JSON Functions

### core_search_file_json

```bash
core_search_file_json "query" "file.json"
```

Searches JSON file with jq-like queries.

### core_fn_json

```bash
core_fn_json "operation" "file.json"
```

Performs JSON operations (jq wrapper).

### core_fn_sort_json

```bash
core_fn_sort_json "file.json" "key"
```

Sorts JSON array by key.

### core_fn_sort_weights

```bash
core_fn_sort_weights "file.json"
```

Sorts items by weight field in JSON.

### core_fn_catalog

```bash
core_fn_catalog "directory/"
```

Generates catalog JSON from directory contents.

---

## Utility Functions

### sanitize_path_name

```bash
sanitize_path_name "input/path"
```

Sanitizes path names (allows `/`, `.`, `-`, `_`).

### sanitize_var_name

```bash
sanitize_var_name "var-name"
```

Sanitizes variable names (converts `.` and `-` to `_`).

### sanitize_db_name

```bash
sanitize_db_name "db-name"
```

Sanitizes database names (lowercase, alphanumeric only).

### to_pascal_case

```bash
to_pascal_case "input_string"
```

Converts string to PascalCase.

### core_load_requirements

```bash
core_load_requirements "requirement1" "requirement2"
```

Validates that requirements are met before proceeding.

---

## Variables

### PROVIDER_SELECT

Used to specify which secret provider to use:

- `mem` - In-memory secrets (fastest)
- `vault` - HashiCorp Vault
- `keepass` - KeePass file
- Combined: `vault keepass` (tries vault first, then keepass)

### MEM_ROOT_DIR

Base directory for in-memory secrets (e.g., `/run/user/1000/home2500`)

### VAULT_ROOT_DIR

Base path for Vault secrets (e.g., `secret/`)

### KEEPASS_ROOT_DIR

Base directory for KeePass file structure
