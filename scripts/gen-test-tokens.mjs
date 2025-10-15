#!/usr/bin/env node

import crypto from 'crypto';
import jwt from 'jsonwebtoken';
import fs from 'fs/promises';
import path from 'path';
import { v4 as uuidv4 } from 'uuid';


const outputDir = path.join(process.cwd(), 'scripts/test-tokens');

const debug = false;

// Generate RSA key pair
function generateKeyPair() {
  return new Promise((resolve, reject) => {
    crypto.generateKeyPair('rsa', {
      modulusLength: 2048,
      publicKeyEncoding: {
        type: 'spki',
        format: 'pem'
      },
      privateKeyEncoding: {
        type: 'pkcs8',
        format: 'pem'
      }
    }, (err, publicKey, privateKey) => {
      if (err) reject(err);
      else resolve({ publicKey, privateKey });
    });
  });
}

// Create test tokens with different scenarios
async function createTestTokens(privateKey, passportData) {
  const now = Math.floor(Date.now() / 1000);
  const oneHour = 3600;

  const tokens = {
    eternalUser: jwt.sign(
      {
        userId: 'test-user-eternal',
        userName: 'Test eternal',
        sub: 'test-user-eternal',
        iss: passportData.iss,
        aud: passportData.aud,
        exp: now + oneHour * 24 * 365 * 10, // 10 years
        iat: now,
        nbf: now,
        jti: uuidv4(),      // Unique token ID
      },
      privateKey,
      { algorithm: passportData.algorithms[0], keyid: passportData.keys[0].kid }
    ),
    validUser: jwt.sign(
      {
        userId: 'test-user-123',
        userName: 'Test User',
        sub: 'test-user-123',
        iss: passportData.iss,
        aud: passportData.aud,
        exp: now + oneHour,
        iat: now,
        nbf: now,
        jti: uuidv4(),      // Unique token ID
      },
      privateKey,
      { algorithm: passportData.algorithms[0], keyid: passportData.keys[0].kid }
    ),

    expiredUser: jwt.sign(
      {
        userId: 'expired-user-456',
        userName: 'Expired User',
        sub: 'expired-user-456',
        iss: passportData.iss,
        aud: passportData.aud,
        exp: now - oneHour,
        iat: now - (oneHour * 2),
        nbf: now - (oneHour * 2),
        jti: uuidv4(),      // Unique token ID
      },
      privateKey,
      { algorithm: passportData.algorithms[0], keyid: passportData.keys[0].kid }
    ),

    adminUser: jwt.sign(
      {
        userId: 'admin-user-789',
        userName: 'Admin User',
        sub: 'admin-user-789',
        iss: passportData.iss,
        aud: passportData.aud,
        exp: now + oneHour,
        iat: now,
        nbf: now,
        jti: uuidv4(),      // Unique token ID
        role: 'admin'
      },
      privateKey,
      { algorithm: passportData.algorithms[0], keyid: passportData.keys[0].kid }
    ),

    minimalUser: jwt.sign(
      {
        sub: 'minimal-user-000',
        iss: passportData.iss,
        aud: passportData.aud,
        exp: now + oneHour,
        iat: now,
        jti: uuidv4(),      // Unique token ID
      },
      privateKey,
      { algorithm: passportData.algorithms[0], keyid: passportData.keys[0].kid }
    ),

    futureUser: jwt.sign(
      {
        userId: 'future-user-111',
        userName: 'Future User',
        sub: 'future-user-111',
        iss: passportData.iss,
        aud: passportData.aud,
        exp: now + oneHour,
        iat: now,
        nbf: now + 300,
        jti: uuidv4(),      // Unique token ID
      },
      privateKey,
      { algorithm: passportData.algorithms[0], keyid: passportData.keys[0].kid }
    )
  };

  return tokens;
}

// Generate JWKS file
function generateJWKS(publicKey) {
  const key = crypto.createPublicKey(publicKey);
  const jwk = key.export({ format: 'jwk' });

  return {
    keys: [
      {
        kty: jwk.kty,
        use: 'sig',
        kid: 'test-key-123',
        alg: 'RS256',
        n: jwk.n,
        e: jwk.e,
        //   publicKey: publicKey // Include PEM format for convenience
      }
    ]
  };
}

