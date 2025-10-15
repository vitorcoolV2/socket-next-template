import { createPublicKey } from 'crypto';

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
    console.error('Failed to convert JWK to PEM:', error.message);
    throw new Error(`JWK to PEM conversion failed: ${error.message}`);
  }
}

// Example usage
const jwk = {
  alg: 'RS256',
  e: 'AQAB',
  kid: 'test-key-123',
  kty: 'RSA',
  n: 'xhrv0jLzHig9HI0XRNnFg87on3PWmldWa47y_JLU_ngLs76IsHB0mRXYfmam3-5xVyD4eCyClgOX7r870xFngbmcMJkMDENlmAm1jfN8Pcx3MzPbQ2T0NXxnkku53PacHBxfk2mH4FPe6gf_oRchCwU3tj3OhLzwEAkxIkq_pqfknt2SPTz15zH-gHvPYRTw_f8urBKiKA6zNDvQVFEQA-N1prMzf8YFI1c0BtlqIX7nx8HvbRTV5aocrlXeuIhvVOBdeiOmMbgWBBNd-LMVnNPcWanWQ4sYeO-DFM76w22fyJB5f6u4Qp2hSLfOoVpls_9qTpI24I4vKC6oiFyQdw',
};

try {
  const pemPublicKey = jwkToPem(jwk.n, jwk.e, jwk.kty);
  console.log(pemPublicKey);
} catch (error) {
  console.error('Error during JWK to PEM conversion:', error.message);
}