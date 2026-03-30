# Chat (Open WebUI) - Issues & Status

## Current Status (2026-03-30)

### ✅ Working

- Chat application running at https://chat.home2500.local
- OIDC authentication via Authentik configured
- User `aiai-bot` created in Authentik via provision_user stage
- **GPU Enabled** - NVIDIA GeForce RTX 3060 (12GB VRAM)
- **Model Downloaded** - qwen2.5-coder:1.5b (986 MB)

### Pre-loaded Models

| Model              | Size    | Status             |
| ------------------ | ------- | ------------------ |
| qwen2.5-coder:1.5b | 986 MB  | ✅ Downloaded      |
| llama3.2:1b        | 1.3 GB  | ✅ Downloaded      |
| codellama:1b       | ~1.3 GB | ❌ Error (removed) |

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
