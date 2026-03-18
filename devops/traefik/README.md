# Traefik (Edge Proxy)

Traefik is the edge router and load balancer for the entire stack.

## Responsibilities

- **TLS Termination**: Automatically fetches and manages certificates from Vault.
- **Routing**: Routes traffic to containers based on hostnames (`<service>.$DOMAIN`).
- **Security**: Applies middlewares for SSO (Authentik), Security Headers, and IP whitelisting.

## Configuration

- **Static Config**: `devops/traefik/traefik.yaml`
- **Dynamic Config**: `devops/traefik/dynamic/` (File provider)
- **Certificates**: Stored in Vault and cached in `acme.json` (managed via `tk_lib`).

## Integration with Authentik

Traefik uses the `forward-auth` middleware pointing to the Authentik Outpost. This ensures that any request to a protected service is first challenged for authentication.

## Useful Commands

```bash
source devops/traefik/_0.traefik_lib.sh

tk_up             # Start Traefik with Vault check
tk_renew_certs    # Force renewal of TLS certificates
tk_status         # Show routing status
```
