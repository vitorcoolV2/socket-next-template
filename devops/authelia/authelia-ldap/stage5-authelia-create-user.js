// authelia-user-create.js
//#!/usr/bin/env node

import { execSync } from 'child_process';
import { readFile } from 'fs/promises';

async function createAutheliaUser() {
  const env = await loadEnv('.env');
  
  const username = process.argv[2];
  const password = process.argv[3];
  const fullName = process.argv[4] || username;
  
  if (!username || !password) {
    console.log('Usage: node authelia-user-create.js <username> <password> [fullName]');
    process.exit(1);
  }

  const baseDN = (env.LDAP_DOMAIN||'').split('.').map(dc=>`dc=${dc}`).join(',');
  const ldapConfig = {
    url: env.LDAP_URL,
    bindDN: `cn=admin,${baseDN}`,
    bindPassword: env.LDAP_ADMIN_PASSWORD,
    baseDN,
  };

  console.log('🔐 Creating Authelia-compatible LDAP User');
  
  // Enhanced user creation with Authelia-required attributes
  const userContent = `dn: cn=${username},ou=users,${ldapConfig.baseDN}
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: ${username}
sn: ${fullName}
givenName: ${fullName.split(' ')[0]}
uid: ${username}
userPassword: ${password}
displayName: ${fullName}
mail: ${username}@home2500.local
uidNumber: 1000
gidNumber: 1000
homeDirectory: /home/${username}
loginShell: /bin/bash`;

  try {
    // Delete user if exists
    try {
      execSync(`ldapdelete -x -H ${ldapConfig.url} -D "${ldapConfig.bindDN}" -w "${ldapConfig.bindPassword}" "cn=${username},ou=users,${ldapConfig.baseDN}"`, 
        { stdio: 'ignore' });
      console.log('♻️  Removed existing user');
    } catch (e) {
      // User didn't exist, continue
    }

    // Create user
    console.log(`👤 Creating user: ${username}`);
    execSync(`echo '${userContent}' | ldapadd -x -H ${ldapConfig.url} -D "${ldapConfig.bindDN}" -w "${ldapConfig.bindPassword}"`, 
      { encoding: 'utf8', stdio: 'inherit' });
    
    // Add to authelia_users group
    const groupContent = `dn: cn=authelia_users,ou=groups,${ldapConfig.baseDN}
changetype: modify
add: member
member: cn=${username},ou=users,${ldapConfig.baseDN}`;

    try {
      execSync(`echo '${groupContent}' | ldapmodify -x -H ${ldapConfig.url} -D "${ldapConfig.bindDN}" -w "${ldapConfig.bindPassword}"`, 
        { encoding: 'utf8', stdio: 'inherit' });
      console.log('✅ User added to authelia_users group');
    } catch (error) {
      console.log('⚠️ Could not add to authelia_users group, creating it...');
      
      // Create the group
      const createGroupContent = `dn: cn=authelia_users,ou=groups,${ldapConfig.baseDN}
objectClass: top
objectClass: groupOfNames
cn: authelia_users
member: cn=${username},ou=users,${ldapConfig.baseDN}`;

      execSync(`echo '${createGroupContent}' | ldapadd -x -H ${ldapConfig.url} -D "${ldapConfig.bindDN}" -w "${ldapConfig.bindPassword}"`, 
        { encoding: 'utf8', stdio: 'inherit' });
      console.log('✅ Created authelia_users group and added user');
    }

    console.log('\n🎯 Authelia User Created Successfully');
    console.log('==================================');
    console.log(`👤 Username: ${username}`);
    console.log(`🔐 Password: ${password}`);
    console.log(`📧 Email: ${username}@home2500.local`);
    console.log(`👥 Group: authelia_users`);
    
    // Test authentication
    console.log('\n🔍 Testing authentication...');
    try {
      execSync(`ldapwhoami -x -H ${ldapConfig.url} -D "cn=${username},ou=users,${ldapConfig.baseDN}" -w "${password}"`, 
        { stdio: 'ignore' });
      console.log('✅ LDAP authentication test PASSED');
    } catch (error) {
      console.log('❌ LDAP authentication test FAILED');
    }
    
  } catch (error) {
    console.error('❌ Failed to create user:', error.message);
  }
}

// Reuse your existing loadEnv function
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

createAutheliaUser().catch(console.error);