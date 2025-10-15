// socket.io/jwt-clerk.mjs

import jwksClient from 'jwks-rsa';
import { createVerify, createPublicKey } from 'crypto'; // Import for signature verification
import { Mutex } from 'async-mutex';

// Mutex to protect clientCache access
const cacheMutex = new Mutex();

// --- Internal Constants and Helpers ---
const debug = false; process.env.NODE_ENV !== 'production';
const clientCache = new Map();


import { algSchema, jwksKeySchema, passportSchema } from './schemas.mjs';

// Add this function to clear the cache
export function clearJwksClientCache() {
  clientCache.clear(); // Clears all entries
  // Or clientCache = new Map(); // Re-initializes the map (might require module re-evaluation)
}

// --- Internal Functions for JWKS ---
export async function getClient(iss) {
  const release = await cacheMutex.acquire();
  try {
    if (clientCache.has(iss)) {
      if (debug) console.log(`Cache hit for issuer: ${iss}`);
      return clientCache.get(iss);
    }

    if (debug) console.log(`Cache miss for issuer: ${iss}`);
    const client = jwksClient({
      jwksUri: `${iss}/.well-known/jwks.json`,
    });

    clientCache.set(iss, client);
    return client;
  } finally {
    release();
  }
}

function getKey(header, client) {
  return new Promise((resolve, reject) => {
    if (!header.kid) {
      return reject(new Error('Token header is missing "kid"'));
    }
    client.getSigningKey(header.kid, (err, key) => {
      if (err) {
        if (debug) console.error(`Error fetching key for kid '${header.kid}' from JWKS:`, err.message);
        return reject(err);
      }
      // jwks-rsa typically provides the key object with methods/properties
      // Prioritize getPublicKey() method, fallback to rsaPublicKey property.
      const signingKey = key?.getPublicKey ? key.getPublicKey() : key?.rsaPublicKey || key;
      if (!signingKey) {
        return reject(new Error('Failed to extract public key from jwks-rsa response for kid: ' + header.kid));
      }
      resolve(signingKey);
    });
  });
}

// --- Core Cryptographic Signature Verification ---
/**
 * Verifies the cryptographic signature of a JWT.
 *
 * @param {string} token The complete JWT string.
 * @param {string} publicKey The public key string (PEM format) for verification.
 * @param {string} algorithm The algorithm specified in the token header (e.g., 'RS256').
 * @returns {{ header: Object, payload: Object }} The decoded header and payload if verification is successful.
 * @throws {Error} If verification fails (malformed token, invalid signature, unsupported algorithm, invalid key).
 */
export function cryptVerify(token, publicKey, algorithm) {
  try {
    // 1. Basic Token Structure Validation
    const parts = token.split('.');
    if (parts.length !== 3) {
      throw new Error('Malformed token: Incorrect number of parts');
    }
    const [headerB64, payloadB64, signatureB64] = parts;

    // 2. Decode Header and Payload
    let header, payload;
    try {
      header = JSON.parse(Buffer.from(headerB64, 'base64url').toString('utf8'));
      payload = JSON.parse(Buffer.from(payloadB64, 'base64url').toString('utf8'));
    } catch (decodeError) {
      throw new Error(`Failed to decode token parts: ${decodeError.message}`);
    }

    // 3. Algorithm Validation (Basic)
    const supportedCryptoAlgorithms = {
      'RS256': 'RSA-SHA256',
      'RS384': 'RSA-SHA384',
      'RS512': 'RSA-SHA512',
      // Add others if needed, map to Node.js crypto names
      // 'ES256': 'SHA256', // ECDSA needs different handling
    };
    const cryptoAlgorithm = supportedCryptoAlgorithms[algorithm];
    if (!cryptoAlgorithm) {
      throw new Error(`Unsupported algorithm for cryptVerify: ${algorithm}`);
    }

    // 4. Public Key Validation
    if (!publicKey || typeof publicKey !== 'string' || !publicKey.trim()) {
      throw new Error('Invalid public key provided for signature verification');
    }

    // 5. Signature Verification using Node.js Crypto
    const unsignedToken = `${headerB64}.${payloadB64}`;
    // Decode the signature from base64url
    const signatureBuffer = Buffer.from(signatureB64, 'base64url');

    const verifier = createVerify(cryptoAlgorithm);
    verifier.update(unsignedToken, 'utf8'); // Specify encoding
    verifier.end(); // Finalize data input

    const isValid = verifier.verify(publicKey, signatureBuffer); // crypto handles base64 internally if needed

    if (!isValid) {
      throw new Error('Invalid token signature');
    }

    // 6. Return Decoded Parts on Success
    if (debug) console.log(`🔒 Cryptographic signature verified successfully for alg ${algorithm}.`);
    return { header, payload };

  } catch (error) {
    // Differentiate between our specific errors and unexpected ones
    if (error.message.startsWith('Malformed token') ||
      error.message.startsWith('Failed to decode') ||
      error.message.startsWith('Unsupported algorithm') ||
      error.message.startsWith('Invalid public key') ||
      error.message === 'Invalid token signature') {
      // Re-throw specific errors as-is for upstream handling
      throw error;
    }
    // For any other unexpected errors during the crypto process, wrap them
    if (debug) console.error("Unexpected error in cryptVerify:", error.message);
    throw new Error('Malformed token'); // Default to generic error for malformed cases
  }
}

