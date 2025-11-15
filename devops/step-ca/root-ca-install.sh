exit

# IS PEFERABLE TO INSTALL file step/certs/root_ca.crt on respective browser
# my case,  brave://certificate-manager/ 

# LAST TIME I TRIED, SYSTEM FAIL WITH GREAT TROUBLES. BEFORE TRYING AGAIN, BE AWARE, SYSTEM COOKED MESURES


# Copy the root CA certificate to system certificates
sudo cp step/certs/root_ca.crt /usr/local/share/ca-certificates/step-root-ca.crt

# Update CA certificates
sudo update-ca-certificates

# Verify installation
ls -la /etc/ssl/certs/ | grep step