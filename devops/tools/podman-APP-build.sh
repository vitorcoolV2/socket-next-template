#!/bin/bash

# Exit on error
# set -e

set +e

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ This is a library and should be sourced, not run directly."  >&2
    echo "     Try: source ./$(realpath --relative-to="$PWD" "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
    return 1 2> /dev/null || exit 1
fi



extract_build_args() {
    local name="${1}"
    local service=$(docker compose config 2> /dev/null | yq ".services[\"$name\"]")

    # Extract build arguments and strip quotes using jq's -r flag
    export APP_UID=$(echo "$service" | jq -r '.build.args.APP_UID // empty')
    export APP_GID=$(echo "$service" | jq -r '.build.args.APP_GID // empty')
    export APP_NAME=$(echo "$service" | jq -r '.build.args.APP_NAME // empty')
    export APP_GROUP=$(echo "$service" | jq -r '.build.args.APP_GROUP // empty')

    # Validate that required arguments are present
    if [[ -z "$APP_UID" || -z "$APP_GID" ]]; then
        echo "Error: Missing required build arguments (APP_UID or APP_GID)."
        return 1
    fi
}

ask_user_confirmation() {
    local message="$1"
    echo "$message"
    read -p "Do you want to proceed? (y/n): " response
    if [[ "$response" != "y" ]]; then
        echo "Aborting due to user request."
        return 1
    fi
    return 0
}

validate_host_requirements() {
    local service="${1}"
    if [[ -z "$service" ]]; then
        echo "Error: missing service argument specified, to propose resolve action."
        return 1
    fi
    # Check if the UID exists on the host
    if ! id "$APP_UID" &>/dev/null; then
        echo "Error: UID $APP_UID does not exist on the host."
        return 1  # Code 1: Missing UID
    fi

    # Check if the GID exists on the host
    if ! getent group "$APP_GID" &>/dev/null; then
        echo "Error: GID $APP_GID does not exist on the host."
        return 2  # Code 2: Missing GID
    fi

    # Check if the group name matches the GID
    local resolved_group=$(getent group "$APP_GID" | cut -d: -f1)
    if [[ "$resolved_group" != "$APP_GROUP" ]]; then
        echo "Warning: GID $APP_GID resolves to group '$resolved_group', but expected '$APP_GROUP'."
        return 3  # Code 3: Group name mismatch
    fi

    # Extract the source path of the bind mount from the volumes configuration
    local volume_source
    volume_source=$(docker compose config 2> /dev/null | yq ".services[\"$service\"].volumes[0].source" | sed 's/^"\(.*\)"$/\1/')

    # Handle Docker-managed volumes
    if [[ "$volume_source" == docker:* || ! "$volume_source" =~ ^/ ]]; then
        echo "Info: '$volume_source' is a Docker-managed volume. Skipping ownership and permission checks."
        return 0  # Skip further checks for managed volumes
    fi
    
    # Ensure the source directory exists
    if [[ -z "$volume_source" || ! -d "$volume_source" ]]; then
        echo "Error: Source directory '$volume_source' does not exist."
        return 4  # Code 4: Missing directory
    fi
    
    # Check the ownership of the source directory
    local current_owner
    current_owner=$(stat -c "%u:%g" "$volume_source" 2>/dev/null)
    local expected_owner="$APP_UID:$APP_GID"

    if [[ "$current_owner" != "$expected_owner" ]]; then
        echo "Error: Ownership of '$volume_source' is currently set to $current_owner, but expected $expected_owner."
        return 5  # Code 5: Ownership mismatch
    fi

    # Ensure the user has write access to the source directory
    if [[ ! -w "$volume_source" ]]; then
        echo "Error: Directory '$volume_source' is not writable by the current user."
        return 6  # Code 6: Permissions error
    fi

    # If all checks pass
    return 0  # Code 0: Success
}

