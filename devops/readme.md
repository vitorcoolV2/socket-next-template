# Devops Stack

## Naming Convention

All services follow: `<service>.<DOMAIN>`

```
DOMAIN=home2500.local
PUBLIC_SERVICES_LIST="traefik vault vault-oidc auth whoami mailcrab pihole backup netdata filebrowser fotos"
```

Generated names: `traefik.home2500.local`, `vault.home2500.local`, `auth.home2500.local`, etc.

## Service Workflow

### 1. DNS → Pi-hole

- `ph api dns sync` - registers all `<service>.<DOMAIN>` entries in Pi-hole

### 2. TLS Cert → Traefik

- Traefik requests TLS certificates from Vault for each `<service>.<DOMAIN>`

### 3. OIDC → Authentik

- Authentik registers OIDC clients for protected services

## Tool Stages

**Provision:**

```
script → provision_db → provision_secrets → vault_login → compose → running → name_register → authentik_login → blue_apply
```

**Teardown:**

```
outpost_remove → blue_clean → authentik_logout → stop → vault_logout → names_unregister
```

## Entrypoint

- `core.sh` - main library (source it, don't run directly)
- `boot-sequence.sh` - boots all services in order

## Starting Services

### Full Boot (all services)

```bash
./boot-sequence.sh
```

Boot sequence:

1. Docker network reset
2. **Pihole** → starts first (DNS needed)
3. **Vault** → unseals and gets token
4. **Pihole DNS sync** → registers all `<service>.$DOMAIN`
5. **Traefik** → starts with TLS
6. **Authentik** → starts, generates API token
7. **Wait for auth** → ensures auth is ready
8. **Set Authentik theme**
9. **Stack services** → netdata, backup, fotos

### Single Service

```bash
# Pihole
cd pihole && docker compose up -d

# Vault
cd vault && docker compose up -d

# Traefik
source traefik/_0.traefik_lib.sh && tk_up

# Authentik
source authentik/_0-authentik_lib.sh && ak_up

# Client app (netdata, backup, fotos, etc.)
cd <service> && source tool.sh && app_up_template__proxy
```

## KeePass

Used for storing secrets (passwords, certificates, keys).

### Config

```bash
KP_DB="/home/vitor/Documents/home2500.kdbx"      # Database path
KP_KEY="/media/vitor/Ventoy/home2500.key"        # Key file (optional)
KP_OPEN_POLICY="create"                          # create|block
```

### Usage

```bash
source vault/keepass.sh

kp open                   # Open database (unlocks with kp or KP_KEY)
kp ls                     # List entries
kp show <entry>           # Show entry details
kp clip <entry>           # Copy password to clipboard
kp get-entry-pass <path>  # Get password (programmatic)
kp get-entry-user <path>  # Get username
kp save-entry <path> <user> <pass>  # Save entry
kp save-ca-pair <path> <cert> <key> # Save cert + key
```

## Pi-hole

DNS and ad-blocking service.

### Usage

```bash
source pihole/_0.pihole_lib.sh

ph_api open        # Open KeePass and restore password
ph_api auth        # Authenticate to Pi-hole API
ph_api close       # Logout

ph_api dns get_records      # List DNS records
ph_api dns add <ip> <host> # Add DNS entry
ph_api dns remove <host>   # Remove DNS entry
ph_api dns sync            # Sync all <service>.$DOMAIN entries
ph_api dns expected        # Show expected DNS records

ph_api password rotate     # Rotate web password
```

### DNS Sync

`sync` compares expected vs actual and:

- Removes: entries in Pi-hole but not in expected
- Adds: entries in expected but not in Pi-hole
