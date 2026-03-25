# Start from the latest official Ubuntu release
FROM ubuntu:latest

# Set common environment variables
ENV DEBIAN_FRONTEND=noninteractive

# Argumentos obrigatórios (sem default). eu sei nao e auto. mas e minha resp (name, user, role)
ARG USERNAME
ARG USER_UID
ARG USER_GID
ARG DOCKER_GID=986

# Verificar se foram fornecidos
RUN if [ -z "$USERNAME" ] || [ -z "$USER_UID" ] || [ -z "$USER_GID" ]; then \
    echo "ERROR: Required build arguments missing!"; \
    echo "Please provide:"; \
    echo "  --build-arg USERNAME=<username>"; \
    echo "  --build-arg USER_UID=$(id -u)"; \
    echo "  --build-arg USER_GID=$(id -g)"; \
    exit 1; \
    fi

# Install core tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    vim \
    ca-certificates \
    curl \
    unzip \
    gnupg \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Create group if not exists, otherwise use existing group
RUN if getent group ${USER_GID} > /dev/null 2>&1; then \
    OLD_GROUP=$(getent group ${USER_GID} | cut -d: -f1); \
    if [ "$OLD_GROUP" != "$USERNAME" ]; then \
    groupmod -n ${USERNAME} ${OLD_GROUP}; \
    fi \
    else \
    groupadd -g ${USER_GID} ${USERNAME}; \
    fi && \
    if id -u ${USER_UID} > /dev/null 2>&1; then \
    OLD_USER=$(id -nu ${USER_UID}); \
    if [ "$OLD_USER" != "$USERNAME" ]; then \
    OLD_HOME=$(eval echo ~${OLD_USER}); \
    usermod -l ${USERNAME} ${OLD_USER}; \
    usermod -d /home/${USERNAME} -m ${USERNAME}; \
    groupmod -n ${USERNAME} ${OLD_USER} 2>/dev/null || true; \
    fi \
    else \
    useradd -u ${USER_UID} -g ${USER_GID} -m -s /bin/bash ${USERNAME}; \
    fi


# Install GitHub CLI (gh)
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI
RUN apt-get update && apt-get install -y --no-install-recommends docker.io && rm -rf /var/lib/apt/lists/*

# Create docker group and add user to it
RUN if getent group docker > /dev/null 2>&1; then \
    EXISTING_GID=$(getent group docker | cut -d: -f3); \
    if [ "$EXISTING_GID" != "${DOCKER_GID}" ]; then \
    groupmod -g ${DOCKER_GID} docker; \
    fi; \
    else \
    groupadd -g ${DOCKER_GID} docker; \
    fi && \
    usermod -aG docker ${USERNAME}

# DEBUG: Check if user still exists
RUN echo "=== BEFORE USER SWITCH ===" && \
    cat /etc/passwd | grep ${USERNAME} || echo "User ${USERNAME} NOT FOUND!" && \
    ls -la /home/ || true

# Switch to the user
USER ${USERNAME}
WORKDIR /home/${USERNAME}

# Create directories
RUN mkdir -p /home/${USERNAME}/.ssh && \
    ssh-keyscan github.com >> /home/${USERNAME}/.ssh/known_hosts 2>/dev/null && \
    mkdir -p /home/${USERNAME}/.local/share/opencode && \
    mkdir -p /home/${USERNAME}/.config/opencode

RUN curl -fsSL https://bun.sh/install | bash 


# Install OpenCode AI
RUN curl -fsSL https://opencode.ai/install | bash