# Authentik Issues & TODO

## Active Issues

### 2026-03-30: provision_user Stage - ✅ DONE

- Created blueprint template: `devops/authentik/app/blueprints/user--ROLE--NAME.yaml`
- Added `_provision_user__requirements()` function to tool.sh
- Added to TOOL_STAGES before vault_login
- User `aiai-bot` created successfully in Authentik via blueprint

---

### 2026-03-30: Vault bot-policy for provision_oidc

**Status**: ✅ DONE (needs to run)

- Updated bot-policy in `vault/_2-vault-policies.sh` with full secret create permissions
- Need to run: `cd devops/vault && ./_2-vault-policies.sh`

**Required For**: Auto-creating `chat/OIDC_ID` and `chat/OIDC_SECRET` in Vault

---

### 2026-03-29: Development User Creation

**Status**: ✅ DONE

- User `aiai-bot` created in Authentik
- Can log in to chat via OIDC

---

## TODO Items

### 1. Apply Development User Blueprint

**Status**: TODO

```bash
# Copy blueprint to Authentik
docker cp devops/authentik/blueprints/blueprint-home2500-developer.yaml \
   authentik-server:/blueprints/blueprint-home2500-developer.yaml

# Or if using volume mount, copy to volume
```

### 2. Create API Token

**Status**: TODO

- Go to: https://auth.home2500.local/-/admin/core/token/add/
- Create token for developer-bot user

### 3. Store Token in KeePass

**Status**: TODO

- Entry: `authentik/AUTHENTIK_API_TOKEN`
- Username: `developer-bot`
- Password: `<token>`

### 4. Test tool.sh with Chat App

**Status**: TODO

Add to chat .env:

```env
APP_USER_NAME=bot
APP_USER_ROLE=developer
APP_USER_EMAIL=developer@home2500.local
```

Then run:

```bash
cd devops/chat
source init.sh
```

### 5. Test provision_user Stage

**Status**: TODO

The provision_user stage should run automatically when APP_USER_NAME is set in .env

---

## Completed

### 2026-03-28: Initial Authentik Setup

**Status**: ✅ RESOLVED

- Authentik deployed with Docker Compose
- Groups created: Home-Admins, Home-Developers, Home-Users
- Applications configured: pihole, traefik, mailcrab, whoami, vault
- Outpost embedded configured

### 2026-03-28: Steward Token

**Status**: ✅ RESOLVED

- steward-automation-token exists in database
- Token key: `QhGJtmPAtAhvcpXAqQv17Ff1wKGXqvUmheKs2mvyjzBh6muz6wtmu7WhunPh`

---

## Notes

### Using Development User vs Steward

| Operation                              | Token                         |
| -------------------------------------- | ----------------------------- |
| Create new app OIDC secrets            | developer                     |
| Apply blueprints                       | developer-bot (Authentik API) |
| Create database credentials            | steward (Vault)               |
| System app secrets (authentik, pihole) | steward (Vault)               |

### Blueprint Discovery

Authentik auto-discovers blueprints in:

- `/blueprints` directory (container path)
- Configured via `AUTHENTIK_BLUEPRINTS_DIR` environment variable
