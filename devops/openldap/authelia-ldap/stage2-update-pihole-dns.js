#!/usr/bin/env node

// DNS COMPUTER RESOLVE

import { execSync, exec } from 'child_process';
import fetch from 'node-fetch';
import https from 'https';
import { readFile } from 'fs/promises';

const SOURCE_DOCKER_NETWORK = 'app-network';
const HOME2500_LOCAL = [
  'pihole.home2500.local',
  'auth.home2500.local',
  'traefik.home2500.local',
  'auth.home2500.local',
  'portainer.home2500.local',
  'phpldapadmin.home2500.local',
];

const containerResourceMapper = (res) => res.split('.')[0];

/**
 * Load and parse .env file for LDAP configuration
 */
async function loadEnv(envFilePath = '.env') {
  try {
    const envFileContent = await readFile(envFilePath, 'utf8');
    const envVars = {};

    envFileContent.split('\n').forEach((line) => {
      const [key, value] = line.split('=').map((str) => str.trim());
      if (key && value) envVars[key] = value;
    });

    return envVars;
  } catch (error) {
    console.error('Error reading', envFilePath, 'file:', error.message);
    return {};
  }
}

/**
 * Validate subdomains using DNS resolution.
 */
function validateSubdomain(domain) {
  return new Promise((resolve) => {
    const dnsLookupCmd = `nslookup ${domain}`;
    exec(dnsLookupCmd, (error, stdout) => {
      const ret = !(error || stdout.includes("can't find")); // True if resolves, false otherwise
      if (error)
        console.error(`DNS lookup failed for ${domain}:`, error.message);
      resolve(ret);
    });
  });
}

class PiHoleExpectedSubdomainsRegistrar {
  unresolvedDomains = [];
  resolvedDomain = [];
  domainsToRegister = HOME2500_LOCAL;

  constructor(env) {
    this.env = env;
    this.session = null;
    this.expectedConfig = null;
    this.ldapDomain = env.LDAP_DOMAIN;
    this.networkMap = new Map();
  }

  async run() {
    console.log('🚀 Pi-hole Expected Subdomains Registration');
    console.log('===========================================\n');

    try {
      // Step 2: Load LDAP domain from .env file
      await this.loadLdapDomain();

      // Step 3: Discover Docker network containers with their actual IPs
      await this.discoverDockerNetwork();

      // Step 4: Authenticate with Pi-hole
      await this.authenticatePihole();

      // Step 5: Register docker network domains
      await this.registerDockerNetwork(SOURCE_DOCKER_NETWORK);

      // Step 6: Register expected subdomains with their actual container IPs
      await this.registerExpectedSubdomains();

      console.log('\n✅ All registrations completed successfully!');
    } catch (error) {
      console.error('❌ Registration failed:', error.message);
      process.exit(1);
    }
  }

  /**
   * Load expected configuration from status file
   */
  async loadExpectedConfiguration() {
    console.log(
      `   ✅ Loaded ${this.domainsToRegister.length} expected subdomains`
    );

    console.log('\n📋 Expected subdomains:');
    this.domainsToRegister.forEach(async (domain) => {
      const valid = await validateSubdomain(domain).catch((e) => {
        this.unresolvedDomain.push(domain);
        return false;
      });
      console.log(`   - ${domain} valid: ${valid}`);
    });

    if (this.unresolvedDomains.length > 0) {
      console.log('\n🔧 Domains to register:');
      this.unresolvedDomains.forEach((domain) => {
        console.log(`   - ${domain}`);
      });
    }
  }

  /**
   * Load LDAP domain from .env file
   */
  async loadLdapDomain() {
    console.log('\n📁 Loading LDAP configuration from .env file...');

    if (this.env.LDAP_DOMAIN) {
      this.ldapDomain = this.env.LDAP_DOMAIN;
      console.log(`   ✅ Using LDAP domain: ${this.ldapDomain}`);
    } else if (this.env.LDAP_ORGANISATION) {
      this.ldapDomain = `${this.env.LDAP_ORGANISATION.toLowerCase()}.local`;
      console.log(
        `   ⚠️  LDAP_DOMAIN not found, using derived domain: ${this.ldapDomain}`
      );
    } else {
      console.log(
        `   ⚠️  No LDAP configuration found, using default: ${this.ldapDomain}`
      );
    }
  }

