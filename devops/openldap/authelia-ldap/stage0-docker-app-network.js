#!/usr/bin/env node

import { execSync } from 'child_process';
import fetch from 'node-fetch';
import https from 'https';
import { readFile } from 'fs/promises';



/**
 * Load and parse .env file.
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
  } catch (err) {
    console.error('Error reading', envFilePath, 'file:', err.message);
    process.exit(1);
  }
}

class PiHoleNetworkRegistrar {
  constructor(config) {
    this.config = config;
    this.session = null;
    this.networkMap = new Map();
  }

  async run() {
    console.log('🚀 Pi-hole Network Registration');
    console.log('===============================\n');

    try {
      // Step 1: Discover Docker app-network containers with their actual IPs
      await this.discoverDockerNetwork();

      // Step 2: Authenticate with Pi-hole
      await this.authenticatePihole();

      // Step 3: Register all containers with their actual IPs
      await this.registerNetworkWithPihole();

      console.log('\n✅ Network registration completed successfully!');

    } catch (error) {
      console.error('❌ Registration failed:', error.message);
      process.exit(1);
    }
  }

  /**
   * Discover Docker app-network containers with their actual IPs
   */
  async discoverDockerNetwork() {
    console.log('🔍 Discovering Docker app-network containers...');

    try {
      const networkInfo = JSON.parse(
        execSync('docker network inspect app-network', { encoding: 'utf8' })
      )[0];

      console.log(`🌐 Network: ${networkInfo.Name}`);
      console.log(`   Subnet: ${networkInfo.IPAM.Config[0].Subnet}`);
      console.log(`   Gateway: ${networkInfo.IPAM.Config[0].Gateway}`);

      // Add gateway entry (only gateway points to gateway IP)
      const gatewayIp = networkInfo.IPAM.Config[0].Gateway;
      this.networkMap.set('gateway', gatewayIp);

      console.log('\n🐳 Containers found with their IPs:');
      for (const [containerId, container] of Object.entries(networkInfo.Containers)) {
        const name = container.Name.replace('/', '');
        const ip = container.IPv4Address.split('/')[0];
        this.networkMap.set(name, ip);
        console.log(`   📦 ${name}.app-network → ${ip}`);
      }

      console.log(`\n📊 Total entries to register: ${this.networkMap.size}`);

    } catch (error) {
      throw new Error(`Docker network discovery failed: ${error.message}`);
    }
  }

  /**
   * Authenticate with Pi-hole API
   */
  async authenticatePihole() {
    console.log('\n🔐 Authenticating with Pi-hole...');

    try {
      const endpoint = "/api/auth";
      const authUrl = `${this.config.pihole.url}${endpoint}`;

      const httpsAgent = new https.Agent({
        rejectUnauthorized: false,
      });

      const response = await fetch(authUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          password: this.config.pihole.password
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
   * Register all network entries with Pi-hole using actual container IPs
   */
  async registerNetworkWithPihole() {
    console.log('\n📡 Registering app-network DNS entries with Pi-hole...');
    console.log('   Each container will resolve to its actual IP in the app-network\n');

    let successCount = 0;
    let errorCount = 0;

    for (const [containerName, actualIp] of this.networkMap) {
      const domain = `${containerName}.app-network`;
      
      try {
        await this.registerDnsEntry(domain, actualIp); // Use the actual container IP
        console.log(`   ✅ ${domain} → ${actualIp}`);
        successCount++;
      } catch (error) {
        console.log(`   ❌ ${domain} → ${actualIp}: ${error.message}`);
        errorCount++;
      }

      // Small delay to avoid overwhelming the API
      await new Promise(resolve => setTimeout(resolve, 100));
    }

    console.log(`\n📊 Registration Summary:`);
    console.log(`   ✅ Success: ${successCount}`);
    console.log(`   ❌ Errors: ${errorCount}`);
  }

  /**
   * Register a single DNS entry with Pi-hole
   */
  async registerDnsEntry(domain, ip) {
    // Try multiple methods since Pi-hole API can be tricky
    const methods = [
      () => this.tryHostsConfigMethod(domain, ip),
      () => this.tryCustomDnsMethod(domain, ip),
      () => this.tryLegacyApiMethod(domain, ip)
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
    const endpoint = "/api/config/dns";
    const fullUrl = `${this.config.pihole.url}${endpoint}`;

    // First get current hosts
    const currentHosts = await this.getCurrentHosts();
    const newHostEntry = `${ip} ${domain}`;

    // Check if entry already exists
    const existingIndex = currentHosts.findIndex(host => 
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
        'X-FTL-SID': this.session.sid
      },
      body: JSON.stringify({
        config: {
          dns: {
            hosts: updatedHosts
          }
        }
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
    const endpoint = "/api/config/customdns";
    const fullUrl = `${this.config.pihole.url}${endpoint}`;

    const httpsAgent = new https.Agent({
      rejectUnauthorized: false,
    });

    const response = await fetch(fullUrl, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'X-FTL-SID': this.session.sid
      },
      body: JSON.stringify({
        config: {
          customdns: {
            [domain]: ip
          }
        }
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
    const endpoint = "/admin/api.php";
    const fullUrl = `${this.config.pihole.url}${endpoint}`;

    const params = new URLSearchParams({
      customdns: 'true',
      action: 'add',
      domain: domain,
      ip: ip,
      auth: this.config.pihole.password
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
    const endpoint = "/api/config/dns";
    const fullUrl = `${this.config.pihole.url}${endpoint}`;

    const httpsAgent = new https.Agent({
      rejectUnauthorized: false,
    });

    const response = await fetch(fullUrl, {
      method: 'GET',
      headers: {
        'X-FTL-SID': this.session.sid
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
   * Generate a summary of what was registered
   */
  generateRegistrationSummary() {
    console.log('\n📋 DNS Registration Summary:');
    console.log('============================');
    
    for (const [containerName, actualIp] of this.networkMap) {
      const domain = `${containerName}.app-network`;
      console.log(`   ${domain} → ${actualIp}`);
    }

    console.log('\n🔍 Test DNS resolution with:');
    console.log('   nslookup gateway.app-network 127.0.0.1');
    console.log('   nslookup pihole.app-network 127.0.0.1');
    console.log('   nslookup traefik.app-network 127.0.0.1');
    console.log('   nslookup auth.app-network 127.0.0.1');

    console.log('\n💡 Each container resolves to its actual IP in the app-network');
  }
}

// Main execution
async function main() {
  const env = await loadEnv('.env');
  
  const config = {
    pihole: {
      url: env.PIHOLE_URL || 'https://localhost:8080',
      password: env.PIHOLE_PASSWORD,
    }
  };

  // Validate required environment variables
  if (!config.pihole.password) {
    console.error('❌ Missing PIHOLE_PASSWORD in .env file');
    process.exit(1);
  }

  const registrar = new PiHoleNetworkRegistrar(config);
  await registrar.run();
  registrar.generateRegistrationSummary();
}

main().catch((error) => {
  console.error('💥 Fatal error:', error);
  process.exit(1);
});