propose_resolve_action() {
    local service="${1}"
    if [[ -z "$service" ]]; then
        echo "Error: missing service argument specified, to propose resolve action."
        return 1
    fi
    local return_code=$2
    local volume_source
    volume_source=$(docker compose config 2> /dev/null | yq ".services[\"$service\"].volumes[0].source"  | sed 's/^"\(.*\)"$/\1/')

    case $return_code in
        1)
            echo "Error: UID $APP_UID does not exist on the host."
            if ask_user_confirmation "Create user with UID $APP_UID?"; then
                sudo useradd -u "$APP_UID" -m "$APP_NAME" || {
                    echo "Failed to create user."
                    return 1
                }
                echo "User created successfully."
            else
                echo "Skipping user creation."
            fi
            ;;
        2)
            echo "Error: GID $APP_GID does not exist on the host."
            if ask_user_confirmation "Create group with GID $APP_GID?"; then
                sudo groupadd -g "$APP_GID" "$APP_GROUP" || {
                    echo "Failed to create group."
                    return 1
                }
                echo "Group created successfully."
            else
                echo "Skipping group creation."
            fi
            ;;
        3)
            echo "Warning: GID $APP_GID resolves to group '$(getent group "$APP_GID" | cut -d: -f1)', but expected '$APP_GROUP'."
            if ask_user_confirmation "Rename group to match expected name?"; then
                sudo groupmod -n "$APP_GROUP" "$(getent group "$APP_GID" | cut -d: -f1)" || {
                    echo "Failed to rename group."
                    return 1
                }
                echo "Group renamed successfully."
            else
                echo "Skipping group renaming."
            fi
            ;;
        4)
            echo "Error: Source directory '$volume_source' does not exist."

            # Handle null or invalid volume_source
            if [[ "$volume_source" == "null" || -z "$volume_source" ]]; then
                echo "Volume mount is undefined or invalid in docker-compose.yaml."
                local suggested_volume="./config/$APP_NAME:/home/$APP_NAME/config"

                if ask_user_confirmation "Add default volume mount '$suggested_volume' to docker-compose.yaml?"; then
                    # Check if docker-compose.yaml exists
                    if [[ ! -f "docker-compose.yaml" ]]; then
                        echo "Error: 'docker-compose.yaml' file not found in the current directory."
                        echo "Please ensure you are in the correct directory or provide the correct path."
                        echo "or"
                        echo "sense_install"
                        return 1
                    fi

                    # Ensure the volumes key exists under the service
                    if ! yq -e ".services[\"$service\"].volumes" docker-compose.yaml &>/dev/null; then
                        echo "Initializing 'volumes' array for service '$APP_NAME'..."
                        yq -yi ".services[\"$service\"].volumes = []" docker-compose.yaml || {
                            echo "Failed to initialize 'volumes' array."
                            return 1
                        }
                    fi

                    # Add the volume mount using yq
                    yq -yi ".services[\"$service\"].volumes += [\"$suggested_volume\"]" docker-compose.yaml || {
                        echo "Failed to update docker-compose.yaml."
                        return 1
                    }
                    echo "Added volume mount '$suggested_volume' to docker-compose.yaml."

                    # Re-extract the volume source
                    volume_source="./config/$APP_NAME"
                else
                    echo "Skipping volume mount addition."
                    return 1
                fi
            fi

            # Confirm directory creation
            if ask_user_confirmation "Create missing directory '$volume_source'?"; then
                mkdir -p "$volume_source" || {
                    echo "Failed to create directory."
                    return 1
                }
                echo "Directory created successfully."
            else
                echo "Skipping directory creation."
            fi
            ;;
        5)
            echo "Error: Ownership of '$volume_source' is currently set to $(stat -c "%u:%g" "$volume_source"), but expected $APP_UID:$APP_GID."
            if ask_user_confirmation "Change ownership of '$volume_source' to $APP_UID:$APP_GID?"; then
                sudo chown "$APP_UID:$APP_GID" "$volume_source" || {
                    echo "Failed to change ownership."
                    return 1
                }
                echo "Ownership changed successfully."
            else
                echo "Skipping ownership change."
            fi
            ;;
        6)
            echo "Error: Directory '$volume_source' is not writable by the current user."
            if ask_user_confirmation "Fix write permissions for '$volume_source'?"; then
                sudo chmod u+w "$volume_source" || {
                    echo "Failed to fix permissions."
                    return 1
                }
                echo "Permissions fixed successfully."
            else
                echo "Skipping permission fix."
            fi
            ;;
        *)
            echo "Unknown error. No resolution action available."
            return 1
            ;;
    esac
}

