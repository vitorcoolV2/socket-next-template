
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

## delete folder mounted on container 
TO_CERT_PATH=$(realpath "./ldap/tls")
TO_CONFIG_PATH=$(realpath "./ldap/config")
TO_DATA_PATH=$(realpath "./ldap/data")

echo "Remove all ldap data mounted on volumes"
sudo rm -rf $TO_CERT_PATH 
sudo rm -rf $TO_CONFIG_PATH 
sudo rm -rf $TO_DATA_PATH


echo "Moving certs of: $HOST_NAME"
echo "SOURCE_WEB_CERTS_PATH: $SOURCE_WEB_CERTS_PATH"
echo "TO_CERT_PATH: $TO_CERT_PATH"
echo "SOURCE_WEB_CERTS_PATH: $SOURCE_WEB_CERTS_PATH"

sudo mkdir -p $TO_CERT_PATH
sudo chown -R $USER:$USER $TO_CERT_PATH

# Copy your step-ca certificates
sudo cp ${SOURCE_WEB_CERTS_PATH}/openldap.cert.pem $TO_CERT_PATH/ldap.crt
sudo cp ${SOURCE_WEB_CERTS_PATH}/openldap.key.pem $TO_CERT_PATH/ldap.key
sudo cp ${SOURCE_CERTS_PATH}/intermediate_ca.crt $TO_CERT_PATH/ca.crt

# Set proper permissions
sudo chmod 600 $TO_CERT_PATH/ldap.key
sudo chmod 644 $TO_CERT_PATH/ldap.crt $TO_CERT_PATH/ca.crt
sudo chown -R 911:911 $TO_CERT_PATH/*

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