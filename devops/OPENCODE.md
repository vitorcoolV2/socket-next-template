path: devops/OPENCODE.md

project: Home2500 DevOps Framework

version: 2.7 (Zero-Leak Edition)
core_system: "devops/*core.sh << devops/.env"
entrypoint: "files/init.sh"
orchestrator: "devops/authentik/app/tool.sh (Service Factory Only)"

🗺️ Mapa de Contexto - home2500

🏛️ O "Steward Role" (Dono da Casa)

O sistema foi desenhado para um "Steward" que detém a chave física/PIN e delega a complexidade técnica ao Core.

Isolamento: O acesso ao cofre é mediado pelo Core.

Maturidade: Mudanças no Core exigem preservação da estabilidade dos serviços ativos.

🏗️ O "Service Factory" (Workflow de Publicação)

Aplica-se apenas aos novos serviços com estrutura devops/$nome/init.sh.

Discovery: Pasta devops/nome com docker-compose.yaml.

Secret Mapping: Extração via core_secret_service_get (Vault/KeePass -> Memória).

Provisioning: Blueprints OIDC no Authentik via tool.sh.

Exposição: Registo DNS no Pi-hole (ph) e Traefik.

🛡️ Regra de Ouro: Zero-Leak Shell (Isolation)

Isolamento Bash: Operações com segredos devem ocorrer em subshells ( ).

Verificação: env | grep -E "TOK|PASS|SECRET" não pode retornar valores.

🛠️ Definições Core (Paths & Mappers)

export KEEPASS_ROOT_DIR="vault"
export VAULT_ROOT_DIR="secret"
export MEM_ROOT_DIR="/run/user/$UID/home2500"

🤖 Actores

01 Core Architect: Moderador de mudanças e estabilidade.

02 Vault Admin: Gere o ciclo de vida dos dados nos caminhos acima.

04 Network Admin: Gere Traefik e DNS (ph).

📈 Estado Atual

[x] Auto-provisionamento OIDC.

[x] Isolamento de subshell (Zero-Leak).

[x] Dynamic RAM Root para dados voláteis.
