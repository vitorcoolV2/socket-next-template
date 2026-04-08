# Chat (Open WebUI) - Issues & Status

## Current Status (2026-03-30)

### ✅ Working

- Chat application running at https://chat.home2500.local
- OIDC authentication via Authentik configured
- User `aiai-bot` created in Authentik via provision_user stage
- **GPU Enabled** - NVIDIA GeForce RTX 3060 (12GB VRAM)

### Pre-loaded Models

| Model                                 | Size   | Status        |
| ------------------------------------- | ------ | ------------- |
| qwen2.5-coder:1.5b                    | 986 MB | ✅ Downloaded |
| llama3.2:1b                           | 1.3 GB | ✅ Downloaded |
| deepseek-coder-v2:lite                | 8.9 GB | ✅ Downloaded |
| MFDoom/deepseek-coder-v2-tool-calling | 8.9 GB | ✅ Downloaded |

### OpenCode Integration

Config at `~/.config/opencode/opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "ollama/MFDoom/deepseek-coder-v2-tool-calling:latest",
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Local Ollama",
      "options": {
        "baseURL": "http://ai.app-network:11434/v1"
      },
      "models": {
        "MFDoom/deepseek-coder-v2-tool-calling:latest": {
          "name": "MFDoom/deepseek-coder-v2-tool-calling:latest"
        }
      }
    }
  }
}
```

**Status**: OpenCode connects to Ollama but tool execution has issues (model reports success but files not created).

### ❌ Remaining Issues

1. **provision_oidc stage fails** - Vault bot-policy needs update
   - Run: `cd devops/vault && ./_2-vault-policies.sh`
   - After: tool.sh will auto-create chat/OIDC_ID and chat/OIDC_SECRET in Vault

## Configuration

### GPU Settings

```yaml
deploy:
  resources:
    limits:
      memory: 4G
    reservations:
      devices:
        - driver: nvidia
          count: 1
          capabilities: [gpu, compute, utility]
```

### Environment

```bash
OLLAMA_KEEP_ALIVE=24h  # Keep models in VRAM
OLLAMA_NUM_PARALLELS=2 # Optimize for GPU
```

## TODO

- [x] Enable NVIDIA GPU support
- [x] Pre-pull qwen2.5-coder:1.5b model
- [x] Pre-pull llama3.2:1b model
- [ ] Run `_2-vault-policies.sh` to fix provision_oidc
- [x] Configure OpenCode with Ollama deepseek-coder-v2-tool-calling model
- [x] Pull qwen2.5-coder:14b model (in progress)
- [x] Fix OCIS files - CSP disabled (working at Traefik level)
