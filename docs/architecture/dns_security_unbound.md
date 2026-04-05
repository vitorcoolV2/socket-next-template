path: docs/architecture/dns_security_unbound.md

🛡️ Arquitetura DNS: Pi-hole & Unbound (Recursividade Local)

No ecossistema home2500, a stack DNS foi evoluída para um modelo de recursividade própria. Esta transição marca a independência da infraestrutura em relação a resolvedores comerciais (Google, Cloudflare, etc.).

🧩 Componentes da Stack

Pi-hole (L7 Filter): Atua como a primeira linha de defesa, bloqueando domínios de telemetria, publicidade e rastreio através de listas negras dinâmicas.

Unbound (Recursive Resolver): O motor de soberania. Em vez de reencaminhar pedidos, o Unbound contacta diretamente os Root Servers e os servidores autoritativos (TLD), resolvendo toda a árvore DNS localmente.

🚀 A Visão para 2500: Soberania Federada

Em 2500, a arquitetura DNS evolui de "recursividade local" para "autoridade absoluta de nó".

Zero-Trust Upstream: O conceito de Upstream DNS deixa de existir. Cada nó home2500 é uma autoridade raiz para o seu próprio sub-universo, sincronizando-se com outros nós via protocolos descentralizados, sem nunca expor metadados a entidades centrais.

DNS Distribuído: A resolução não depende de IPs estáticos, mas de uma malha de confiança onde a identidade do serviço é a própria prova de existência (Self-Sovereign Identity).

Latência Zero e Privacidade Total: Com a cache persistente e a recursividade local, o tempo de resposta é medido em microssegundos, e a "pegada" digital de navegação é zero, pois as consultas nunca saem da rede privada do Steward.

🛠️ Implementação Técnica Atual

A configuração garante que o Pi-hole utiliza o Unbound (porta 5335) como o seu único upstream.

Benefícios Imediatos:

DNSSEC Validation: Proteção contra cache poisoning e falsificação de respostas.

Privacy Hardening: Ocultação do tráfego DNS contra o ISP (Internet Service Provider) através do isolamento da recursividade.

Resiliência: Se os grandes resolvedores globais falharem, a rede home2500 continua a resolver nomes contactando diretamente a raiz da internet.

Nota do Arquiteto: Esta stack é o primeiro passo para a autonomia total prevista no Steward Role.