/**
 * Converts a JSON Web Key (JWK) with `.n` and `.e` into a PEM-formatted public key.
 *
 * @param {string} n - The Base64 URL-safe encoded modulus of the RSA public key.
 * @param {string} e - The Base64 URL-safe encoded public exponent.
 * @param {string} kty - The key type (e.g., 'RSA').
 * @returns {string} - The PEM-formatted public key.
 */
function jwkToPem(n, e, kty = 'RSA') {
  try {
    // Input validation
    if (!n || !e || typeof n !== 'string' || typeof e !== 'string') {
      throw new Error('Invalid input: "n" and "e" must be non-empty strings.');
    }
    if (kty !== 'RSA') {
      throw new Error(`Unsupported key type: "${kty}". Only "RSA" is currently supported.`);
    }

    // Create the public key using Node.js crypto module
    const publicKey = createPublicKey({
      key: {
        kty,
        n, // Pass the raw Base64 URL-safe string
        e, // Pass the raw Base64 URL-safe string
      },
      format: 'jwk', // Specify JWK format for input
    });

    // Export the public key in PEM format
    return publicKey.export({ type: 'spki', format: 'pem' });
  } catch (error) {
    if (debug) console.error('Failed to convert JWK to PEM:', error.message);
    throw new Error(`JWK to PEM conversion failed: ${error.message}`);
  }
}


function jwtDecode(token) {
  try {
    // Split the token into its three parts: header, payload, and signature
    const [encodedHeader, encodedPayload, signature] = token.split('.');

    if (!encodedHeader || !encodedPayload || !signature) {
      throw new Error('Token structure invalid: missing components');
    }

    // Decode the header and payload from base64url
    const decodeBase64Url = (str) => {
      try {
        return JSON.parse(Buffer.from(str, 'base64url').toString());
      } catch (err) {
        throw new Error(`Failed to decode JWT component: ${err.message}`);
      }
    };

    const header = decodeBase64Url(encodedHeader);
    const payload = decodeBase64Url(encodedPayload);

    // Validate the structure of the decoded components
    if (!header || typeof header !== 'object' || !payload || typeof payload !== 'object') {
      throw new Error('Token structure invalid: header or payload is not a valid object');
    }

    // Return the decoded components without validating the signature
    return { header, payload, signature };
  } catch (error) {
    throw new Error(`JWT decoding failed: ${error.message}`);
  }
}

// --- Main Token Verification Function ---
/**
 * Verifies a JWT token against a passport configuration.
 *
 * @param {string} token - The JWT string to verify.
 * @param {Object} passport - The passport object containing validation rules.
 * @returns {Promise<boolean|Object>} - Returns false if verification fails,
 *                                      or an object { header, payload } if successful.
 */

