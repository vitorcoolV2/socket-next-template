#!/bin/bash
# ../devops/tests.sh

set +e

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo "❌ This is a script and should not be sourced, run directly."  >&2
    return 1
fi

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/core.sh"


# Lê a saída linha por linha para dentro do array
readarray -t CONTAINERS < <(docker ps --format '{{.Names}}')

# Exemplo de uso dentro do seu loop de verificação
for name in "${CONTAINERS[@]}"; do
    echo "------------------------------------"
    echo "🔎 Testing >>>>>>>  $name  >>>>> port: [$(docker_container_name_ports "$name")]"
    
    # Obtém a lista de URLs candidatas
    url=$(core__container_name__url "$name")
    echo $url
    echo $(docker_container_name_ip "$name")
    echo $(docker_container_name_ports "$name")    

done