  /**
   * Discover Docker network containers with their actual IPs
   */
  async discoverDockerNetwork() {
    console.log(
      `\n🔍 Discovering Docker ${SOURCE_DOCKER_NETWORK} containers...`
    );

    try {
      const networkInfo = JSON.parse(
        execSync(`docker network inspect ${SOURCE_DOCKER_NETWORK}`, {
          encoding: 'utf8',
        })
      )[0];

      console.log(`🌐 Network: ${networkInfo.Name}`);
      console.log(`   Subnet: ${networkInfo.IPAM.Config[0].Subnet}`);
      console.log(`   Gateway: ${networkInfo.IPAM.Config[0].Gateway}`);

      // Add gateway entry
      const gatewayIp = networkInfo.IPAM.Config[0].Gateway;
      this.networkMap.set('gateway', gatewayIp);

      console.log('\n🐳 Containers found with their IPs:');
      Object.values(networkInfo.Containers).forEach((container) => {
        const name = container.Name.replace('/', '');
        const ip = container.IPv4Address.split('/')[0];
        this.networkMap.set(name, ip);
        console.log(`   📦 ${name}.${SOURCE_DOCKER_NETWORK} → ${ip}`);
      });

      console.log(`\n📊 Total entries to register: ${this.networkMap.size}`);
    } catch (error) {
      throw new Error(`Docker network discovery failed: ${error.message}`);
    }
  }

  /**
   * Get container IP for a subdomain
   */
  getContainerIpForSubdomain(subdomain) {
    const containerName = subdomain.split('.')[0];
    return this.networkMap.get(containerName);
  }

