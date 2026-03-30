#!/bin/bash



swap_flush() {
    echo "Antes:"
    free -h
    echo ""

    echo "
    # 1. Força a gravação de dados pendentes no disco
    # 2. Limpa o cache de arquivos da RAM (libera espaço para o Swap voltar)
    # 3. Desliga e liga o Swap (isso força o conteúdo do Swap de volta para a RAM)"
    sudo sync && echo 3 | sudo tee /proc/sys/vm/drop_caches && sudo swapoff -a && sudo swapon -a
    echo "-------------------------"
    echo "depois"
    free -h
}

os_mem() {
    ps aux --sort=-%mem | awk 'NR<=6 {print $4"% MEM\t" $11}'
}

docker_mem() {
    docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}"
}

os_mem


docker_mem
