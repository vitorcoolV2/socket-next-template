#!/bin/bash
LDAP_ADMIN_PASS="KjnFUyRJx7e4CiVa9k"
THE_USER="test"
THE_PASS="Secure123!"
THE_NAME="Tester"
THE_GROUPS="developers"

echo "=== LDAP User Management Test ==="

# 1. Delete the user if exists
echo "Step 1: Deleting user '$THE_USER' if exists..."
node authelia-ldap/stage4-ldap-user-manager.js delete $THE_USER

# 2. Create a proper test user
echo "Step 2: Creating user '$THE_USER'..."
node authelia-ldap/stage4-ldap-user-manager.js \
  create $THE_USER -p "$THE_PASS" -f "$THE_NAME" -g "$THE_GROUPS"

# 3. Verify the user was created correctly
echo "Step 3: Listing users..."
node authelia-ldap/stage4-ldap-user-manager.js list

# 4. Test LDAP bind with correct credentials
echo "Step 4: Testing LDAP bind..."
# First, let's check what DN format the script actually uses
#node authelia-ldap/stage4-ldap-user-manager.js search $THE_USER

# Search for the user to see their actual DN
ldapsearch -x -H ldap://openldap.app-network:389 \
  -b "ou=$THE_GROUPS,dc=home2500,dc=local" \
  -D "cn=admin,dc=home2500,dc=local" \
  -w "$LDAP_ADMIN_PASS" \
  "(uid=$THE_USER)"

# Or search more broadly
ldapsearch -x -H ldap://openldap.app-network:389 \
  -b "dc=home2500,dc=local" \
  -D "cn=admin,dc=home2500,dc=local" \
  -w "$LDAP_ADMIN_PASS" \
  "(|(uid=$THE_USER)(cn=$THE_USER))"


# Try the bind with the proper DN format
echo "Testing bind with generated DN..."
# Use the correct DN format - cn=test instead of uid=test
ldapwhoami -x -H ldap://openldap.app-network:389 \
  -D "cn=$THE_USER,ou=$THE_GROUPS,dc=home2500,dc=local" \
  -w "$THE_PASS"


# 5. Test login via Authelia API
echo ""
echo "Step 5: Testing Authelia API login..."
# Test what username format works by checking Authelia logs
echo "Make an authentication attempt and check logs:"
curl -X POST https://auth.home2500.local/api/firstfactor \
  -H "Content-Type: application/json" \
  -H "Host: auth.home2500.local" \
  -d '{"username":"test","password":"Secure123!","keepMeLoggedIn":true}' \
  -k -s


docker logs auth | tail -20

docker logs openldap | tail -20
