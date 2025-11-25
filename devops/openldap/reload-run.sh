
# Change to script directory
cd "$(dirname "$0")"
echo "Working directory: $(pwd)"

### The container name, network, source and target certs path
THE_NAME="openldap"
THE_NETWORK="app-network"
HOST_NAME="$THE_NAME.$THE_NETWORK"
SOURCE_CERTS_PATH=$(realpath ../step-ca/step/certs)
SOURCE_WEB_CERTS_PATH=$(realpath ../step-ca/step/web-certs/$THE_NETWORK)

###### MUST STOP ldap to rebuild from context
docker compose stop $THE_NAME
docker compose rm -f $THE_NAME 

docker compose up -d

# WAIT FOR FIRST TIME LONG START. More or less, like we do in the morning. checking in'er nodes connection
CONTAINER_NAME=$THE_NAME
MAX_ATTEMPTS=60  # Maximum number of attempts (e.g., 60 * 2s = 2 minutes)
SLEEP_TIME=2     # Polling interval in seconds
ATTEMPT=0

echo "Waiting for OpenLDAP container to initialize..."

# Loop until the container is ready
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  # Increment attempt counter
  ATTEMPT=$((ATTEMPT + 1))

  # Check if slapd is running by inspecting container logs
  if docker logs "$CONTAINER_NAME" 2>&1 | grep -q "slapd starting"; then
    echo "OpenLDAP container is ready!"
    exit 0
  fi

  # Alternatively, check if the LDAPS port (636) is open using netcat
  if nc -zv "$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER_NAME")" 636 2>/dev/null; then
    echo "OpenLDAP container is ready!"
    exit 0
  fi

  # Wait for 2 seconds before retrying
  echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: OpenLDAP container not ready yet. Retrying in $SLEEP_TIME seconds..."
  sleep "$SLEEP_TIME"
done