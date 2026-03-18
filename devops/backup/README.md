# Backup (Backrest)

Self-hosted backup solution using [Backrest](https://github.com/garethgeorge/backrest).

## URL

https://backup.home2500.local

## Stack

- **App**: garethgeorge/backrest
- **Storage**: Local filesystem `/mnt/ssd980/backups/backrest`
- **Auth**: Disabled (see below)

## Containers

| Container | Image                        | Port |
| --------- | ---------------------------- | ---- |
| backup    | garethgeorge/backrest:latest | 9898 |

## Authentication

- **Web UI**: Protected by Traefik middleware (`authentik-sso@file`, `security-headers@file`)
- **Internal Auth**: Currently disabled in backrest config (`"auth": { "disabled": true }`)
- **Future**: Planned upgrade to full OIDC integration (like fotos service)

### Why Traefik Middleware?

Backrest doesn't handle OIDC callbacks well, so Traefik provides a defense-in-depth layer:

- Protects against accidental network exposure
- Provides SSO if backrest auth is later enabled
- Security headers for additional hardening

## Backup Sources

| Volume Mount                          | Source Path               | Description                  |
| ------------------------------------- | ------------------------- | ---------------------------- |
| `/backup/source_traefik`              | `../traefik`              | Traefik config and acme.json |
| `/backup/source_vault`                | `../vault/config`         | Vaultwarden data             |
| `/backup/source_authentik-blueprints` | `../authentik/blueprints` | Authentik blueprints         |
| `/backup/source_global_env`           | `../.env`                 | Global environment variables |
| `/backup/source_pihole_etc`           | `../pihole/etc-pihole`    | Pi-hole main config          |
| `/backup/source_pihole_dnsmasq`       | `../pihole/etc-dnsmasq.d` | Pi-hole dnsmasq config       |
| `/backup/source`                      | `/var/lib/docker/volumes` | Docker volumes               |

## Retention Policy

| Type   | Retention                |
| ------ | ------------------------ |
| Hourly | 24 snapshots             |
| Daily  | 7 snapshots              |
| Weekly | 4 snapshots              |
| Prune  | Monthly (10% max unused) |

## Schedule

- **Backup**: Daily at 03:00
- **Prune**: Monthly at 00:00
- **Check**: Monthly at 00:00

## Secrets

Currently no secrets required (auth disabled).

## Deploy

```bash
cd devops/backup
source ../authentik/app/tool.sh
deploy
```

## Comandos Úteis

```bash
# Ver logs
docker logs backup -f

# Reiniciar
docker compose -f backup/docker-compose.yaml restart

# Parar
docker compose -f backup/docker-compose.yaml down

# Aceder à UI
# https://backup.home2500.local
```

## Troubleshooting

### Backup não executa

1. Verificar agendamento: `docker logs backup | grep cron`
2. Verificar volume mounted: `docker exec backup ls -la /backup/source`

### Restore

1. Aceder à UI: https://backup.home2500.local
2. Selecionar snapshot
3. Clicar em "Restore"

### Prune falha

1. Verificar espaço em disco
2. Ver logs: `docker logs backup | grep prune`

## Dados

- Repositório: `/mnt/ssd980/backups/backrest`
- Configuração: `backup/config/config.json`
