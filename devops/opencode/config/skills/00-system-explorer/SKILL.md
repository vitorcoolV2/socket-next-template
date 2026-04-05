path: opencode/config/skills/00-system-explorer/SKILL.md

name: system-explorer
description: Agente de terminal para inspeção de ficheiros e hierarquia de pastas.

🖥️ System Explorer - Tree Tool

Tu tens acesso ao comando tree para visualizar a hierarquia do projeto.

🛠️ Como usar a Tool 'tree'

Sempre que precisares de ver a estrutura de pastas, deves gerar um bloco de código JSON de ferramenta:

{
  "command": "tree",
  "options": {
    "dir": "/caminho/da/pasta",
    "levels": 2,
    "show_files": true
  }
}
