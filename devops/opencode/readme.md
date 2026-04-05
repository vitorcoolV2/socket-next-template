# OpenCode

AI-powered code assistant using [OpenCode](https://opencode.ai).

## Overview

This setup runs OpenCode in a Docker container with:

- Ubuntu base image
- Pre-configured AI provider (Docker Model Runner)
- TUI and Web interfaces
- Shared workspace directory

## URL

- **Web UI**: https://opencode.home2500.local
- **Local**: `docker exec -it opencode opencode web`

## Architecture

```
┌─────────────────────────────────────────────┐
│  opencode container (Ubuntu)                │
│  ┌─────────────────────────────────────┐    │
│  │  opencode.ai CLI + Web Server       │    │
│  │  AI: Docker Model Runner (DMR)      │    │
│  │  - qwen-coder3                      │    │
│  │  - devstral-small-2                 │    │
│  └─────────────────────────────────────┘    │
│  └── workspace/  (shared with host)          │
└─────────────────────────────────────────────┘
```

## AI Provider Configuration

Provider configured in `opencode.json`:

| Provider                  | Type  | Models                        |
| ------------------------- | ----- | ----------------------------- |
| Docker Model Runner (DMR) | Local | qwen-coder3, devstral-small-2 |

The DMR endpoint runs at `http://localhost:12434/v1` (typically served by [ollama](https://ollama.ai/) or similar).

## Authentication

- **Web UI**: Protected by Traefik middleware (`authentik-sso@file`, `security-headers@file`)
- **OpenCode Server**: No password required - authentication handled by Traefik/Authentik OIDC

After Authentik OIDC login succeeds, access to OpenCode is granted without additional password prompt.

## Setup

### 1. Configure User

Edit `.env` file:

```bash
USER=vitor
UID=1000
GID=1000
```

Or create from template:

```bash
cp .env.template .env
# Edit USER/UID/GID to match your system user
```

### 2. (Optional) Set Server Password

Only needed if NOT using Traefik/Authentik OIDC:

```bash
OPENCODE_SERVER_PASSWORD=your-secure-password
```

### 3. Build and Run

```bash
cd devops/opencode
docker compose build
docker compose up -d
```

### 4. Access

- **Web UI**: https://opencode.home2500.local
- **TUI**: `docker exec -it opencode opencode`
- **Attach TUI to Web**: `docker exec -it opencode opencode attach http://localhost:4096`

## Configuration

### opencode.json

Main configuration file for AI providers and server:

```json
{
  "provider": {
    "dmr": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Docker Model Runner",
      "options": {
        "baseURL": "http://localhost:12434/v1"
      },
      "models": {
        "qwen-coder3": { "name": "qwen-coder3" },
        "devstral-small-2": { "name": "devstral-small-2" }
      }
    }
  },
  "server": {
    "port": 4096,
    "hostname": "0.0.0.0"
  }
}
```

### Switching Models

Inside opencode:

```
/model qwen-coder3
```

## Volumes

| Host Path                       | Container Path           | Description      |
| ------------------------------- | ------------------------ | ---------------- |
| `./workspace`                   | `/home/${USER}/`         | Shared workspace |
| `${HOME}/.local/share/opencode` | `/.local/share/opencode` | App data         |
| `${HOME}/.local/state/opencode` | `/.local/state/opencode` | State            |
| `${HOME}/.local/bin/opencode`   | `/.local/bin/opencode`   | Binary           |
| `${HOME}/.config/opencode`      | `/.config/opencode`      | Config           |
| `${HOME}/.ssh`                  | `/.ssh` (ro)             | SSH keys         |
| `${HOME}/.bashrc`               | `/.bashrc`               | Shell config     |

## Deployment

```bash
cd devops/opencode
source ../authentik/app/tool.sh
deploy
```

## Commands

```bash
# Build image
docker compose build

# Start container
docker compose up -d

# Stop container
docker compose down

# View logs
docker logs opencode

# Access TUI
docker exec -it opencode opencode

# Run web server
docker exec -it opencode opencode web

# Attach TUI to web server
docker exec -it opencode opencode attach http://localhost:4096

# Rebuild after changes
docker compose build --no-cache && docker compose up -d
```

## Troubleshooting

### Container won't build

Verify build args are set:

```bash
docker compose build \
  --build-arg USERNAME=$(whoami) \
  --build-arg USER_UID=$(id -u) \
  --build-arg USER_GID=$(id -g)
```

### AI provider not connecting

Ensure Docker Model Runner is running and accessible:

```bash
curl http://localhost:12434/v1/models
```

### Permission issues

Ensure UID/GID in `.env` match your user:

```bash
id
# uid=1000(vitor) gid=1000(vitor) groups=...
```

### Web UI not loading

Check if server started with password:

```bash
docker exec opencode env | grep OPENCODE
```

## Security Notes

- SSH directory mounted read-only
- Container runs as non-root user
- Web UI protected by Traefik + Authentik OIDC
- OpenCode server has no password (rely on Traefik auth layer)

## Future Enhancements

- [x] Traefik web UI exposure with Authentik OIDC
- [x] No password required after OIDC login
- [ ] Multi-user support
- [ ] GPU passthrough for local models
