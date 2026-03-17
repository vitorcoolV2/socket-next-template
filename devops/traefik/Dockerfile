# Start from your current Traefik image
FROM traefik:v3.6.1


# 1. Copy the CA certificate into the system's CA directory
# Use the ca-chain.pem path you are already using
COPY ./traefik/certs/ca-chain.pem /usr/local/share/ca-certificates/vault-ca-chain.crt

# 2. Update the system trust store
# The Traefik container uses an Alpine/Debian base, so this command is usually available
RUN update-ca-certificates