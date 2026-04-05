# path: devops/opencode/Dockerfile

# ==========================================
# ESTÁGIO 1: BASE (Identidade e Segurança)
# ==========================================
FROM ubuntu:noble AS base

# Argumentos de Identidade (Sincronizados com o Host)
ARG APP_USER=steward
ARG APP_UID=2500
ARG APP_GID=2500
ARG DOCKER_GID=986
ARG DOMAIN=home2500.local

COPY devops/opencode/entrypoint.sh ./opencode/entrypoint.sh

# Instalação Base Essencial
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg sudo wget git jq lsb-release \
    iproute2 procps dnsutils iputils-ping unzip \
    && rm -rf /var/lib/apt/lists/*

# Injeção Direta de Certificado para evitar erros de SSL/TLS
COPY devops/trusted-ca.pem ./opencode/home2500-ca.pem
RUN cat ./opencode/home2500-ca.pem >> /etc/ssl/certs/ca-certificates.crt

# Criação da Identidade Steward
RUN groupadd -g $APP_GID stewards || true && \
    groupadd -g $DOCKER_GID docker_host || true && \
    useradd -m -u $APP_UID -g stewards -G docker_host,sudo -s /bin/bash $APP_USER || true && \
    echo "$APP_USER ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# ==========================================
# ESTÁGIO 2: DEVELOPMENT (OpenCode / Agente 01)
# ==========================================
FROM base AS development

USER root
# Ferramentas de Orquestração e Build (Docker CLI, Compose, Tree)
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && apt-get install -y docker-ce-cli docker-compose-plugin tree \
    && rm -rf /var/lib/apt/lists/*

# Instalação do Bun (Runtime de IA/JS)
ENV BUN_INSTALL=/home/$APP_USER/.bun
ENV PATH=$BUN_INSTALL/bin:$PATH
RUN curl -fsSL https://bun.sh/install | bash

USER $APP_USER
WORKDIR /home/$APP_USER/devops

# O OpenCode fica em aguardo para comandos do Steward
CMD ["tail", "-f", "/dev/null"]

# ==========================================
# ESTÁGIO 3: RUNTIME (Serviço App de Produção)
# ==========================================
FROM base AS runtime

# Otimização para Produção
ENV NODE_ENV=production
ENV TMPDIR=/tmp

# No runtime, não temos Docker CLI nem Bun por padrão (Segurança Ativa)
# Apenas o essencial para rodar o serviço exposto
USER $APP_USER
WORKDIR /home/$APP_USER/devops

# Entrypoint que limpa a RAM antes de iniciar
CMD ["/bin/bash", "-c", "rm -rf /tmp/* && exec /bin/bash"]