test() {
    docker run -v $(pwd)/config:/home/nodeuser/app/config \
         -p 3000:3000 base-pod-app
}


build() {
    local service="${1}"
    if [[ -z "$service" ]]; then
        echo "Error: missing service argument specified, to build ."
        return 1
    fi
    extract_build_args "$service" || return 1

    # Print the exported variables for debugging
    echo "APP_UID=$APP_UID"
    echo "APP_GID=$APP_GID"
    echo "APP_NAME=$APP_NAME"
    echo "APP_GROUP=$APP_GROUP"

    # Validate host requirements
    validate_host_requirements "$service"
    local validation_result=$?

    # Retry validation until all requirements are met
    while [[ $validation_result -ne 0 ]]; do
        echo "Validation failed with code $validation_result."

        # Propose resolution action
        propose_resolve_action "$service" "$validation_result" || {
            echo "Failed to resolve issue. Aborting build."
            return 1
        }

        # Revalidate after resolution
        validate_host_requirements "$service"
        validation_result=$?
    done

    # Proceed with the Docker Compose build
    echo "All requirements are satisfied. Building the service..."
    docker compose build "$service" || {
        echo "Error: Docker build failed."
        return 1
    }
}

podman_clean() {
    # Ensure the script is run as the intended user
    if [ -z "$SUDO_USER" ]; then
        echo "Error: SUDO_USER is not set. Run this script with sudo or as the intended user."
        return 1
    fi

    local USER_HOME=$(eval echo ~$SUDO_USER)
    local USER_UID=$(id -u $SUDO_USER)

    # 1. Stop Podman socket and services
    systemctl --user stop podman.socket podman.service || echo "Failed to stop Podman services."

    # 2. Kill any running Podman processes
    pkill podman || echo "No running Podman processes found."

    # 3. Clean XDG_RUNTIME_DIR (your user's runtime directory)
    if [ -d "/run/user/$USER_UID" ]; then
        rm -rf /run/user/$USER_UID/{containers,libpod,netns,networks,overlay*,runc,podman,storage} || echo "Failed to clean runtime directory."
    else
        echo "Runtime directory /run/user/$USER_UID does not exist."
    fi

    # 4. Remove problematic files and reset ownership
    if [ -d "$USER_HOME/.local/share/containers" ]; then
        rm -rf $USER_HOME/.local/share/containers/*
        chown -R $USER_UID:$USER_UID $USER_HOME/.local/share/containers || echo "Failed to reset ownership."
    else
        echo "Container storage directory does not exist."
    fi

    # 5. Reset Podman
    podman system reset || echo "Failed to reset Podman system."

    # 6. Verify cleanup
    if [ ! -d "$USER_HOME/.local/share/containers" ] && [ ! -d "/run/user/$USER_UID/containers" ]; then
        echo "✓ Storage and runtime directories are clean."
    else
        echo "Some directories were not cleaned up properly."
    fi

    # 7. Test Podman
    if podman pull alpine:latest && podman run --rm alpine echo "Podman is working!"; then
        echo "✓ Podman is functioning correctly."
    else
        echo "Error: Podman test failed."
    fi
}

# Source the bash_tool_sensor.sh library
source ../tools/bash_sensor.sh
source ../tools/podman-activate.sh


OUT_NDJSON="/tmp/$VENV_NAME:$(date +%Y%m%d%H%M%S).ndjson"
echo "OUT_NDJSON=$OUT_NDJSON"
touch "$OUT_NDJSON"

