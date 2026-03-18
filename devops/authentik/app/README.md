# Authentik App Framework

This directory contains the core framework (`tool.sh`) used by client applications to integrate with the Home2500 stack (SSO, DNS, Database, Secrets).

## Purpose

The `tool.sh` library provides a standardized lifecycle for deploying services. Instead of writing complex deployment scripts for every app, you create a simple `init.sh` that utilizes this framework.

## The Deployment Pipeline (Stages)

When you run a deployment, the tool executes these stages:

1.  **`script`**: Validates that your app has a `deploy` function.
2.  **`provision_db`**: If `APP_DB_NAME` is defined in `.env`, it creates the Postgres DB and 3 roles (admin, rw, ro).
3.  **`provision_secrets`**: Maps global secrets (e.g., Redis password) to your app's local secrets.
4.  **`compose`**: Injects all secrets and runs `docker compose up -d`.
5.  **`running`**: Verifies the container is up and has an IP.
6.  **`name_register`**: Registers the service in Pi-hole DNS.
7.  **`authentik_login`**: Ensures the Authentik API is ready.
8.  **`blue_apply`**: Compiles and applies the Authentik Blueprint (Proxy or OIDC).
9.  **`outpost_add`**: Connects the service to the Traefik Outpost (if using proxy mode).

## Scaffolding a New Service

1.  **Create Directory**: `devops/my-app/`
2.  **Create Compose**: `devops/my-app/docker-compose.yaml`
3.  **Create Init Script**:
    ```bash
    cp devops/authentik/app/script_provision/CLIENT_APP_NAME--base-init.sh devops/my-app/init.sh
    ```
4.  **Configure**: Create `.env` with `APP_` variables.

## Configuration (`.env`)

Variables prefixed with `APP_` are automatically transformed to `CLIENT_APP_` for the framework:

| Variable                   | Description             | Default        |
| :------------------------- | :---------------------- | :------------- |
| `APP_CONTAINER_NAME`       | Name in docker-compose  | Directory name |
| `APP_BLUE_GROUP`           | UI Group in Authentik   | `Ferramentas`  |
| `APP_BLUE_TEMPLATE_MODULE` | `proxy` or `oidc`       | `proxy`        |
| `APP_DB_NAME`              | Database name to create | —              |

## Database Provisioning

For every `APP_DB_NAME`, the following roles are created:

- `db_<name>__role_admin`: Full permissions.
- `db_<name>__role_rw`: Read/Write permissions.
- `db_<name>__role_ro`: Read-only permissions.

## Blueprints

Templates are located in `./blueprints/`.

- **Proxy Mode**: Uses `CLIENT_APP_NAME--apply-proxy.yaml`. Suitable for apps without native OIDC.
- **OIDC Mode**: Uses `CLIENT_APP_NAME--apply-oidc.yaml`. Suitable for apps with native OIDC support (e.g., Immich).
