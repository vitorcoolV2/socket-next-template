---
project: Home2500 DevOps Framework
stack: [Bash, Traefik, Authentik, Pi-hole, Vault, KeePass]
---

# 🗺️ Mapa de Dependências do Projeto

O ponto de entrada principal é `files/init.sh`. Ele depende das bibliotecas centrais e específicas:

### ⚙️ Core & Utils

- `devops/core.sh`: Funções globais de log, rede e variáveis de ambiente.
- `devops/vault/vault_lib.sh` & `keepass.sh`: Gestão de segredos e credenciais.

### 🔐 Auth Stack (Authentik)

- `devops/authentik/_0-authentik_lib.sh`: Configuração base da API.
- `devops/authentik/_1-blueprints_lib.sh`: Gestão de Blueprints/YAMLs.
- `devops/authentik/app/tool.sh`: Utilitários de gerenciamento de aplicações.

### 🌐 Network & Proxy

- `devops/traefik/_0.traefik_lib.sh`: Automação de labels e middlewares.
- `devops/pihole/_0.pihole_lib.sh`: Gestão de DNS local e bloqueios.

## 🛠️ Regras de Operação para AI

1. **Sempre Verifique Bibliotecas:** Antes de sugerir uma alteração no `init.sh`, leia as funções em `devops/core.sh` para evitar duplicidade.
2. **Segurança Primeiro:** Nunca sugira expor senhas no `init.sh`. Use as funções do `vault_lib.sh` para buscar credenciais.
3. **Escopo do Traefik:** Mudanças de CSP devem ser refletidas tanto nas labels do Compose quanto nas bibliotecas em `devops/traefik/`.
