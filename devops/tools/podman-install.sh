#!/bin/bash

# Exit on error
# set -e

set +e

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ This is a library and should be sourced, not run directly."  >&2
    echo "     Try: source ./$(realpath --relative-to="$PWD" "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
    return 1 2> /dev/null || exit 1
fi


# Function to install required packages
install_required_packages() {
    if ! sudo apt update ; then
        return 1
    fi
    if ! sudo apt install -y podman python3-full uidmap; then
        return 1
    fi
    ### pyenv
    if ! sudo apt install -y make build-essential libssl-dev zlib1g-dev \
        libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm \
        libncurses5-dev libncursesw5-dev xz-utils tk-dev libffi-dev liblzma-dev \
        git; then
        return 1
    fi
    if ! sudo apt-get install -y python3-openssl; then
        return 1
    fi
    
    return 0
}

install_optional_vm_packages() {
    if ! sudo apt update ; then
        return 1
    fi
    ### podman machine vm 
    if ! sudo apt install -y qemu-system-x86 qemu-kvm libvirt-daemon-system ; then
        return 1
    fi    
    podman machine init 
    podman machine start

    ### vm accel tools 
    if ! sudo apt install -y libvirt-clients bridge-utils virt-manager htop; then        
        return 1
    fi    
    ## activate
    sudo usermod -aG kvm $USER 
    sudo usermod -aG libvirt $USER
    ## test
    kvm-ok
    lsmod | grep kvm
    podman machine list
}

# Function to set up a Python environment for pip3
setup_python_environment() {
    echo "Setting up Python environment for pip3..."

    # Check if python3-full is installed
    if ! command -v python3; then
        return 1
    fi

    # Create a virtual environment
    if ! python3 -m venv "$VENV_NAME"; then
        return 1
    fi

    # Activate the virtual environment
    if ! source "$VENV_NAME/bin/activate"; then
        return 1
    fi

    # Upgrade pip inside the virtual environment
    if ! pip install --upgrade pip; then
        deactivate
        return 1
    fi

    # Install podman-compose inside the virtual environment
    if ! pip install podman-compose; then
        deactivate
        return 1
    fi

    # Deactivate the virtual environment after installation
    if ! pip install pyopenssl; then
        deactivate
        return 1
    fi
    deactivate
    return 0
}



# Function to enable and start Podman socket
enable_podman_socket() {
    if ! systemctl --user enable podman.socket ; then
        return 1
    fi
    if ! systemctl --user start podman.socket ; then
        return 1
    fi
    return 0
}

# Function to add Docker alias (optional)
add_docker_alias() {
    read -p "Do you want to alias 'docker' to 'podman'? (y/n): " alias_docker
    if [[ "$alias_docker" == "y" ]]; then
        if ! echo "alias docker=podman" >> ~/.bashrc; then
            return 1
        fi
        if ! source ~/.bashrc ; then
            return 1
        fi
    fi
    return 0
}

# Step 1: Make sense bash 
sense() {
    local args=("$@")  # Capture all arguments as an array
    local log_file=$(mktemp)
    trap 'rm -f "$log_file"' EXIT  # Ensure the file is cleaned up on exit

    # Execute the command using core__tool_ and log the output
    echo " - Executing: ${args[*]}"
    core__tool_ "${args[@]}" > "$log_file" 2>&1
    local result=$(cat "$log_file")

    echo $result >> $OUT_NDJSON ### acummulate main execution flow
    # Check if the command resulted in an error
    if core__tool_is_error "$result"; then
        echo "Error executing command: ${args[*]}"
        echo "$result" | jq -r '.stderr'   # Print the stderr from the JSON output
        return 1
    fi    
    return 0
}


sense_install() {
    sense validate_sudo "$(whoami)"    ### validate whoami user has suitable $range   
    sense install_required_packages || return 1
    sense setup_python_environment || return 1
    
    
    source "${VENV_NAME}/bin/activate" || return 1    

    sense sudo apt install pipx || return 1
    # Ensure pipx is in your PATH
    sense pipx ensurepath || return 1

    # Install podman-compose
    sense pipx install podman-compose || return 1

    #sense "pip" "install" "podman-compose" || return 1
    ### this is me. vitor sudo #
    sense validate_sudo "$(whoami)"    ### validate whoami user has suitable $range   

    sense "enable_podman_socket" || return 1
    sense "podman" "--version" || return 1

    sense grep "$(whoami):" /etc/subuid ## Who are you
    sense grep "builder:" /etc/subgid

    sense grep CONFIG_USER_NS /boot/config-$(uname -r)

    sense sudo loginctl enable-linger $(whoami)

    

    ### python jsonschema. lets have fun spliting && reducing with python && filter .....
    sense pip install 
    #sense curl https://pyenv.run | bash
    sense python ../tools/bash_sensor_redutor.py $OUT_NDJSON

    echo "Inspect $(basename ${BASH_SOURCE[0]}) sense:response $OUT_NDJSON"
    python ../tools/bash_sensor_redutor.py $OUT_NDJSON
}


# Source the bash_tool_sensor.sh library
source ../tools/bash_sensor.sh
source ../tools/sudo-rootless.sh
source ../tools/podman-activate.sh
OUT_NDJSON="/tmp/$VENV_NAME:$(date +%Y%m%d%H%M%S).ndjson"
echo "OUT_NDJSON=$OUT_NDJSON"
touch "$OUT_NDJSON"

