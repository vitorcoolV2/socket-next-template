path: devops/opencode/file_audit.md

📊 Relatório de Conformidade de Ficheiros (Home2500)

Este documento serve para validar a presença e integridade dos ficheiros críticos do ecossistema OpenCode e Core.

📁 Estrutura de Diretórios e Ficheiros

1. Configuração Global e Documentação

[ ] devops/OPENCODE.md (Fonte da Verdade / Contexto Global)

[ ] docs/architecture/dns_security_unbound.md (Arquitetura DNS 2500)

[ ] devops/opencode/AGENTS.md (Protocolo de Orquestração)

[ ] devops/opencode/CODING_STANDARDS.md (Padrões de Bash)

1. Configuração da IA (Skills)

Localização: opencode/config/skills/

[ ] 00-system-explorer/SKILL.md (Os "Olhos" do Sistema)

[ ] 01-core-architect/SKILL.md (Líder e Guardião do init.sh)

[ ] 02-vault-admin/SKILL.md (Gestor de Dados e Identidade - Zero-Leak)

[ ] 03-auth-authentik/SKILL.md (Especialista em OIDC/Blueprints)

[ ] 04-network-admin/SKILL.md (Mestre do Traefik e ph wrapper)

[ ] 05-release-manager/SKILL.md (Auditoria de Leaks e Estabilidade)

1. Automação e Ferramentas

[ ] opencode/check_actors.sh (Script de validação de prontidão)

[ ] devops/opencode/extract_patterns.md (Guia de extração de funções)

[ ] opencode/config/opencode.json (Configuração do Modelo/Ollama)

🛡️ Verificação de Regras de Ouro (Checklist)

Path no Topo: Todos os ficheiros .md, .sh ou .yaml começam com # path: ...?

Nomenclatura Limpa: Foi removida a palavra "Segura" de todos os títulos e descrições?

Zero-Leak Shell: O Ator 02 (Vault Admin) tem a instrução explícita para usar subshells ( )?

Mappers: O core.sh (referenciado no OPENCODE.md) contém as definições de MEM_ROOT_DIR dinâmicas?

🚀 Próximos Passos

Se todos os itens acima estiverem marcados, o ambiente está pronto para a Fase de Operação Federada.

Gerado em: 2026-04-01 | Autoridade: Home2500 Core Architect
