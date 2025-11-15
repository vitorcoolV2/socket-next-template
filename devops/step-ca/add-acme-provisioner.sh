#!/bin/bash

# Variables
CONTAINER_NAME="step-ca"
PASSWORD_FILE="./step/secrets/password"  # Path to the password file on the host
COMMAND="step ca provisioner add acme --type ACME"

# Check if the container is running
if ! docker ps --filter "name=$CONTAINER_NAME" --filter "status=running" | grep -q "$CONTAINER_NAME"; then
  echo "Error: The container '$CONTAINER_NAME' is not running."
  exit 1
fi

# Check if the password file exists
if [[ ! -f "$PASSWORD_FILE" ]]; then
  echo "Error: Password file '$PASSWORD_FILE' not found."
  exit 1
fi

# Read the password from the file
PASSWORD=$(cat "$PASSWORD_FILE")


docker exec "$CONTAINER_NAME" step ca provisioner list

# Execute the command inside the container with non-interactive authentication
echo "Adding ACME provisioner to Step CA..."
docker exec \
  -e STEP_CA_PASSWORD="$PASSWORD" \
  "$CONTAINER_NAME" \
  sh -c "step ca provisioner add acme --type ACME"

# Check the exit status of the command
if [ $? -eq 0 ]; then
  echo "ACME provisioner added successfully."
else
  echo "Failed to add ACME provisioner. Please check the logs for more details."
  exit 1
fi