export async function verifyToken(token, passport) {
  if (!token) {
    if (debug) console.warn('No token provided for verification.');
    return false;
  }

  try {
    // --- Step 0: Validate the passport object ---
    const { error: passportValidationError } = passportSchema.required().validate(passport, { abortEarly: false });
    if (passportValidationError) {
      if (debug) console.error(
        'Passport validation failed:',
        passportValidationError.details.map((e) => e.message).join(', ')
      );
      return false;
    }

    // --- Step 1: Decode the token (without signature verification) ---
    let _decoded;
    try {
      _decoded = jwtDecode(token);
    } catch (decodeError) {
      if (debug) console.warn('Failed to decode JWT:', decodeError?.message);
      return false;
    }

    // pre decoded token structure
    const decoded = { ..._decoded, valid: false };

    const { kid, alg } = decoded.header;
    const { iss, aud, exp, nbf } = decoded.payload;

    // --- Step 2: Validate core token claims ---
    if (!iss) {
      if (debug) console.error('Issuer (iss) claim is missing in the token.');
      return false;
    }
    if (iss !== passport.iss) {
      if (debug) console.error(`Issuer mismatch. Expected: '${passport.iss}', Got: '${iss}'`);
      return false;
    }

    if (!alg) {
      if (debug) console.error('Algorithm (alg) header is missing in the token.');
      return false;
    }

    // --- Step 3: Resolve Public Key ---
    let publicKey;

    if (passport.keys) {
      // Use provided keys if available
      const key = passport.keys.find(k => k.kid === kid);
      if (!key) {
        if (debug) console.error(`No matching key found in passport for kid: ${kid}`);
        return false;
      }
      publicKey = jwkToPem(key.n, key.e, key.kty);

    } else {
      // Fetch public key from JWKS if passport.keys is not provided
      try {
        const client = getClient(iss);
        publicKey = await getKey(decoded.header, client);
        if (!publicKey) {
          throw new Error('Failed to retrieve public key from JWKS');
        }
        if (debug) console.log(`Fetched public key from JWKS for kid: ${kid}`);
      } catch (jwksError) {
        if (debug) console.error('Failed to retrieve public key from JWKS:', jwksError.message);
        return false;
      }
    }

    // --- Step 4: Verify Token Signature ---
    try {
      const { header, payload } = cryptVerify(token, publicKey, alg);
      decoded.header = header;
      decoded.payload = payload;
      decoded.valid = true; // Mark as valid
      if (debug) console.log(`✅ Token for user '${payload.sub || payload.userId}' successfully verified.`);
    } catch (verifyError) {
      if (debug) console.error('🔐 Token signature verification failed:', verifyError.message);
      return false;
    }

    // --- Step 5: Validate Algorithm ---
    const supportedAlgorithms = ['RS256', 'RS384', 'RS512', 'ES256', 'ES384', 'ES512'];
    if (!supportedAlgorithms.includes(alg)) {
      if (debug) console.error(`Unsupported algorithm: ${alg}`);
      return false;
    }

    const passportAlgorithms = passport.algorithms || ['RS256'];
    if (!passportAlgorithms.includes(alg)) {
      if (debug) console.error(
        `Algorithm mismatch: Token alg '${alg}' not in passport algs [${passportAlgorithms.join(', ')}]`
      );
      return false;
    }

    // --- Step 6: Validate Time-Based Claims ---
    const currentTime = Math.floor(Date.now() / 1000);

    // Check expiration (exp)
    if (exp !== undefined) {
      const ignoreExpiration = passport.ignoreExpiration ?? true;
      if (!ignoreExpiration && exp < currentTime) {
        if (debug) console.log(`Token expired at ${new Date(exp * 1000).toISOString()}, current time is ${new Date(currentTime * 1000).toISOString()}`);
        return false;
      }
    }

    // Check not-before (nbf)
    if (nbf !== undefined) {
      const ignoreNotBefore = passport.ignoreNotBefore ?? true;
      if (!ignoreNotBefore && nbf > currentTime) {
        if (debug) console.log(`Token not valid before ${new Date(nbf * 1000).toISOString()}, current time is ${new Date(currentTime * 1000).toISOString()}`);
        return false;
      }
    }

    // --- Step 7: Validate Audience ---
    const expectedAudiences = Array.isArray(passport.aud) ? passport.aud : [passport.aud];
    const tokenAudiences = Array.isArray(aud) ? aud : [aud];

    if (expectedAudiences.length > 0) {
      const audienceMatch = expectedAudiences.some(expected => tokenAudiences.includes(expected));
      if (!audienceMatch) {
        if (debug) console.error(`Audience mismatch. Expected one of [${expectedAudiences.join(', ')}], Token has [${tokenAudiences.join(', ')}]`);
        return false;
      }
    }

    // --- Success ---
    if (debug) console.log(`✅ Token for user '${decoded.payload.sub || decoded.payload.userId}' successfully verified.`);
    return { header: decoded.header, payload: decoded.payload };

  } catch (error) {
    if (debug) console.error('❌ Unexpected error during token verification:', error.message);
    return false;
  }
}