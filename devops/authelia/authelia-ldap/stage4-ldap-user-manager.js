// stage4-ldap-user-manager-enhanced.js
// #!/usr/bin/env node

import { execSync } from 'child_process';
import { readFile } from 'fs/promises';

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
 * Parse command line arguments properly
 */
function parseArgs() {
  const args = process.argv.slice(2);
  const result = {
    command: null,
    username: null,
    password: null,
    fullName: null,
    groups: ['users'],
    force: false
  };

  if (args.length === 0) {
    showHelp();
    process.exit(1);
  }

  result.command = args[0];

  if (['create', 'delete'].includes(result.command)) {
    let i = 1;
    
    while (i < args.length) {
      const arg = args[i];
      
      if (arg === '-p' || arg === '--password') {
        if (i + 1 < args.length) {
          result.password = args[i + 1];
          i += 2;
        } else {
          console.error('❌ Password value is required after --password flag');
          process.exit(1);
        }
      } else if (arg === '-f' || arg === '--full-name') {
        if (i + 1 < args.length) {
          result.fullName = args[i + 1];
          i += 2;
        } else {
          console.error('❌ Full name value is required after --full-name flag');
          process.exit(1);
        }
      } else if (arg === '-g' || arg === '--groups') {
        if (i + 1 < args.length) {
          result.groups = args[i + 1].split(',').map(g => g.trim());
          i += 2;
        } else {
          console.error('❌ Groups value is required after --groups flag');
          process.exit(1);
        }
      } else if (arg === '--force') {
        result.force = true;
        i++;
      } else if (arg.startsWith('-')) {
        console.error(`❌ Unknown option: ${arg}`);
        showHelp();
        process.exit(1);
      } else {
        // This should be the username
        if (!result.username) {
          result.username = arg;
          i++;
        } else {
          console.error(`❌ Unexpected argument: ${arg}`);
          showHelp();
          process.exit(1);
        }
      }
    }
  }

  return result;
}

/**
 * Show help information
 */
function showHelp() {
  console.log(`
LDAP User Management Tool
=========================

Usage: node stage4-ldap-user-manager.js <command> [options]

Commands:
  list                               List all users
  create <username> [options]        Create a new user
  delete <username> [--force]        Delete a user

Options for create:
  -p, --password PASSWORD   User password (required)
  -f, --full-name NAME      User's full name [default: username]
  -g, --groups GROUPS       Comma-separated group list [default: users]

Options for delete:
  --force                   Skip confirmation prompt

Examples:
  node stage4-ldap-user-manager.js list
  node stage4-ldap-user-manager.js create john -p "secret123" -f "John Doe" -g "admins,users"
  node stage4-ldap-user-manager.js delete john --force
`);
}

/**
 * Escape LDAP DN special characters
 */
