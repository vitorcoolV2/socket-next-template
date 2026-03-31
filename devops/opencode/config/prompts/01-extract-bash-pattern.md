📜 Bash Development Patterns (home2500)

Este documento cataloga os padrões de programação detetados no core.sh. Todos os novos scripts e bibliotecas (_lib.sh) devem aderir a estas convenções.

🏗️ 1. Nomenclatura e Prefixos (Namespace)

O projeto utiliza um sistema de nomes estrito para evitar colisões e identificar a origem da função:

Prefixo

Categoria

Descrição

core_*

Global/Core

Funções fundamentais de utilidade (caminhos, URLs, strings).

require_*

Assertions

Validações críticas que interrompem a execução se falharem (bins, files, vars).

docker_*

Infra

Interação direta com o motor Docker e redes.

ask_*

Interação

Prompts para o utilizador (provisionamento, confirmações).

_ (prefixo)

Internal

Funções privadas ou auxiliares que não devem ser chamadas fora da lib.

🛠️ 2. Gestão de Segredos (Secret Pattern)

Nunca se acede a passwords diretamente. O padrão é usar o sistema de provedores abstratos:

Fluxo: _get_service_secret_path -> _fetch_vault_provider -> core_secret_load_vars.

Implementação: As funções core_secret_mapper_* garantem que o código funciona indiferente de onde o segredo vem (Memória, Vault ou KeePass).

🛡️ 3. Padrão de Asserção (Fail-Fast)

Antes de qualquer operação lógica, o script deve validar as pré-condições usando o catálogo ASSERT:

# Exemplo de uso correto

require_vars "DOMAIN_NAME" "VAULT_TOKEN"
require_binaries "jq" "curl"
require_containers_ready "traefik"

🔍 4. Auto-Documentação (Cataloging)

O sistema é auto-consciente. Todas as funções são mapeadas no runtime:

Catalog: core_fn_catalog gera a lista dinâmica que acabaste de ver.

Mapping: As funções internas _map_function__file_line permitem localizar o código fonte exato em tempo real.

📝 5. Estilo de Codificação

Case: Funções usam snake_case (ex: to_pascal_case).

Injeção: Variáveis de ambiente são injetadas via core_transform_inject_env_file_vars.

Sanitização: Entradas de DB ou Paths devem passar por sanitize_db_name ou sanitize_path_name.

🤝 Interação para IAs (OpenCode)

Sempre que um Ator for criar uma nova função, deve primeiro verificar se já existe uma funcionalidade similar no core_fn_catalog para evitar duplicação.
