
import generateTestPKI from '../../../../scripts/gen-test-tokens.mjs';

// Generate test data first
const { testTokens, passportData, testKeys } = await generateTestPKI();


jest.unstable_mockModule('jwks-rsa', () => ({
  default: jest.fn(() => ({
    getSigningKey: jest.fn((kid, callback) => {
      process.nextTick(() => callback(null, { getPublicKey: () => testKeys.publicKey }));
    }),
    getSigningKeyxxx: jest.fn((kid, callback) => {
      if (!passportData.keys || passportData.keys.length === 0) {
        throw new Error('No keys available in passportData');
      }

      const key = passportData.keys.find(k => k.kid === kid);
      if (key) {
        process.nextTick(() => callback(null, { getPublicKey: () => testKeys.publicKey }));
      } else {
        process.nextTick(() => callback(new Error('Key not found')));
      }
    }),
  })),
}));

// Import the mocked jwksClient
const { default: jwksClient } = await import('jwks-rsa');

// Import the module after mocking
const { verifyTokenLegacy, cryptVerify, clearJwksClientCache, getClient } = await import('a-socket/jwt-passport');

describe('JWT Clerk Complete Test Suite', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('verifyTokenLegacy - Positive Cases', () => {
    test('should verify valid user token', async () => {
      const result = await verifyTokenLegacy(testTokens.validUser, passportData);

      expect(result).toBeDefined();
      expect(result.payload.userId).toBe('test-user-123');
      expect(result.payload.userName).toBe('Test User');
      expect(result.payload.sub).toBe('test-user-123');
      expect(result.header.alg).toBe('RS256');
      expect(result.header.kid).toBe('test-key-123');
    });

    test('should verify admin user token', async () => {
      const result = await verifyTokenLegacy(testTokens.adminUser, passportData);

      expect(result).toBeDefined();
      expect(result.payload.userId).toBe('admin-user-789');
      expect(result.payload.userName).toBe('Admin User');
      expect(result.payload.role).toBe('admin');
    });

    test('should verify minimal user token', async () => {
      const result = await verifyTokenLegacy(testTokens.minimalUser, passportData);

      expect(result).toBeDefined();
      expect(result.payload.sub).toBe('minimal-user-000');
      expect(result.payload.iss).toBe('https://com-socket.dev');
    });
  });

  describe('verifyTokenLegacy - Negative Cases', () => {
    test('should reject expired token', async () => {
      const result = await verifyTokenLegacy(testTokens.expiredUser, passportData);
      expect(result).toBe(false);
    });

    test('should reject future token (not yet valid)', async () => {
      const result = await verifyTokenLegacy(testTokens.futureUser, passportData);
      expect(result).toBe(false);
    });

    test('should reject invalid token string', async () => {
      const result = await verifyTokenLegacy('invalid.token.string', passportData);
      expect(result).toBe(false);
    });

    test('should reject empty token', async () => {
      const result = await verifyTokenLegacy('', passportData);
      expect(result).toBe(false);
    });

    test('should reject null token', async () => {
      const result = await verifyTokenLegacy(null, passportData);
      expect(result).toBe(false);
    });

    test('should reject undefined token', async () => {
      const result = await verifyTokenLegacy(undefined, passportData);
      expect(result).toBe(false);
    });
  });

  describe('verifyTokenLegacy - Edge Cases', () => {
    test('should handle malformed JWT (missing parts)', async () => {
      const result = await verifyTokenLegacy('header.payload', passportData);
      expect(result).toBe(false);
    });

    test('should handle invalid base64 in token', async () => {
      const result = await verifyTokenLegacy('invalid!base64!here', passportData);
      expect(result).toBe(false);
    });

  });

  describe('cryptVerify Function', () => {
    test('should verify valid token signature', () => {
      const result = cryptVerify(testTokens.validUser, testKeys.publicKey, 'RS256');

      expect(result).toBeDefined();
      expect(result.header.alg).toBe('RS256');
      expect(result.header.kid).toBe('test-key-123');
      expect(result.payload.userId).toBe('test-user-123');
    });

    test('should throw error for invalid signature', async () => {
      // Generate a different key pair to create invalid signature
      const crypto = await import('crypto');
      const { privateKey: wrongKey/*, publicKey: wrongPubKey*/ } = crypto.generateKeyPairSync('rsa', {
        modulusLength: 2048,
        publicKeyEncoding: { type: 'spki', format: 'pem' },
        privateKeyEncoding: { type: 'pkcs8', format: 'pem' }
      });

      const jwt = (await import('jsonwebtoken')).default;
      const wrongToken = jwt.sign(
        { test: 'data' },
        wrongKey,
        { algorithm: 'RS256', keyid: 'test-key-123' }
      );

      expect(() => {
        cryptVerify(wrongToken, testKeys.publicKey, 'RS256');
      }).toThrow('Invalid token signature');
    });

    test('should throw error for malformed token', () => {
      expect(() => {
        cryptVerify('not.a.valid.token', testKeys.publicKey, 'RS256');
      }).toThrow('Malformed token'); // Changed to match the expected error
    });

    expect(() => {
      cryptVerify(testTokens.validUser, testKeys.publicKey, 'HS256');
      // Change the expected message to match the actual one:
    }).toThrow('Unsupported algorithm for cryptVerify: HS256');

    test('should throw error for invalid public key', () => {
      expect(() => {
        cryptVerify(testTokens.validUser, '', 'RS256');
      }).toThrow('Invalid public key');
    });
  });

  describe('Passport Data Validation', () => {
    test('should reject passport missing required fields', async () => {
      const invalidPassport = { roles: ['user'] };
      const result = await verifyTokenLegacy(testTokens.validUser, invalidPassport);
      expect(result).toBe(false);
    });

    test('should reject passport with invalid issuer format', async () => {
      const invalidPassport = {
        ...passportData,
        iss: 'not-a-valid-uri'
      };
      const result = await verifyTokenLegacy(testTokens.validUser, invalidPassport);
      expect(result).toBe(false);
    });

    test('should reject passport with empty audience', async () => {
      const invalidPassport = {
        ...passportData,
        aud: [] // Empty audience
      };
      const result = await verifyTokenLegacy(testTokens.validUser, invalidPassport);
      expect(result).toBe(false);
    });
  });

  describe('JWKS Integration', () => {
    test('should handle JWKS key not found', async () => {
      // Create token with unknown kid
      const jwt = (await import('jsonwebtoken')).default;
      const unknownKidToken = jwt.sign(
        { test: 'data' },
        testKeys.privateKey,
        { algorithm: 'RS256', keyid: 'unknown-key' }
      );
      const pass2 = {
        "keys": [
          {
            "kty": "RSA",
            "use": "sig",
            "kid": "test-key-123",
            "alg": "RS256",
            "n": "xhrv0jLzHig9HI0XRNnFg87on3PWmldWa47y_JLU_ngLs76IsHB0mRXYfmam3-5xVyD4eCyClgOX7r870xFngbmcMJkMDENlmAm1jfN8Pcx3MzPbQ2T0NXxnkku53PacHBxfk2mH4FPe6gf_oRchCwU3tj3OhLzwEAkxIkq_pqfknt2SPTz15zH-gHvPYRTw_f8urBKiKA6zNDvQVFEQA-N1prMzf8YFI1c0BtlqIX7nx8HvbRTV5aocrlXeuIhvVOBdeiOmMbgWBBNd-LMVnNPcWanWQ4sYeO-DFM76w22fyJB5f6u4Qp2hSLfOoVpls_9qTpI24I4vKC6oiFyQdw",
            "e": "AQAB"
          }
        ],
        "roles": [
          "user",
          "admin"
        ],
        "aud": [
          "http://localhost:3001"
        ],
        "algorithms": [
          "RS256"
        ],
        "ignoreNotBefore": false,
        "ignoreExpiration": false,

      }
      const result = await verifyTokenLegacy(unknownKidToken, pass2);
      expect(result).toBe(false);
    });
    test('should cache JWKS client for same issuer', async () => {
      const iss = 'https://enabling-glider-13.clerk.accounts.dev';

      // First call to getClient
      await getClient(iss);

      // Second call to getClient with the same issuer
      await getClient(iss);

      // Assert that jwksClient was called only once
      expect(jwksClient).toHaveBeenCalledTimes(1);
    });
    test('should not use cache JWKS when passport keys and defined. Will not fetch issuer keys', async () => {
      clearJwksClientCache();
      // First call - this should create the JWKS client
      await verifyTokenLegacy(testTokens.validUser, passportData);
      expect(jwksClient).toHaveBeenCalledTimes(0);

      // Second call - this should reuse the cached client
      const { keys, ...passportData2 } = passportData;
      expect(keys).toBeDefined();
      await verifyTokenLegacy(testTokens.adminUser, passportData2);

      // JWKS client should be created only once
      // Assert that jwksClient was called only once
      expect(jwksClient).toHaveBeenCalledTimes(1);
    });
  });

  describe('Performance and Reliability', () => {
    test('should handle concurrent token verifications', async () => {
      const promises = [
        verifyTokenLegacy(testTokens.validUser, passportData),
        verifyTokenLegacy(testTokens.adminUser, passportData),
        verifyTokenLegacy(testTokens.minimalUser, passportData)
      ];

      const results = await Promise.all(promises);

      expect(results[0].payload.userId).toBe('test-user-123');
      expect(results[1].payload.userId).toBe('admin-user-789');
      expect(results[2].payload.sub).toBe('minimal-user-000');
    });

    test('should handle rapid successive calls', async () => {
      for (let i = 0; i < 5; i++) {
        const result = await verifyTokenLegacy(testTokens.validUser, passportData);
        expect(result.payload.userId).toBe('test-user-123');
      }
    });
  });
});

// Export test data for use in other tests
export { testTokens, passportData, testKeys };