function escapeDN(string) {
  return string.replace(/[,+"\\<>;]/g, '\\$&');
}

/**
 * Check if user exists
 */
function userExists(username, ldapConfig) {
  const escapedUsername = escapeDN(username);
  try {
    const checkUserCmd = `ldapsearch -x -H ${ldapConfig.url} -D "${ldapConfig.bindDN}" -w "${ldapConfig.bindPassword}" -b "cn=${escapedUsername},ou=users,${ldapConfig.baseDN}" -s base dn 2>/dev/null`;
    const result = execSync(checkUserCmd, { encoding: 'utf8' });
    return result.includes(`cn=${escapedUsername}`);
  } catch (error) {
    return false;
  }
}

/**
 * Reset user password
 */
function resetUserPassword(username, password, ldapConfig) {
  const escapedUsername = escapeDN(username);
  const passwordContent = `dn: cn=${escapedUsername},ou=users,${ldapConfig.baseDN}
changetype: modify
replace: userPassword
userPassword: ${password}`;

  try {
    console.log(`\n🔐 Resetting password for user: ${username}`);
    execSync(`echo '${passwordContent}' | ldapmodify -x -H ${ldapConfig.url} -D "${ldapConfig.bindDN}" -w "${ldapConfig.bindPassword}"`, 
      { encoding: 'utf8', stdio: 'inherit' });
    console.log('✅ Password reset successfully');
    return true;
  } catch (error) {
    console.error('❌ Failed to reset password:', error.message);
    return false;
  }
}

/**
 * Delete user
 */
function deleteUser(username, ldapConfig, force = false) {
  const escapedUsername = escapeDN(username);
  
  if (!force) {
    console.log(`⚠️  Are you sure you want to delete user '${username}'?`);
    console.log('   This action cannot be undone.');
    console.log('   Use --force to skip this confirmation.');
    return false;
  }

  try {
    console.log(`🗑️  Deleting user: ${username}`);
    execSync(`ldapdelete -x -H ${ldapConfig.url} -D "${ldapConfig.bindDN}" -w "${ldapConfig.bindPassword}" "cn=${escapedUsername},ou=users,${ldapConfig.baseDN}"`, 
      { encoding: 'utf8', stdio: 'inherit' });
    console.log('✅ User deleted successfully');
    return true;
  } catch (error) {
    console.error('❌ Failed to delete user:', error.message);
    return false;
  }
}

/**
 * Check if user is already in group
 */
function isUserInGroup(username, group, ldapConfig) {
  const escapedUsername = escapeDN(username);
  const escapedGroup = escapeDN(group);
  
  try {
    const command = `ldapsearch -x -H ${ldapConfig.url} -D "${ldapConfig.bindDN}" -w "${ldapConfig.bindPassword}" -b "cn=${escapedGroup},ou=groups,${ldapConfig.baseDN}" "(member=cn=${escapedUsername},ou=users,${ldapConfig.baseDN})" dn 2>/dev/null`;
    const result = execSync(command, { encoding: 'utf8' });
    return result.includes(`dn: cn=${escapedGroup},ou=groups,${ldapConfig.baseDN}`);
  } catch (error) {
    return false;
  }
}

/**
 * Add user to group (only if not already a member)
 */
function addUserToGroup(username, group, ldapConfig) {
  const escapedUsername = escapeDN(username);
  const escapedGroup = escapeDN(group);
  
  // Check if user is already in group
  if (isUserInGroup(username, group, ldapConfig)) {
    console.log(`ℹ️ User ${username} is already in group ${group}`);
    return true;
  }

  // First, check if group exists
  let groupExists = false;
  try {
    const checkGroupCmd = `ldapsearch -x -H ${ldapConfig.url} -D "${ldapConfig.bindDN}" -w "${ldapConfig.bindPassword}" -b "cn=${escapedGroup},ou=groups,${ldapConfig.baseDN}" -s base dn 2>/dev/null`;
    const result = execSync(checkGroupCmd, { encoding: 'utf8' });
    groupExists = result.includes(`dn: cn=${escapedGroup},ou=groups,${ldapConfig.baseDN}`);
  } catch (error) {
    groupExists = false;
  }

  if (!groupExists) {
    console.log(`⚠️ Group ${group} does not exist, creating it first...`);
    
    // Create the group
    const createGroupContent = `dn: cn=${escapedGroup},ou=groups,${ldapConfig.baseDN}
objectClass: top
objectClass: groupOfNames
cn: ${group}
member: cn=${escapedUsername},ou=users,${ldapConfig.baseDN}`;

    try {
      execSync(`echo '${createGroupContent}' | ldapadd -x -H ${ldapConfig.url} -D "${ldapConfig.bindDN}" -w "${ldapConfig.bindPassword}"`, 
        { encoding: 'utf8', stdio: 'inherit' });
      console.log(`✅ Created group ${group} and added user`);
      return true;
    } catch (error) {
      console.error(`❌ Failed to create group ${group}:`, error.message);
      return false;
    }
  }

  // Group exists, add user to it
  const groupContent = `dn: cn=${escapedGroup},ou=groups,${ldapConfig.baseDN}
changetype: modify
add: member
member: cn=${escapedUsername},ou=users,${ldapConfig.baseDN}`;

  try {
    console.log(`\n➕ Adding user to ${group} group`);
    execSync(`echo '${groupContent}' | ldapmodify -x -H ${ldapConfig.url} -D "${ldapConfig.bindDN}" -w "${ldapConfig.bindPassword}"`, 
      { encoding: 'utf8', stdio: 'inherit' });
    console.log(`✅ User added to ${group} group`);
    return true;
  } catch (error) {
    console.error(`❌ Could not add user to ${group}: ${error.message}`);
    return false;
  }
}

/**
 * List all users
 */
function listUsers(ldapConfig) {
  try {
    console.log('\n👥 Listing LDAP Users');
    console.log('====================');
    
    const command = `ldapsearch -x -H ${ldapConfig.url} -D "${ldapConfig.bindDN}" -w "${ldapConfig.bindPassword}" -b "ou=users,${ldapConfig.baseDN}" "(objectClass=inetOrgPerson)" cn mail displayName`;
    const result = execSync(command, { encoding: 'utf8' });
    
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
    
    users.forEach(user => {
      console.log(`📛 ${user.cn} (${user.displayName || 'No name'})`);
      console.log(`   📧 ${user.mail || 'No email'}`);
      console.log('   ---');
    });
    
    console.log(`Total users: ${users.length}`);
    return users;
  } catch (error) {
    console.error('❌ Failed to list users:', error.message);
    return [];
  }
}

/**
 * Create or update LDAP user
 */
async function main() {
  const args = parseArgs();
  const env = await loadEnv('.env');
  const baseDN = (env.LDAP_DOMAIN||'').split('.').map(dc=>`dc=${dc}`).join(',');
  const ldapConfig = {
    url: env.LDAP_URL || 'ldap://openldap.app-network:389',
    bindDN: `cn=admin,${baseDN}`,
    bindPassword: env.LDAP_ADMIN_PASSWORD,
    baseDN,
  };

  switch (args.command) {
    case 'list':
      listUsers(ldapConfig);
      break;

    case 'delete':
      if (!args.username) {
        console.error('❌ Username is required for delete command');
        process.exit(1);
      }
      
      if (!userExists(args.username, ldapConfig)) {
        console.error(`❌ User '${args.username}' does not exist`);
        process.exit(1);
      }
      
      deleteUser(args.username, ldapConfig, args.force);
      break;

    case 'create':
      if (!args.username) {
        console.error('❌ Username is required for create command');
        process.exit(1);
      }

      if (!args.password) {
        console.error('❌ Password is required for create command (use -p or --password)');
        process.exit(1);
      }

      args.fullName = args.fullName || args.username;

      console.log('🚀 Creating/Updating LDAP User');
      console.log('==============================\n');
      console.log(`Username: ${args.username}`);
      console.log(`Full Name: ${args.fullName}`);
      console.log(`Groups: ${args.groups.join(', ')}`);

      let userAlreadyExists = userExists(args.username, ldapConfig);

      if (userAlreadyExists) {
        console.log(`\nℹ️ User ${args.username} already exists, resetting password...`);
        if (resetUserPassword(args.username, args.password, ldapConfig)) {
          console.log('✅ Password updated successfully');
        }
      } else {
        // Create new user
        try {
          // Create user
          const userContent = `dn: cn=${args.username},ou=users,${ldapConfig.baseDN}
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
cn: ${args.username}
sn: ${args.fullName}
givenName: ${args.fullName.split(' ')[0]}
uid: ${args.username}
userPassword: ${args.password}
displayName: ${args.fullName}
mail: ${args.username}@home2500.local`;

          console.log(`\n👤 Creating user: ${args.username}`);
          execSync(`echo '${userContent}' | ldapadd -x -H ${ldapConfig.url} -D "${ldapConfig.bindDN}" -w "${ldapConfig.bindPassword}"`, 
            { encoding: 'utf8', stdio: 'inherit' });
          console.log('✅ User created successfully');
        } catch (error) {
          console.error('❌ Failed to create user:', error.message);
          process.exit(1);
        }
      }

      // Add user to groups
      for (const group of args.groups) {
        if (userAlreadyExists) {
          addUserToGroup(args.username, group, ldapConfig);
        } else {
          addUserToGroup(args.username, group, ldapConfig);
        }
      }

      console.log('\n🎯 User Creation/Update Complete');
      console.log('===============================');
      console.log(`👤 User: ${args.username}`);
      console.log(`📧 Email: ${args.username}@home2500.local`);
      console.log(`👥 Groups: ${args.groups.join(', ')}`);
      console.log(`🔐 Password: ${args.password}`);
      console.log(`📝 Status: ${userAlreadyExists ? 'Updated existing user' : 'Created new user'}`);
      break;

    default:
      console.error(`❌ Unknown command: ${args.command}`);
      showHelp();
      process.exit(1);
  }
}

main().catch(console.error);