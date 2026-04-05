#!/bin/bash
# path: devops/opencode/entrypoint.sh


# Project git status for debugging
git ls-files --directory --exclude-standard --others 
# Project devops core files not in .gitignore
git ls-files --directory --exclude-standard 
# Listar arquivos accessíveis no container para debugging
#tree nextjs-app-template/devops -L 4

. ./core.sh 
# Carrega as funções do Core para o ambiente do container
# No Sonho o desejo d'um steward acrescenta o objectivo a missao "de manter os ent nomes de meu $DOMAIN". 
# O Core tem a função de garantir que o ambiente do container tem acesso a essas variáveis e segredos, e que o OpenCode pode operar com elas.
# Verdade seja dita, o Core é o guardião do ambiente, garantindo que as chaves certas estão no lugar para o OpenCode cumprir sua missão.
# Amem. a vontade do Core seja feita, no container como no Sonho do Steward.

. ./vault/keepass.sh
kp test || kp open

core_desired_domain_names_json | jq .


# 2. Esperar pelo Vault (Vault Admin Check)
#until curl -s $VAULT_ADDR/v1/sys/health > /dev/null; do
#  echo "waiting for vault-server em $VAULT_ADDR..."
#  sleep 1
#done

# 3. Executar o comando original (Post-Start)
exec "$@"
