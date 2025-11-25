// debug-authelia-ldap.js
// #!/usr/bin/env node

import { execSync } from 'child_process';
import { readFile } from 'fs/promises';

async function loadEnv(envFilePath = '.env') {
  try {
    const envFileContent = await readFile(envFilePath, 'utf8');
    const envVars = {};
    envFileContent.split('\n').forEach((line) => {
      if (line.trim() === '' || line.trim().startsWith('#')) return;
      const [key, ...valueParts] = line.split('=');
      if (key && valueParts.length > 0) {
        const value = valueParts.join('=').trim();
        envVars[key.trim()] = value.replace(/^["']|["']$/g, '');
      }
    });
    return envVars;
  } catch (error) {
    console.error('Error reading .env file:', error.message);
    return {};
  }
}

async function debugLDAP() {
  const env = await loadEnv('.env');
  
  const baseDN = (env.LDAP_DOMAIN||'home2500.local').split('.').map(dc=>`dc=${dc}`).join(',');
  const ldapConfig = {
    url: env.LDAP_URL || 'ldap://openldap.app-network:389',
    bindDN: `cn=admin,${baseDN}`,
    bindPassword: env.LDAP_ADMIN_PASSWORD,
    baseDN,
  };

  console.log('🔍 Debugging Authelia LDAP Connection');
  console.log('====================================\n');

  // Test 1: Check LDAP connection
  console.log('1. Testing LDAP connection...');
  try {
    execSync(`ldapwhoami -x -H ${ldapConfig.url} -D "${ldapConfig.bindDN}" -w "${ldapConfig.bindPassword}"`, {
      stdio: 'pipe'
    });
    console.log('✅ LDAP connection successful');
  } catch (error) {
    console.log('❌ LDAP connection failed:', error.message);
    return;
  }

  // Test 2: List all users
  console.log('\n2. Listing all users in LDAP:');
  try {
    const users = execSync(`ldapsearch -x -H ${ldapConfig.url} -D "${ldapConfig.bindDN}" -w "${ldapConfig.bindPassword}" -b "ou=users,${baseDN}" "(objectClass=*)" dn cn mail uid displayName`, {
      encoding: 'utf8'
    });
    console.log(users);
  } catch (error) {
    console.log('❌ Failed to list users:', error.message);
  }

  // Test 3: Test specific user search (using Authelia's filter)
  console.log('\n3. Testing user search with Authelia filter "(cn=test)":');
  try {
    const result = execSync(`ldapsearch -x -H ${ldapConfig.url} -D "${ldapConfig.bindDN}" -w "${ldapConfig.bindPassword}" -b "ou=users,${baseDN}" "(cn=test)" dn cn mail uid displayName`, {
      encoding: 'utf8'
    });
    console.log(result || 'No user found with cn=test');
  } catch (error) {
    console.log('❌ Search failed:', error.message);
  }

  // Test 4: Test authentication with user
  console.log('\n4. Testing user authentication:');
  try {
    execSync(`ldapwhoami -x -H ${ldapConfig.url} -D "cn=test,ou=users,${baseDN}" -w "Secure123!"`, {
      stdio: 'pipe'
    });
    console.log('✅ User authentication successful');
  } catch (error) {
    console.log('❌ User authentication failed');
  }

  // Test 5: Check object classes of test user
  console.log('\n5. Checking test user object classes:');
  try {
    const userDetails = execSync(`ldapsearch -x -H ${ldapConfig.url} -D "${ldapConfig.bindDN}" -w "${ldapConfig.bindPassword}" -b "cn=test,ou=users,${baseDN}" -s base "(objectClass=*)" objectClass`, {
      encoding: 'utf8'
    });
    console.log(userDetails);
  } catch (error) {
    console.log('❌ Failed to get user details:', error.message);
  }
}

debugLDAP().catch(console.error);