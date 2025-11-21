#!/usr/bin/env node

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

/**
 * Load expected configuration from status file
 */
async function loadExpectedConfig(configFilePath = './ldap-setup/authelia-access-setup-status.json') {
  try {
    const configContent = await readFile(configFilePath, 'utf8');
    return JSON.parse(configContent);
  } catch (error) {
    console.error('Error reading', configFilePath, 'file:', error.message);
    process.exit(1);
  }
}

class OpenLdapExpectedGroupsRegistrar {
  constructor(env) {
    this.env = env;  
    this.expectedConfig = null;
    this.ldapDomain = env.LDAP_DOMAIN;    
  }

  async run() {
    console.log('🚀 OpenLDAP Expected Groups Registration');
    console.log('========================================\n');

    try {
      // Step 1: Load expected configuration from status file
      await this.loadExpectedConfiguration();

      // Step 2: Load LDAP configuration from .env file
      await this.loadLdapConfig();

      // Step 3: Create missing LDAP groups
      await this.createMissingLDAPGroups();

      console.log('\n✅ All LDAP groups created successfully!');
    } catch (error) {
      console.error('❌ Registration failed:', error.message);
      process.exit(1);
    }
  }

  /**
   * Load expected configuration from status file
   */
  async loadExpectedConfiguration() {
    console.log('📁 Loading expected configuration from status file...');

    this.expectedConfig = await loadExpectedConfig();
 
    console.log(`   ✅ Loaded ${this.expectedConfig.expected.ldapGroups.length} expected LDAP groups`);
    console.log(`   ✅ ${this.expectedConfig.missing.ldap.missingGroups.length} LDAP groups need creation`);

    console.log('\n👥 Expected LDAP groups:');
    this.expectedConfig.expected.ldapGroups.forEach((group) => {
      console.log(`   - ${group}`);
    });

    if (this.expectedConfig.missing.ldap.missingGroups.length > 0) {
      console.log('\n🔧 LDAP groups to create:');
      this.expectedConfig.missing.ldap.missingGroups.forEach((group) => {
        console.log(`   - ${group}`);
      });
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
   * Create missing LDAP groups
   */
  async createMissingLDAPGroups() {
    console.log('\n👥 Creating missing LDAP groups...');

    const missingGroups = this.expectedConfig.missing.ldap.missingGroups;
    
    if (missingGroups.length === 0) {
      console.log('   ℹ️  No missing LDAP groups to create');
      return;
    }

    let successCount = 0;
    let errorCount = 0;

    for (const group of missingGroups) {
      try {
        await this.createLDAPGroup(group);
        console.log(`   ✅ Created LDAP group: ${group}`);
        successCount++;
      } catch (error) {
        console.log(`   ❌ Failed to create LDAP group ${group}: ${error.message}`);
        errorCount++;
      }

      // Small delay to avoid overwhelming the LDAP server
      await new Promise((resolve) => setTimeout(resolve, 100));
    }

    console.log(`\n📊 LDAP Groups Creation Summary:`);
    console.log(`   ✅ Success: ${successCount}`);
    console.log(`   ❌ Errors: ${errorCount}`);
  }

  /**
   * Create a single LDAP group
   */
  async createLDAPGroup(groupName) {
    const ldapConfig = {
      url: this.env.LDAP_URL,
      bindDN: this.env.LDAP_ADMIN_USER,
      bindPassword: this.env.LDAP_ADMIN_PASSWORD,
      baseDN: `dc=${this.ldapDomain.replace('.', ',dc=')}`,
    };

    console.log(`   🔧 Creating group: ${groupName}`);
    console.log(`      URL: ${ldapConfig.url}`);
    console.log(`      Bind DN: ${ldapConfig.bindDN}`);
    console.log(`      Base DN: ${ldapConfig.baseDN}`);

    const groupDN = `cn=${groupName},ou=groups,${ldapConfig.baseDN}`;
    
    // Create LDIF content for the group
    const ldifContent = `dn: ${groupDN}
objectClass: top
objectClass: groupOfNames
cn: ${groupName}
description: Autogenerated group for ${groupName}
member: cn=dummy,${ldapConfig.baseDN}`;

    try {
      // First, try to create the groups OU if it doesn't exist
      await this.createGroupsOU(ldapConfig);
      
      // Create the group using ldapadd
      const ldapAddCmd = `echo '${ldifContent}' | ldapadd -x -H ${ldapConfig.url} -D "${ldapConfig.bindDN}" -w "${ldapConfig.bindPassword}"`;
      
      console.log(`      Command: ldapadd -x -H ${ldapConfig.url} -D "${ldapConfig.bindDN}" -w "***"`);
      
      execSync(ldapAddCmd, { encoding: 'utf8' });
    } catch (error) {
      // If group already exists, that's fine - we can continue
      if (error.message.includes('Already exists') || error.message.includes('entry already exists')) {
        console.log(`   ℹ️  LDAP group ${groupName} already exists`);
        return;
      }
      throw new Error(`Failed to create LDAP group ${groupName}: ${error.message}`);
    }
  }

  /**
   * Create the groups OU if it doesn't exist
   */
  async createGroupsOU(ldapConfig) {
    const ouDN = `ou=groups,${ldapConfig.baseDN}`;
    
    const ouLdifContent = `dn: ${ouDN}
objectClass: top
objectClass: organizationalUnit
ou: groups
description: Container for user groups`;

    try {
      const ldapAddCmd = `echo '${ouLdifContent}' | ldapadd -x -H ${ldapConfig.url} -D "${ldapConfig.bindDN}" -w "${ldapConfig.bindPassword}"`;
      console.log(`      Creating groups OU: ${ouDN}`);
      execSync(ldapAddCmd, { encoding: 'utf8' });
      console.log(`      ✅ Groups OU created successfully`);
    } catch (error) {
      // If OU already exists, that's fine - we can continue
      if (error.message.includes('Already exists') || error.message.includes('entry already exists')) {
        console.log(`      ℹ️  Groups OU already exists`);
        return;
      }
      throw new Error(`Failed to create groups OU: ${error.message}`);
    }
  }

  /**
   * Generate a comprehensive summary
   */
  generateRegistrationSummary() {
    console.log('\n🎯 COMPREHENSIVE REGISTRATION SUMMARY');
    console.log('====================================\n');

    console.log('👥 LDAP Groups Status:');
    console.log('----------------------');
    console.log(`   Expected groups: ${this.expectedConfig.expected.ldapGroups.length}`);
    console.log(`   Created groups: ${this.expectedConfig.missing.ldap.missingGroups.length}`);
    
    console.log('\n📋 All Required LDAP Groups:');
    this.expectedConfig.expected.ldapGroups.forEach((group) => {
      console.log(`   ✅ ${group}`);
    });

    console.log(`\n💡 LDAP domain: ${this.ldapDomain}`);
    console.log(`🌐 LDAP server: ${this.env.LDAP_URL}`);
    console.log(`👤 LDAP admin: ${this.env.LDAP_ADMIN_USER}`);
    console.log(`👥 Total LDAP groups configured: ${this.expectedConfig.expected.ldapGroups.length}`);
    console.log(`📝 Groups: ${this.expectedConfig.expected.ldapGroups.join(', ')}`);
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