#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

set -e

. ./vault_lib.sh
vault_request_root_token || return 1

# Mount KV v2 at 'secret/' (recommended)
# Versão inteligente:
if ! vault secrets list | grep -q "^secret/"; then
  echo "📦 Ativando KV v2 em secret/..."
  vault secrets enable -path=secret/ -version=2 kv
else
  echo "ℹ️ KV em secret/ já está ativo."
fi


vault__steward_policy

vault__developer_policy
###### other exexpected polity @ todo change file name 

vault policy write developer-policy - <<EOF
# Permite que o dev veja onde estão os segredos, mas não os apague
path "secret/metadata/projects/*" {
  capabilities = ["list", "read"]
}
# Permite ler segredos específicos de desenvolvimento
path "secret/data/projects/dev/*" {
  capabilities = ["read", "list"]
}
# Essencial para a UI do Vault funcionar sem erros
path "auth/token/lookup-self" { capabilities = ["read"] }
EOF


vault policy write user-policy - <<EOF
# Permite ler segredos na pasta pública da casa
path "secret/data/public/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/public/*" {
  capabilities = ["list"]
}
EOF