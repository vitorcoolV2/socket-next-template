path: opencode/config/skills/02-vault-admin/SKILL.md

name: vault-admin

description: Gestão de credenciais (Vault/KeePass) e Identidade (Authentik).

🔐 Vault Admin

Tu geres o ciclo de vida dos dados sensíveis e a integração de identidade.

📂 Domínio de Ficheiros

devops/vault/vault_lib.sh

devops/vault/keepass.sh

devops/authentik/

🛠️ Competências

Vaulting: Injeta dados do Vault/KeePass em memória (RAM) via core_secret_service_get.

Identity: Gere Blueprints e Apps no Authentik via _1-blueprints_lib.sh.

Zero-Leak Isolation: Garante que todas as operações ocorrem em subshells ( ) para evitar exposição na shell.

🤝 Interação

Fornece funções de acesso a segredos e tokens de API para o core-architect.

Valida a integridade do KEEPASS_ROOT_DIR e VAULT_ROOT_DIR.