// Simple validation using jwt.verify (no jose dependency)
export async function testValidation({ testTokens, testKeys }) {
  if (debug) console.log('🧪 Testing token validation with jsonwebtoken...\n');

  for (const [name, token] of Object.entries(testTokens)) {
    try {
      const payload = jwt.verify(token, testKeys.publicKey, { algorithms: ['RS256'] });
      if (debug) console.log(`✅ ${name}: VALID - User: ${payload.userId || payload.sub}`);
      if (debug) console.log(`   Expires: ${new Date(payload.exp * 1000).toISOString()}`);
    } catch (error) {
      if (error.name === 'TokenExpiredError') {
        if (debug) console.log(`⏰ ${name}: EXPIRED - ${error.message}`);
      } else if (error.name === 'JsonWebTokenError') {
        if (debug) console.log(`🚫 ${name}: JWT ERROR - ${error.message}`);
      } else {
        if (debug) console.log(`❌ ${name}: ERROR - ${error.message}`);
      }
    }
  }
}


async function generateTestPKI() {
  // Create output directory
  await fs.mkdir(outputDir, { recursive: true });

  const keysFilePath = path.join(outputDir, 'test-keys.json');

  let testKeys;
  let testTokens;
  let passportData;

  // If keys exist, load other files as well
  const tokensFilePath = path.join(outputDir, 'test-tokens.json');
  const passportFilePath = path.join(outputDir, 'passport.json');
  const jwksFilePath = path.join(outputDir, 'jwks.json');


  // Check if test-keys.json exists
  try {
    const existingKeysContent = await fs.readFile(keysFilePath, 'utf-8');
    testKeys = JSON.parse(existingKeysContent);
    if (debug) console.log('🔑 Loaded existing keys from test-keys.json');

    // DO not load
    //testTokens = JSON.parse(await fs.readFile(tokensFilePath, 'utf-8'));
    //passportData = JSON.parse(await fs.readFile(passportFilePath, 'utf-8'));

    //console.log('🎫 Loaded existing test tokens and passport data.');
  } catch (error) {
    // Some other error occurred while reading the file
    if (debug) console.error('❌ Error reading existing keys or related files:', error);
    // File does not exist, generate new keys and data
    if (debug) console.log('🔑 Generating new RSA key pair...');
    const { publicKey, privateKey } = await generateKeyPair();
    testKeys = { publicKey, privateKey };
    await fs.writeFile(
      keysFilePath,
      JSON.stringify(testKeys, null, 2)
    );


  }

  if (debug) console.log('📁 Generating JWKS...');
  const jwks = generateJWKS(testKeys.publicKey);

  // Save files
  await fs.writeFile(
    jwksFilePath,
    JSON.stringify(jwks, null, 2)
  );

  // Create passport data file
  passportData = {
    keys: jwks.keys,
    roles: ['user', 'admin'],
    iss: "https://com-socket.dev",
    aud: ['http://localhost:3001'],
    algorithms: ['RS256'],
    ignoreNotBefore: false,
    ignoreExpiration: false,
  };

  await fs.writeFile(
    passportFilePath,
    JSON.stringify(passportData, null, 2)
  );

  if (debug) console.log('✅ New test tokens generated and saved!');



  if (debug) console.log('🎫 Creating test tokens...');
  testTokens = await createTestTokens(testKeys.privateKey, passportData);

  await fs.writeFile(
    tokensFilePath,
    JSON.stringify(testTokens, null, 2)

  );

  if (debug) console.log('📂 Files located in:', outputDir);

  const ret = {
    jwks,
    testTokens,
    passportData,
    testKeys
  };

  // Run validation (only if generating new tokens)
  if (!testTokens.validUser) { // A simple check to see if tokens were loaded vs generated
    // This might not be robust if files are partially present
    // A better check might be if the keys were newly generated
    // But the generation block already runs validation
    await testValidation(ret);
  } else {
    // If loaded, you might still want to validate, or skip based on a flag
    // For now, let's validate loaded tokens too, as it's useful
    if (debug) console.log('\n🧪 Validating loaded tokens...');
    await testValidation(ret);
  }

  return ret;
}

// Only run main if this file is executed directly
if (import.meta.url === `file://${process.argv[1]}`) {
  generateTestPKI().then(result => {
    if (debug) console.log('\n📋 Generated tokens:');
    Object.keys(result.testTokens).forEach(key => {
      if (debug) console.log(`   - ${key}: ${result.testTokens[key].substring(0, 50)}...`);
    });
  });
}


// Export the generated tokens
export const testTokens = await generateTestPKI().then(result => result.testTokens);
export const jwks = await generateTestPKI().then(result => result.jwks);
export const passportData = await generateTestPKI().then(result => result.passportData);
export const testKeys = await generateTestPKI().then(result => result.testKeys);

export default generateTestPKI;
