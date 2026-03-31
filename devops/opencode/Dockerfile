# Start from Ubuntu 24.04
FROM ubuntu:24.04

# Set common environment variables
ENV DEBIAN_FRONTEND=noninteractive

# Build Arguments (passed from your docker-compose.yml)
ARG USERNAME
ARG USER_UID
ARG USER_GID
ARG DOCKER_GID=986

# 1. Install Prerequisites & Docker Repo
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg tree lsb-release sudo wget vim unzip jq git openssh-client \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# 2. Install Docker CLI + Plugins (Synchronized Versions)
RUN apt-get update && apt-get install -y \
    docker-ce-cli \
    docker-compose-plugin \
    docker-buildx-plugin \
    && rm -rf /var/lib/apt/lists/*

# 3. THE FIX: Link plugins to the Global Priority Path
# This ensures 'docker compose' works even if /home is mounted over
RUN mkdir -p /usr/local/lib/docker/cli-plugins && \
    ln -sf /usr/libexec/docker/cli-plugins/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose && \
    ln -sf /usr/libexec/docker/cli-plugins/docker-buildx /usr/local/lib/docker/cli-plugins/docker-buildx && \
    ln -sf /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose

# 4. Install yq (v4.50.1)
RUN wget https://github.com/mikefarah/yq/releases/download/v4.50.1/yq_linux_amd64 -O /usr/bin/yq \
    && chmod +x /usr/bin/yq

# 5. Create User & Map Docker Group
RUN if getent group ${USER_GID}; then \
    groupmod -n ${USERNAME} $(getent group ${USER_GID} | cut -d: -f1); \
    else \
    groupadd --gid ${USER_GID} ${USERNAME}; \
    fi && \
    if getent passwd ${USER_UID}; then \
    usermod -l ${USERNAME} -m -d /home/${USERNAME} $(getent passwd ${USER_UID} | cut -d: -f1); \
    else \
    useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/bash ${USERNAME}; \
    fi && \
    echo "${USERNAME} ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} && \
    chmod 0440 /etc/sudoers.d/${USERNAME} && \
    (groupadd -g ${DOCKER_GID} docker_host || true) && \
    usermod -aG ${DOCKER_GID} ${USERNAME} || true

# 6. Switch to User
RUN chown -R ${USERNAME}:${USER_GID} /home/${USERNAME}
USER ${USERNAME}
WORKDIR /home/${USERNAME}

# 7. Setup SSH and local tools
RUN mkdir -p /home/${USERNAME}/.ssh \
    && ssh-keyscan github.com >> /home/${USERNAME}/.ssh/known_hosts 2>/dev/null \
    && chmod 700 /home/${USERNAME}/.ssh

# 8. Install Bun & OpenCode
RUN curl -fsSL https://bun.sh/install | bash \
    && curl -fsSL https://opencode.ai/install | bash

# Final Path Setup
ENV PATH="/home/${USERNAME}/.local/bin:/home/${USERNAME}/.bun/bin:${PATH}"

CMD ["bash"]