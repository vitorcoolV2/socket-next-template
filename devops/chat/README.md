# Chat Stack (Open WebUI + Ollama)

Local AI chat interface with Ollama LLM backend.

## Services

| Service    | Image                              | Port  | Description |
| ---------- | ---------------------------------- | ----- | ----------- |
| open-webui | ghcr.io/open-webui/open-webui:main | 8080  | Chat UI     |
| ollama     | ollama/ollama:latest               | 11434 | LLM runtime |

## URLs

- **Chat UI**: https://chat.home2500.local
- **Ollama API**: http://ai.app-network:11434

## Authentication

OIDC via Authentik:

- Provider: `https://auth.home2500.local/application/o/open-webui/`
- Auto-signup enabled for new Authentik users

## Environment Variables

| Variable         | Description               |
| ---------------- | ------------------------- |
| CLIENT_ID        | OIDC Client ID            |
| CLIENT_SECRET    | OIDC Client Secret        |
| WEBUI_SECRET_KEY | Open WebUI session secret |

## Deployment

```bash
# Deploy stack
./init.sh deploy

# Or manually:
docker compose -f docker-compose.yaml up -d
```

## Resource Limits

| Service    | Memory Limit |
| ---------- | ------------ |
| open-webui | 1G           |
| ollama     | 3G           |

## GPU Support

Ollama supports NVIDIA GPUs. Uncomment the following in `docker-compose.yaml`:

```yaml
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: 1
          capabilities: [gpu]
```
