
# Change to script directory
cd "$(dirname "$0")"
echo "Working directory: $(pwd)"

# Create directory structure
#export PREVIOUS_LDAP_TLS_CA_CRT_PATH=/container/service/slapd/assets/certs/ca.crt
#export PREVIOUS_LDAP_TLS_CRT_PATH=/container/service/slapd/assets/certs/ldap.crt
#export PREVIOUS_LDAP_TLS_KEY_PATH=/container/service/slapd/assets/certs/ldap.key
#export PREVIOUS_LDAP_TLS_DH_PARAM_PATH=/container/service/slapd/assets/certs/dhparam.pem
PARA="./ldap/tls"

HOST="openldap.app-network"
FROM="../step-ca/step/web-certs/$HOST"
sudo mkdir -p $PARA
sudo chown -R $USER:$USER $PARA

# Copy your step-ca certificates
cp ${FROM}/cert.pem $PARA/ldap.crt
cp ${FROM}/key.pem $PARA/ldap.key
cp ${FROM}/intermediate-ca.crt $PARA/ca.crt

# Set proper permissions
chmod 600 $PARA/ldap.key
chmod 644 $PARA/ldap.crt $PARA/ca.crt