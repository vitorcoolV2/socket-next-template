
# Copy the root CA certificate to system certificates
sudo cp /mnt/ssd980/Projects/nextjs-app-template/devops/trusted-ca.pem /usr/local/share/ca-certificates/trusted-ca.crt

# Update CA certificates
sudo update-ca-certificates

# Verify installation
ls -la /etc/ssl/certs/ | grep step