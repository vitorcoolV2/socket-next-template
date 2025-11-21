# Create the required directories

. .env

docker compose authelia down

sudo chown root:root data/authelia/secrets
mkdir -p data/authelia/secrets

# Generate the secret files
echo "$(openssl rand -base64 32)" > data/authelia/secrets/JWT_SECRET
echo "$(openssl rand -base64 32)" > data/authelia/secrets/SESSION_SECRET
echo "$(openssl rand -base64 32)" > data/authelia/secrets/STORAGE_ENCRYPTION_KEY
echo "$LDAP_ADMIN_PASSWORD" > data/authelia/secrets/AUTHENTICATION_BACKEND_LDAP_PASSWORD
echo "$UNLOCK_PASSWORD" > data/authelia/secrets/STORAGE_PASSWORD

# Set proper permissions
chmod 600 data/authelia/secrets/*


ls -la data/authelia/secrets/
cat data/authelia/secrets/*