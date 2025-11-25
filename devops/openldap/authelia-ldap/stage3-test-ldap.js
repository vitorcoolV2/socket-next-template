#!/usr/bin/env node

import { execSync } from 'child_process';
import { readFile } from 'fs/promises';
import { createInterface } from 'readline';

/**
 * Load and parse .env file for LDAP configuration
 */
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

/**
 * Test LDAP connection before proceeding
 */
function testLDAPConnection(ldapConfig) {
  try {
    console.log('🔍 Testing LDAP connection...');

    // Test basic connection and authentication
    const testCmd = `ldapsearch -x -H ${ldapConfig.url} -D "${ldapConfig.bindDN}" -w "${ldapConfig.bindPassword}" -b "${ldapConfig.baseDN}" -s base "(objectClass=*)" dn 2>&1`;
    const result = execSync(testCmd, { encoding: 'utf8' });

    if (result.includes('Invalid credentials')) {
      throw new Error('Invalid LDAP admin credentials');
    }

    console.log('✅ LDAP connection successful');
    return true;
  } catch (error) {
    console.error('❌ LDAP connection failed:', error.message);

    // Provide helpful error messages
    if (error.message.includes('Invalid credentials')) {
      console.log('💡 Check your LDAP_ADMIN_PASSWORD in the .env file');
    } else if (error.message.includes("Can't contact LDAP server")) {
      console.log('💡 Check if the LDAP server is running and accessible');
      console.log('💡 Verify the LDAP_URL in your .env file');
    } else if (error.status === 32) {
      console.log('💡 The base DN might not exist yet, but we can continue...');
      return true; // Continue anyway for initial setup
    }

    return false;
  }
}

/**
 * Ensure basic LDAP structure exists
 */
function ensureLDAPStructure(ldapConfig) {
  try {
    // Check if users OU exists, create if not
    const checkUsersOU = `ldapsearch -x -H ${ldapConfig.url} -D "${ldapConfig.bindDN}" -w "${ldapConfig.bindPassword}" -b "ou=users,${ldapConfig.baseDN}" -s base dn 2>&1`;
    execSync(checkUsersOU, { encoding: 'utf8' });
    console.log('✅ Users OU exists');
  } catch (error) {
    console.log('📁 Creating users OU...');

    // Create users OU
    const createUsersOU = `dn: ou=users,${ldapConfig.baseDN}
objectClass: top
objectClass: organizationalUnit
ou: users`;

    try {
      execSync(
        `echo '${createUsersOU}' | ldapadd -x -H ${ldapConfig.url} -D "${ldapConfig.bindDN}" -w "${ldapConfig.bindPassword}" 2>&1`,
        { encoding: 'utf8' }
      );
      console.log('✅ Created users OU');
    } catch (createError) {
      console.log('⚠️ Could not create users OU (might already exist)');
    }
  }

  try {
    // Check if groups OU exists, create if not
    const checkGroupsOU = `ldapsearch -x -H ${ldapConfig.url} -D "${ldapConfig.bindDN}" -w "${ldapConfig.bindPassword}" -b "ou=groups,${ldapConfig.baseDN}" -s base dn 2>&1`;
    execSync(checkGroupsOU, { encoding: 'utf8' });
    console.log('✅ Groups OU exists');
  } catch (error) {
    console.log('📁 Creating groups OU...');

    // Create groups OU
    const createGroupsOU = `dn: ou=groups,${ldapConfig.baseDN}
objectClass: top
objectClass: organizationalUnit
ou: groups`;

    try {
      execSync(
        `echo '${createGroupsOU}' | ldapadd -x -H ${ldapConfig.url} -D "${ldapConfig.bindDN}" -w "${ldapConfig.bindPassword}" 2>&1`,
        { encoding: 'utf8' }
      );
      console.log('✅ Created groups OU');
    } catch (createError) {
      console.log('⚠️ Could not create groups OU (might already exist)');
    }
  }
}

/**
 * Enhanced list users with better error handling
 */
function listUsers(ldapConfig) {
  try {
    console.log('\n👥 Listing LDAP Users');
    console.log('====================');

    const command = `ldapsearch -x -H ${ldapConfig.url} -D "${ldapConfig.bindDN}" -w "${ldapConfig.bindPassword}" -b "ou=users,${ldapConfig.baseDN}" "(objectClass=inetOrgPerson)" cn mail displayName 2>&1`;
    const result = execSync(command, { encoding: 'utf8' });

    // Check if no users found
    if (result.includes('numEntries: 0') || !result.includes('cn:')) {
      console.log('ℹ️ No users found in the directory');
      return [];
    }

    const users = [];
    const lines = result.split('\n');
    let currentUser = {};

    for (const line of lines) {
      if (line.startsWith('dn: ')) {
        if (currentUser.cn) users.push(currentUser);
        currentUser = {};
      } else if (line.startsWith('cn: ')) {
        currentUser.cn = line.substring(4);
      } else if (line.startsWith('mail: ')) {
        currentUser.mail = line.substring(6);
      } else if (line.startsWith('displayName: ')) {
        currentUser.displayName = line.substring(13);
      }
    }

    if (currentUser.cn) users.push(currentUser);

    users.forEach((user) => {
      console.log(`📛 ${user.cn} (${user.displayName || 'No name'})`);
      console.log(`   📧 ${user.mail || 'No email'}`);
      console.log('   ---');
    });

    console.log(`Total users: ${users.length}`);
    return users;
  } catch (error) {
    if (error.status === 32) {
      console.log('ℹ️ No users found or users OU does not exist');
      return [];
    }
    console.error('❌ Failed to list users:', error.message);
    return [];
  }
}

// ... (keep the existing parseArgs, showHelp, escapeDN, userExists,
// resetUserPassword, deleteUser, isUserInGroup, addUserToGroup functions)

/**
 * Main function with enhanced error handling
 */
async function main() {
  try {
    const args = parseArgs();
    const env = await loadEnv('.env');

    const baseDN = (env.LDAP_DOMAIN || 'home2500.local')
      .split('.')
      .map((dc) => `dc=${dc}`)
      .join(',');

    const ldapConfig = {
      url: env.LDAP_URL || 'ldap://openldap.app-network:389',
      bindDN: `cn=admin,${baseDN}`,
      bindPassword: env.LDAP_ADMIN_PASSWORD,
      baseDN,
    };

    // Test connection first
    if (!testLDAPConnection(ldapConfig)) {
      process.exit(1);
    }

    // Ensure basic structure exists
    ensureLDAPStructure(ldapConfig);

    switch (args.command) {
      case 'list':
        listUsers(ldapConfig);
        break;

      case 'create':
        // ... (existing create logic)
        break;

      case 'delete':
        // ... (existing delete logic)
        break;

      default:
        console.error(`❌ Unknown command: ${args.command}`);
        showHelp();
        process.exit(1);
    }
  } catch (error) {
    console.error('❌ Script execution failed:', error.message);
    process.exit(1);
  }
}

main().catch(console.error);
