# Devops Stack

Welcome to the Home2500 Devops Stack. This project manages the lifecycle of self-hosted services using Docker, Traefik, Authentik, and Vault.

## 📖 Service Documentation Index

| Service             | Documentation                                          | Core Responsibility                             |
| :------------------ | :----------------------------------------------------- | :---------------------------------------------- |
| **Orchestration**   | [readme.md](readme.md)                                 | Global stack boot sequence & naming conventions |
| **Ecosystem**       | [home2500.md](home2500.md)                             | Core components & Blueprint relationships       |
| **Authentik**       | [authentik/README.md](authentik/README.md)             | Identity Provider (OIDC/SAML) & App Access      |
| **├ App Framework** | [authentik/app/README.md](authentik/app/README.md)     | Developer tool for service deployment & SSO     |
| **└ Theme**         | [authentik/theme/README.md](authentik/theme/README.md) | Custom branding & UI asset builder              |
| **Traefik**         | [traefik/README.md](traefik/README.md)                 | Reverse proxy, TLS (Vault), & Middlewares       |
| **Vault**           | [vault/README.md](vault/README.md)                     | Secret storage & Vault unsealing orchestration  |
| **└ KeePass**       | [vault/keepass.md](vault/keepass.md)                   | Wrapper library for secure secret management    |
| **Pi-hole**         | [pihole/README.md](pihole/README.md)                   | Network-wide DNS & API sync                     |
| **Backup**          | [backup/README.md](backup/README.md)                   | Automated backups via Backrest                  |
| **Fotos**           | [fotos/README.md](fotos/README.md)                     | Immich photo management                         |
| **OpenCode**        | [opencode/readme.md](opencode/readme.md)               | AI Code Assistant                               |

---

## Naming Convention

All services follow: `<service>.<DOMAIN>`

```bash
DOMAIN=home2500.local
PUBLIC_SERVICES_LIST="traefik vault vault-oidc auth whoami mailcrab pihole backup netdata filebrowser fotos"
```

Generated names: `traefik.home2500.local`, `vault.home2500.local`, `auth.home2500.local`, etc.

## Service Workflow

### 1. DNS → Pi-hole

Records are registered in Pi-hole to point to the Traefik IP.

### 2. TLS Cert → Traefik

Traefik requests TLS certificates from Vault for each service domain.

### 3. OIDC/SSO → Authentik

Authentik handles user authentication and authorization for all protected services.

## Tool Stages

**Provision:**
`script` → `provision_db` → `provision_secrets` → `vault_login` → `compose` → `running` → `name_register` → `authentik_login` → `blue_apply`

**Teardown:**
`outpost_remove` → `blue_clean` → `authentik_logout` → `stop` → `vault_logout` → `names_unregister`

## Entrypoints

- `core.sh`: Main library (source it, don't run directly).
- `boot-sequence.sh`: Automated script to boot all services in order.

## Starting Services

### Full Boot (all services)

```bash
./boot-sequence.sh
```

### Single Service

```bash
# Core Services (Manual)
cd pihole && docker compose up -d
cd vault && docker compose up -d

# Using Libraries
source traefik/_0.traefik_lib.sh && tk_up
source authentik/_0-authentik_lib.sh && ak_up

# Client Apps (using the framework)
cd <service> && source init.sh && deploy
```