  /**
   * Authenticate with Pi-hole API
   */
  async authenticatePihole() {
    console.log('\n🔐 Authenticating with Pi-hole...');

    try {
      const endpoint = '/api/auth';
      const authUrl = `${this.env.PIHOLE_URL}${endpoint}`;

      const httpsAgent = new https.Agent({
        rejectUnauthorized: false,
      });

      const response = await fetch(authUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          password: this.env.PIHOLE_PASSWORD,
        }),
        agent: httpsAgent,
      });

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${await response.text()}`);
      }

      const result = await response.json();

      if (result.session?.valid) {
        this.session = result.session;
        console.log('✅ Pi-hole authentication successful');
        console.log(`   Session ID: ${this.session.sid.substring(0, 10)}...`);
      } else {
        throw new Error(`Authentication failed: ${result.session?.message}`);
      }
    } catch (error) {
      throw new Error(`Pi-hole authentication failed: ${error.message}`);
    }
  }

  /**
   * Register expected subdomains with their actual container IPs
   */
  async registerExpectedSubdomains() {
    console.log('\n📡 Registering expected subdomains with Pi-hole...');
    console.log(
      `   Using actual container IPs from Docker ${SOURCE_DOCKER_NETWORK}\n`
    );

    const domainsToRegister = this.domainsToRegister;
    if (domainsToRegister.length === 0) {
      console.log('   ℹ️  No unresolved domains to register');
      return;
    }

    let successCount = 0;
    let errorCount = 0;
    let skippedCount = 0;

    for (const domain of domainsToRegister) {
      const containerName = containerResourceMapper(domain);
      const containerIp = this.getContainerIpForSubdomain(containerName);

      if (!containerIp) {
        console.log(
          `   ⚠️  ${domain} → SKIPPED (container not found in ${SOURCE_DOCKER_NETWORK})`
        );
        skippedCount++;
        continue;
      }

      try {
        await this.registerDnsEntry(domain, containerIp);
        console.log(`   ✅ ${domain} → ${containerIp}`);
        successCount++;
      } catch (error) {
        console.log(`   ❌ ${domain} → ${containerIp}: ${error.message}`);
        errorCount++;
      }

      // Small delay to avoid overwhelming the API
      await new Promise((resolve) => setTimeout(resolve, 100));
    }

    console.log(`\n📊 Expected Subdomains Registration Summary:`);
    console.log(`   ✅ Success: ${successCount}`);
    console.log(`   ❌ Errors: ${errorCount}`);
    console.log(`   ⚠️  Skipped: ${skippedCount} (containers not found)`);
  }

  /**
   * Register docker network domains
   */
  async registerDockerNetwork(dockerNetwork) {
    console.log(`\n🌐 Registering ${dockerNetwork} domains with Pi-hole...`);
    console.log(
      `   Each container will have its own ${dockerNetwork} domain\n`
    );

    let successCount = 0;
    let errorCount = 0;

    for (const [containerName, actualIp] of this.networkMap) {
      const domain = `${containerName}.${dockerNetwork}`;

      try {
        await this.registerDnsEntry(domain, actualIp);
        console.log(`   ✅ ${domain} → ${actualIp}`);
        successCount++;
      } catch (error) {
        console.log(`   ❌ ${domain} → ${actualIp}: ${error.message}`);
        errorCount++;
      }

      // Small delay to avoid overwhelming the API
      await new Promise((resolve) => setTimeout(resolve, 100));
    }

    console.log(`\n📊 ${dockerNetwork} Domains Registration Summary:`);
    console.log(`   ✅ Success: ${successCount}`);
    console.log(`   ❌ Errors: ${errorCount}`);
  }

  /**
   * Register a single DNS entry with Pi-hole
   */
  async registerDnsEntry(domain, ip) {
    const methods = [
      () => this.tryHostsConfigMethod(domain, ip),
      () => this.tryCustomDnsMethod(domain, ip),
      () => this.tryLegacyApiMethod(domain, ip),
    ];

    for (const method of methods) {
      try {
        await method();
        return; // Success
      } catch (error) {
        // Continue to next method
        continue;
      }
    }

    throw new Error('All registration methods failed');
  }

  /**
   * Method 1: Try hosts configuration
   */
  async tryHostsConfigMethod(domain, ip) {
    const endpoint = '/api/config/dns';
    const fullUrl = `${this.env.PIHOLE_URL}${endpoint}`;

    const currentHosts = await this.getCurrentHosts();
    const newHostEntry = `${ip} ${domain}`;

    const existingIndex = currentHosts.findIndex((host) =>
      host.includes(domain)
    );

    let updatedHosts;
    if (existingIndex >= 0) {
      updatedHosts = [...currentHosts];
      updatedHosts[existingIndex] = newHostEntry;
    } else {
      updatedHosts = [...currentHosts, newHostEntry];
    }

    const httpsAgent = new https.Agent({
      rejectUnauthorized: false,
    });

    const response = await fetch(fullUrl, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'X-FTL-SID': this.session.sid,
      },
      body: JSON.stringify({
        config: {
          dns: {
            hosts: updatedHosts,
          },
        },
      }),
      agent: httpsAgent,
    });

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${await response.text()}`);
    }

    await response.json();
  }

  /**
   * Method 2: Try custom DNS endpoint
   */
  async tryCustomDnsMethod(domain, ip) {
    const endpoint = '/api/config/customdns';
    const fullUrl = `${this.env.PIHOLE_URL}${endpoint}`;

    const httpsAgent = new https.Agent({
      rejectUnauthorized: false,
    });

    const response = await fetch(fullUrl, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'X-FTL-SID': this.session.sid,
      },
      body: JSON.stringify({
        config: {
          customdns: {
            [domain]: ip,
          },
        },
      }),
      agent: httpsAgent,
    });

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${await response.text()}`);
    }

    await response.json();
  }

  /**
   * Method 3: Try legacy API method
   */
  async tryLegacyApiMethod(domain, ip) {
    const endpoint = '/admin/api.php';
    const fullUrl = `${this.env.PIHOLE_URL}${endpoint}`;

    const params = new URLSearchParams({
      customdns: 'true',
      action: 'add',
      domain,
      ip,
      auth: this.env.PIHOLE_PASSWORD,
    });

    const httpsAgent = new https.Agent({
      rejectUnauthorized: false,
    });

    const response = await fetch(fullUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: params.toString(),
      agent: httpsAgent,
    });

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${await response.text()}`);
    }

    const result = await response.json();
    if (result !== '') {
      throw new Error(`Legacy API error: ${JSON.stringify(result)}`);
    }
  }

  /**
   * Get current hosts configuration from Pi-hole
   */
  async getCurrentHosts() {
    const endpoint = '/api/config/dns';
    const fullUrl = `${this.env.PIHOLE_URL}${endpoint}`;

    const httpsAgent = new https.Agent({
      rejectUnauthorized: false,
    });

    const response = await fetch(fullUrl, {
      method: 'GET',
      headers: {
        'X-FTL-SID': this.session.sid,
      },
      agent: httpsAgent,
    });

    if (!response.ok) {
      return []; // Return empty array if we can't get current hosts
    }

    const result = await response.json();
    return result.config?.dns?.hosts || [];
  }

  /**
   * Generate a comprehensive summary
   */
  generateRegistrationSummary() {
    console.log('\n🎯 COMPREHENSIVE REGISTRATION SUMMARY');
    console.log('====================================\n');

    const registeredExpectedDomains = this.unresolvedDomains.filter((domain) =>
      this.getContainerIpForSubdomain(domain)
    );

    console.log('📋 Expected Subdomains Registered:');
    console.log('----------------------------------');
    if (registeredExpectedDomains.length === 0) {
      console.log(
        '   ℹ️  No expected subdomains were registered (containers not found)'
      );
    } else {
      registeredExpectedDomains.forEach((domain) => {
        const containerIp = this.getContainerIpForSubdomain(domain);
        console.log(`   ✅ ${domain} → ${containerIp}`);
      });
    }

    console.log(`\n🔍 Test DNS resolution with:`);
    console.log(`   nslookup pihole.${this.ldapDomain} 127.0.0.1`);
    console.log(`   nslookup traefik.${this.ldapDomain} 127.0.0.1`);

    console.log(
      `\n💡 You now have ${this.ldapDomain} domains for expected services`
    );
  }
}

// Main execution
async function main() {
  const env = await loadEnv('.env');

  // Validate required environment variables
  if (!env.PIHOLE_PASSWORD) {
    console.error('❌ Missing PIHOLE_PASSWORD in .env file');
    process.exit(1);
  }

  const registrar = new PiHoleExpectedSubdomainsRegistrar(env);
  await registrar.run();
  registrar.generateRegistrationSummary();
}

main().catch((error) => {
  console.error('💥 Fatal error:', error);
  process.exit(1);
});
