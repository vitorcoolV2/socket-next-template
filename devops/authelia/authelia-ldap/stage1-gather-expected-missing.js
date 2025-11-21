import { readFile } from 'fs/promises';
import { exec } from 'child_process';
import * as yaml from 'yaml';
import { mkdirSync, writeFileSync, existsSync } from 'fs';

// Configuration
const envFilePath = '.env'; // Path to .env file
const autheliaConfigPath = './data/authelia/config/configuration.yml'; // Path to Authelia config
const outputDir = './ldap-setup'; // Directory to store generated files

// Ensure output directory exists
function ensureOutputDir(outputDir) {
  try {
    if (!existsSync(outputDir)) {
      mkdirSync(outputDir, { recursive: true });
      console.log(`Created output directory: ${outputDir}`);
    } else {
      console.log(`Output directory already exists: ${outputDir}`);
    }
  } catch (err) {
    console.error(`Failed to create or access output directory: ${outputDir}`, err.message);
    process.exit(1);
  }
}

// Call the function to ensure the directory exists
ensureOutputDir(outputDir);

/**
 * Load and parse .env file.
 */
async function loadEnv() {
  try {
    const envFileContent = await readFile(envFilePath, 'utf8');
    const envVars = {};
    envFileContent.split('\n').forEach((line) => {
      const [key, value] = line.split('=').map((str) => str.trim());
      if (key && value) envVars[key] = value;
    });
    return envVars;
  } catch (err) {
    console.error('Error reading .env file:', err.message);
    process.exit(1);
  }
}

/**
 * Load Authelia configuration.
 */
async function loadAutheliaConfig() {
  try {
    const fileContents = await readFile(autheliaConfigPath, 'utf8');
    return yaml.parse(fileContents);
  } catch (err) {
    console.error('Error reading Authelia configuration:', err.message);
    process.exit(1);
  }
}

/**
 * Extract groups from subject strings
 */
function extractGroupsFromSubjects(accessControlRules) {
  const groups = new Set();
  
  accessControlRules.forEach((rule) => {
    if (rule.subject && typeof rule.subject === 'string') {
      // Extract groups from subject patterns like:
      // "group:admins", "group:admins|group:developers", "group:users"
      const groupMatches = rule.subject.match(/group:([^|]+)/g);
      if (groupMatches) {
        groupMatches.forEach((match) => {
          const groupName = match.replace('group:', '');
          groups.add(groupName);
        });
      }
    }
  });
  
  return Array.from(groups);
}

/**
 * Verify groups exist in LDAP using ldapsearch.
 */
function verifyGroupsInLDAP(groups, ldapConfig) {
  const groupStatus = {};
  const promises = groups.map((group) => {
    return new Promise((resolve) => {
      const groupDN = `cn=${group},ou=groups,${ldapConfig.baseDN}`;
      const ldapSearchCmd = `ldapsearch -x -H ${ldapConfig.url} -D "${ldapConfig.bindDN}" -w "${ldapConfig.bindPassword}" -b "${groupDN}"`;

      exec(ldapSearchCmd, (error, stdout) => {
        groupStatus[group] = !(error || !stdout.includes('dn:')); // True if group exists, false otherwise
        resolve();
      });
    });
  });

  return Promise.all(promises).then(() => groupStatus);
}

/**
 * Validate subdomains using DNS resolution.
 */
function validateSubdomains(subdomains) {
  const subdomainStatus = {};
  const promises = subdomains.map((domain) => {
    return new Promise((resolve) => {
      const dnsLookupCmd = `nslookup ${domain} pihole.app-network`;
      exec(dnsLookupCmd, (error, stdout) => {
        subdomainStatus[domain] = !(error || stdout.includes('can\'t find')); // True if resolves, false otherwise
        if (error) console.error(`DNS lookup failed for ${domain}:`, error.message);
        resolve();
      });
    });
  });

  return Promise.all(promises).then(() => subdomainStatus);
}

/**
 * Generate a JSON status file for Authelia setup.
 */
function generateStatusFile(data) {
  const filePath = `${outputDir}/authelia-access-setup-status.json`;
  try {
    writeFileSync(filePath, JSON.stringify(data, null, 2));
    console.log(`Generated status file: ${filePath}`);
  } catch (err) {
    console.error(`Failed to write status file: ${filePath}`, err.message);
    process.exit(1);
  }
}

/**
 * Main function to process access control rules.
 */
async function main() {
  // Load .env file
  const env = await loadEnv();

  // Parse LDAP configuration from .env
  const ldapConfig = {
    url: 'ldap://localhost', // Replace with your LDAP server URL if not localhost
    bindDN: `cn=admin,dc=${env.LDAP_DOMAIN.replace('.', ',dc=')}`, // Construct admin DN
    bindPassword: env.LDAP_ADMIN_PASSWORD,
    baseDN: `dc=${env.LDAP_DOMAIN.replace('.', ',dc=')}`, // Construct base DN
  };

  console.log('Loaded LDAP configuration from .env:', {
    url: ldapConfig.url,
    bindDN: ldapConfig.bindDN,
    bindPassword: "***",
    baseDN: ldapConfig.baseDN,
  });

  // Load Authelia configuration
  const autheliaConfig = await loadAutheliaConfig();
  const accessControlRules = autheliaConfig.access_control?.rules || [];
  console.log(`Found ${accessControlRules.length} access control rules.`);

  // Extract subdomains
  const expectedSubdomains = Array.from(
    new Set(accessControlRules.filter((rule) => rule.domain).map((rule) => rule.domain))
  );
  console.log(`Expected subdomains: ${expectedSubdomains.join(', ')}`);

  // Validate subdomains
  const subdomainStatus = await validateSubdomains(expectedSubdomains);

  // Collect required groups from subject strings
  const expectedGroups = extractGroupsFromSubjects(accessControlRules);
  console.log(`Expected LDAP groups: ${expectedGroups.join(', ')}`);

  // Verify groups in LDAP
  const groupStatus = await verifyGroupsInLDAP(expectedGroups, ldapConfig);

  // Identify unresolved subdomains and missing groups
  const unresolvedDomains = expectedSubdomains.filter((domain) => !subdomainStatus[domain]);
  const missingGroups = expectedGroups.filter((group) => !groupStatus[group]);

  // Generate status data
  const statusData = {
    expected: {
      subdomains: expectedSubdomains,
      ldapGroups: expectedGroups,
    },
    missing: {
      pihole: {
        unresolvedDomains,
      },
      ldap: {
        missingGroups,
      },
    },
  };

  // Generate status file
  generateStatusFile(statusData);
}

main().catch((err) => {
  console.error('Error during execution:', err.message);
  process.exit(1);
});