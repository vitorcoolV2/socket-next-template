# Action Todo: Chat Stack

## Overview

- **Reference**: chat/issues.md
- **Status**: In Progress

## Action Items

### High Priority

- [ ] **Enable GPU support** - Uncomment NVIDIA GPU configuration in docker-compose.yaml
- [ ] **Pre-pull default model** - Add model pull to init.sh or docker-compose entrypoint

### Medium Priority

- [ ] **Increase OLLAMA_KEEP_ALIVE** - Change from 2m to 24h for faster responses
- [x] **Configure OIDC** - Set up Authentik application for open-webui (done via provision_secrets)

### Low Priority

- [x] **Review memory limits** - Adjusted in docker-compose.yaml
- [x] **Add health checks** - Already configured in docker-compose.yaml

## Completed

- [x] **Provision OIDC secrets** - OIDC_ID, OIDC_SECRET added to provision_secrets()
- [x] **Fix init.sh copy/paste** - Changed "Stack Fotos" to "Stack Chat"
- [x] **Remove reset_ocis** - Invalid function call removed
- [x] **Create .secret export** - \_export_secrets_to_file() added

## Notes

- Stack uses OIDC authentication via Authentik
- Requires external `app-network` docker network
- All secrets (WEBUI_SECRET_KEY, OIDC_ID, OIDC_SECRET) provisioned via init.sh
