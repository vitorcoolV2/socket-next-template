#!/bin/bash

# Exit on error
# set -e

set +e

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ This is a library and should be sourced, not run directly."  >&2
    echo "     Try: source ./$(realpath --relative-to="$PWD" "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
    return 1 2> /dev/null || exit 1
fi

source ../tools/transform.sh # core__transform_string. well. how string looks like and how is integrated is other thing
source ../tools/git.sh       # The colective structural "Global Information Tracker"

## value to track existent podman vent

git__pwd_podman_venv_tracker() {
      # project local relative install. where i git clone
    local ENV_PROJECT_GRRU=$(core__transform_string "$(git_remote_root_url)" snake)
    export ENV_GIT_TRACKER="$(core__transform_string "${ENV_PROJECT_GRRU}" initials)"
    echo "
    ENV_GIT_TRACKER: ${ENV_GIT_TRACKER}" | grep -e "${ENV_GIT_TRACKER}"
    # Option 1: Only show files that match the suffix

    local DEVOPS_DIR="$(git_project_root)/devops"
    find -L "$DEVOPS_DIR" -maxdepth 3 -name "*${ENV_GIT_TRACKER}" | while read -r file; do
        # Converte caminho absoluto para relativo ao pwd atual
        echo " 
        venv: $(realpath --relative-to="$(pwd)" "$file" 2>/dev/null || echo "$file")" | grep -e "${ENV_GIT_TRACKER}"
    done    
}
git__pwd_podman_venv_tracker 


auto__pwd_podman_venv_activate() {
    # Check if the virtual environment exists in the current directory
    # the issue is automatic term enter folder base activate env ??????
    # - idea is activate what is already defined
    # lets make a trick with the env name.    
    #   - $(pwd) is a already existing print workspace directory
    #   - does it have podman supported python environment ?
    #   - how do we give native name locational id. 
    #   - A env name "a virtual env name" making reference to all it relative ancestral / min way to track location and lineage mutation 
    #   - A env name, containing path initials of target pwd criation. this auto invalidate copy of folder i bealive
    #   - a env name that auto define own folder liniege
    
    local PROJECT_IRP=$(core__transform_string "$(git_relative_path)" pascal) # project innner relative path. where will be installed a new environment    
    
    ## users of this project must have a public repository, or private one.
    export VENV_NAME=".${PROJECT_IRP}--${ENV_GIT_TRACKER}"

    

    # Set DOCKER_HOST for rootless Podman
    export DOCKER_HOST="unix:///run/user/$(id -u)/podman/podman.sock"

    if [[ -f "$(pwd)/${VENV_NAME}/bin/activate" ]]; then
        # Activate the virtual environment
        source "$(pwd)/${VENV_NAME}/bin/activate"
        # Extract the socket path from DOCKER_HOST
        SOCKET_PATH="${DOCKER_HOST#unix://}"

        # No seu .bashrc
        alias podman-run-dns='podman run --network dns'

        # Check if the socket file exists
        if [[ ! -S "$SOCKET_PATH" ]]; then
            echo "Error: Podman socket '$SOCKET_PATH' does not exist."
            echo "Ensure Podman is running in rootless mode. You can start it with:"
            echo "  podman system service --time=0 &"
            return 1
        fi

        # Update PATH to include the virtual environment's bin directory
        export PATH="$(pwd)/${VENV_NAME}/bin:$PATH"
        GIT_USER_NAME=$(git config --global user.name)
        GIT_USER_EMAIL=$(git config --global user.email)
        SYSTEM_USER=$(whoami)
        USER_ID=$(id -u)
               
        echo "
        Git User: $GIT_USER_NAME <$GIT_USER_EMAIL>
        System User: $SYSTEM_USER UID: $USER_ID
        $(id)
            sub*
              uid $(grep ^${SYSTEM_USER}: /etc/subuid)
              gid $(grep ^${SYSTEM_USER}: /etc/subgid)
        
        Project: $(pwd)
        Environment: $(pwd)/${VENV_NAME}  # Python Virtual environment activated.
        DOCKER_HOST=$DOCKER_HOST set for rootless Podman."
    else        
        echo "Virtual environment './${VENV_NAME}' not found in the current directory.
         - source ../tools/podman-install.sh 
         - sense_install
         "
        return 1
    fi
}

alias activate=auto__pwd_podman_venv_activate 
activate > /dev/null