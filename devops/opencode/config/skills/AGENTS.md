# 🤖 Matriz de Agentes (Actors) - Projeto home2500

Este documento define a hierarquia, os identificadores e o mapeamento de competências para a orquestração multi-agente.

## 📋 Tabela de Mapeamento (Caminhos Oficiais)

| ID | Agente | Ficheiro de Skill | Responsabilidade Primária |
|:---|:---|:---|:---|
| **00** | **System Explorer** | `00-system-explorer/SKILL.md` | Inspeção de ficheiros, `tree`, `ls`, `cat`. |
| **01** | **Core Architect** | `01-core-architect/SKILL.md` | **Execução:** Orquestração de `init.sh` e lógica Bash. |
| **01D**| **Diagram Architect**| `01-diagram-architect/SKILL.md`| **Representação:** Desenho de diagramas Mermaid. |
| **02** | **Security Vault** | `02-devops-security/SKILL.md` | Gestão de segredos, Vault e KeePass. |
| **03** | **Auth Authentik** | `03-auth-authentik/SKILL.md` | Identidade, Blueprints e Provedores IAM. |
| **04** | **Network Admin** | `04-network-admin/SKILL.md` | Traefik, Pi-hole (Wrapper `ph`) e Unbound. |
| **05** | **Release Manager** | `05-release-manager/SKILL.md` | Validação de sintaxe e estabilidade de logs. |

## 📌 Regras de Comunicação

- Cada agente deve referir-se ao outro pelo **ID** (ex: "Solicito ao Agente 04 que...").
- O **01 Core Architect** valida o código; o **01D Diagram Architect** valida a imagem.
