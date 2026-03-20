# Fotos (Immich)

Self-hosted Google Photos alternative.

## URL

<https://fotos.home2500.local>

## Stack

- **App**: Immich (immich-server + immich-machine-learning)
- **Database**: PostgreSQL (authentik-db)
- **Cache**: Redis (authentik-redis)
- **Auth**: OIDC via Authentik

## Containers

| Container     | Image                                              | Port |
| ------------- | -------------------------------------------------- | ---- |
| immich-server | ghcr.io/immich-app/immich-server:release           | 2283 |
| immich-ml     | ghcr.io/immich-app/immich-machine-learning:release | 3003 |

## OIDC Configuration

- **Issuer**: <https://auth.home2500.local/application/o/fotos/>
- **Client ID**: immich-fdgds53c
- **Scopes**: openid, email, profile
- **Auto-register**: true

## Secrets

Guardados em:

- `mem:/run/user/1000/home2500/fotos/.secret`
- `vault:secret/fotos/`
- `keepass:`

Variáveis:

- `DB_ROLE_ADMIN_PASS` - Password do utilizador DB
- `REDIS_PASSWORD` - Password do Redis
- `CLIENT_APP_OIDC_ID` - Client ID OIDC
- `CLIENT_APP_OIDC_SECRET` - Client Secret OIDC

## Deploy

```bash
cd devops/fotos
source ../authentik/app/tool.sh
deploy
```

## Comandos Úteis

```bash
# Ver logs
docker logs immich-server -f

# Reiniciar
docker compose -f fotos/docker-compose.yaml restart

# Parar
docker compose -f fotos/docker-compose.yaml down
```

## Troubleshooting

### Container não inicia (DB password error)

1. Verificar se a password está correta em `.secret`
2. Regenerar secrets:

   ```bash
   source ../../core.sh
   source ../authentik/app/tool.sh
   core_secret_export2_env_vars fotos DB_ROLE_ADMIN_PASS REDIS_PASSWORD CLIENT_APP_OIDC_ID CLIENT_APP_OIDC_SECRET
   docker compose -f docker-compose.yaml up -d
   ```

### OIDC login não funciona

1. Verificar que o provider existe no Authentik: <https://auth.home2500.local/if/admin/#/core/providers/>
2. Verificar redirect_uris no provider
3. Verificar logs: `docker logs immich-server`

## Dados

- Dados de upload: `/mnt/ssd980/immich_data`
- Modelos ML: `/mnt/ssd980/immich_model_cache`
