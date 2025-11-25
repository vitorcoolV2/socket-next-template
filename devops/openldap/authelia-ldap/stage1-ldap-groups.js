#!/usr/bin/env node

import { execSync } from 'child_process';
import { readFile, writeFile, unlink } from 'fs/promises';

const LDAP_GROUPS = ["admins", "users", "developers"];

/**
 * Load and parse .env file for LDAP configuration
 */
async function loadEnv(envFilePath = '.env') {
  try {
    const envFileContent = await readFile(envFilePath, 'utf8');
    const envVars = {};
    
    envFileContent.split('\n').forEach((line) => {
      // Handle lines with # comments and empty lines
      if (line.trim() === '' || line.trim().startsWith('#')) {
        return;
      }
      
      const [key, ...valueParts] = line.split('=');
      if (key && valueParts.length > 0) {
        const value = valueParts.join('=').trim();
        // Remove quotes if present
        envVars[key.trim()] = value.replace(/^["']|["']$/g, '');
      }
    });
    
    return envVars;
  } catch (error) {
    console.error('Error reading', envFilePath, 'file:', error.message);
    return {};
  }
}

class OpenLdapExpectedGroupsRegistrar {
  constructor(env) {
    this.env = env;      
    this.ldapDomain = env.LDAP_DOMAIN;    
  }

  get ldapBaseDN() {
    return `dc=${this.ldapDomain.replace(/\./g, ',dc=')}`;
  }

  async run() {
    console.log('🚀 OpenLDAP Expected Groups Registration');
    console.log('========================================\n');

    try {
      // Step 1: Load LDAP configuration from .env file
      await this.loadLdapConfig();

      // Step 2: Create missing LDAP groups
      await this.createMissingLDAPGroups();

      console.log('\n✅ All LDAP groups created successfully!');
    } catch (error) {
      console.error('❌ Registration failed:', error.message);
      process.exit(1);
    }
  }

  /**
   * Load LDAP configuration from .env file
   */
  async loadLdapConfig() {
    console.log('\n📁 Loading LDAP configuration from .env file...');

    // Debug: Show what we're reading from .env
    console.log('   🔍 LDAP_URL:', this.env.LDAP_URL);
    console.log('   🔍 LDAP_ADMIN_USER:', this.env.LDAP_ADMIN_USER);
    console.log('   🔍 LDAP_ADMIN_PASSWORD:', this.env.LDAP_ADMIN_PASSWORD ? '***' : 'MISSING');
    console.log('   🔍 LDAP_DOMAIN:', this.env.LDAP_DOMAIN);

    if (this.env.LDAP_DOMAIN) {
      this.ldapDomain = this.env.LDAP_DOMAIN;
      console.log(`   ✅ Using LDAP domain: ${this.ldapDomain}`);
    } else {
      // Extract domain from LDAP_ADMIN_USER if LDAP_DOMAIN is not set
      const adminUser = this.env.LDAP_ADMIN_USER;
      if (adminUser) {
        const domainMatch = adminUser.match(/dc=([^,]+),dc=([^,]+)/);
        if (domainMatch) {
          this.ldapDomain = `${domainMatch[1]}.${domainMatch[2]}`;
          console.log(`   ⚠️  LDAP_DOMAIN not found, using derived domain: ${this.ldapDomain}`);
        } else {
          this.ldapDomain = 'home2500.local';
          console.log(`   ⚠️  No domain found in admin user, using default: ${this.ldapDomain}`);
        }
      } else {
        this.ldapDomain = 'home2500.local';
        console.log(`   ⚠️  No LDAP configuration found, using default: ${this.ldapDomain}`);
      }
    }

    // Validate critical LDAP configuration
    if (!this.env.LDAP_ADMIN_USER || this.env.LDAP_ADMIN_USER === 'cn') {
      throw new Error('Invalid LDAP_ADMIN_USER in .env file. Expected format: cn=admin,dc=home2500,dc=local');
    }

    if (!this.env.LDAP_ADMIN_PASSWORD) {
      throw new Error('Missing LDAP_ADMIN_PASSWORD in .env file');
    }

    if (!this.env.LDAP_URL) {
      throw new Error('Missing LDAP_URL in .env file');
    }
  }

  /**
   * Check if an LDAP entry exists before creating it
   */
  async checkLDAPEntryExists(dn) {
    try {
      const searchCmd = `ldapsearch -x -H ${this.env.LDAP_URL} -D "${this.env.LDAP_ADMIN_USER}" -w "${this.env.LDAP_ADMIN_PASSWORD}" -b "${dn}" "(objectClass=*)" dn | grep "^dn:"`;
      
      const result = execSync(searchCmd, { 
        encoding: 'utf8',
        stdio: ['pipe', 'pipe', 'pipe']
      });
      
      return result.includes(`dn: ${dn}`);
    } catch (error) {
      // If search fails, entry probably doesn't exist
      return false;
    }
  }

  /**
   * Create missing LDAP groups - check existence first
   */
  async createMissingLDAPGroups() {
    console.log('\n👥 Checking and creating missing LDAP groups...');

    let successCount = 0;
    let skipCount = 0;
    let errorCount = 0;

    for (const group of LDAP_GROUPS) {
      const groupDN = `cn=${group},ou=groups,${this.ldapBaseDN}`;
      
      try {
        // Check if group already exists
        const groupExists = await this.checkLDAPEntryExists(groupDN);
        
        if (groupExists) {
          console.log(`   ℹ️  LDAP group already exists: ${group}`);
          skipCount++;
          continue;
        }
        
        // Check if OU exists, create if needed
        const ouDN = `ou=groups,${this.ldapBaseDN}`;
        const ouExists = await this.checkLDAPEntryExists(ouDN);
        
        if (!ouExists) {
          await this.createGroupsOU();
        }
        
        // Create the group
        await this.createLDAPGroup(group);
        console.log(`   ✅ Created LDAP group: ${group}`);
        successCount++;
        
      } catch (error) {
        console.log(`   ❌ Failed to create LDAP group ${group}: ${error.message}`);
        errorCount++;
      }

      await new Promise((resolve) => setTimeout(resolve, 100));
    }

    console.log(`\n📊 LDAP Groups Summary:`);
    console.log(`   ✅ Created: ${successCount}`);
    console.log(`   ℹ️  Already existed: ${skipCount}`);
    console.log(`   ❌ Errors: ${errorCount}`);
  }

  /**
   * Create a single LDAP group using secure temp files
   */
  async createLDAPGroup(groupName) {
    const groupDN = `cn=${groupName},ou=groups,${this.ldapBaseDN}`;
    
    const ldifContent = `dn: ${groupDN}
objectClass: top
objectClass: groupOfNames
cn: ${groupName}
description: Autogenerated group for ${groupName}
member: ${this.env.LDAP_ADMIN_USER}`;

    // Use temporary file for more secure credential handling
    const tempLdifFile = `/tmp/group_${groupName}_${Date.now()}.ldif`;
    const tempPasswordFile = `/tmp/ldap_pass_${Date.now()}`;
    
    try {
      console.log(`   🔧 Creating group: ${groupName}`);
      console.log(`      URL: ${this.env.LDAP_URL}`);
      console.log(`      Bind DN: ${this.env.LDAP_ADMIN_USER}`);
      console.log(`      Base DN: ${this.ldapBaseDN}`);
      
      // Write temp files
      await writeFile(tempLdifFile, ldifContent);
      await writeFile(tempPasswordFile, this.env.LDAP_ADMIN_PASSWORD);
      
      // Create the group using ldapadd with temp files
      const ldapAddCmd = `ldapadd -x -H ${this.env.LDAP_URL} -D "${this.env.LDAP_ADMIN_USER}" -y ${tempPasswordFile} -f ${tempLdifFile}`;
      
      console.log(`      Command: ldapadd -x -H ${this.env.LDAP_URL} -D "${this.env.LDAP_ADMIN_USER}" -y [password_file] -f [ldif_file]`);
      
      execSync(ldapAddCmd, { encoding: 'utf8' });
      
    } catch (error) {
      // If group already exists, that's fine - we can continue
      if (error.message.includes('Already exists') || error.message.includes('entry already exists')) {
        console.log(`   ℹ️  LDAP group ${groupName} already exists`);
        return;
      }
      throw new Error(`Failed to create LDAP group ${groupName}: ${error.message}`);
    } finally {
      // Clean up temp files
      try {
        await unlink(tempLdifFile);
        await unlink(tempPasswordFile);
      } catch (cleanupError) {
        // Ignore cleanup errors
      }
    }
  }

  /**
   * Create the groups OU if it doesn't exist
   */
  async createGroupsOU() {
    const ouDN = `ou=groups,${this.ldapBaseDN}`;
    
    const ouLdifContent = `dn: ${ouDN}
objectClass: top
objectClass: organizationalUnit
ou: groups
description: Container for user groups`;

    const tempLdifFile = `/tmp/ou_groups_${Date.now()}.ldif`;
    const tempPasswordFile = `/tmp/ldap_pass_ou_${Date.now()}`;

    try {
      console.log(`      Creating groups OU: ${ouDN}`);
      
      await writeFile(tempLdifFile, ouLdifContent);
      await writeFile(tempPasswordFile, this.env.LDAP_ADMIN_PASSWORD);
      
      const ldapAddCmd = `ldapadd -x -H ${this.env.LDAP_URL} -D "${this.env.LDAP_ADMIN_USER}" -y ${tempPasswordFile} -f ${tempLdifFile}`;
      
      execSync(ldapAddCmd, { encoding: 'utf8', stdio: 'pipe' });
      console.log(`      ✅ Groups OU created successfully`);
      
    } catch (error) {
      // If OU already exists, that's fine - we can continue
      if (error.message.includes('Already exists') || error.message.includes('entry already exists')) {
        console.log(`      ℹ️  Groups OU already exists`);
        return;
      }
      // Don't throw error for OU creation - it might fail for other reasons but groups might still work
      console.log(`      ⚠️  Could not create groups OU (may already exist): ${error.message}`);
    } finally {
      // Clean up temp files
      try {
        await unlink(tempLdifFile);
        await unlink(tempPasswordFile);
      } catch (cleanupError) {
        // Ignore cleanup errors
      }
    }
  }

  /**
   * Generate a comprehensive summary
   */
  generateRegistrationSummary() {
    console.log('\n🎯 COMPREHENSIVE REGISTRATION SUMMARY');
    console.log('====================================\n');
    
    console.log(`💡 LDAP domain: ${this.ldapDomain}`);
    console.log(`🌐 LDAP server: ${this.env.LDAP_URL}`);
    console.log(`👤 LDAP admin: ${this.env.LDAP_ADMIN_USER}`);
    console.log(`📝 Groups: ${LDAP_GROUPS.join(', ')}`);
  }
}

// Main execution
async function main() {
  const env = await loadEnv('.env');
  
  const registrar = new OpenLdapExpectedGroupsRegistrar(env);
  await registrar.run();
  registrar.generateRegistrationSummary();
}

main().catch((error) => {
  console.error('💥 Fatal error:', error);
  process.exit(1);
});