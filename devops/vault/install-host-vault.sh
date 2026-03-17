# Download the latest Vault binary directly
VAULT_VERSION="1.21.1"
cd /tmp

# Download Vault
wget https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip

# Download checksums for verification
wget https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_SHA256SUMS

# Verify the download
sha256sum -c vault_${VAULT_VERSION}_SHA256SUMS 2>&1 | grep OK

# Install Vault
sudo unzip -o vault_${VAULT_VERSION}_linux_amd64.zip -d /usr/local/bin/
sudo chmod +x /usr/local/bin/vault

vault --version


### yq is required too
sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq
sudo chmod +x /usr/bin/yq