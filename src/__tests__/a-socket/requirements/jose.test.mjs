// src/__tests__/jose.test.mjs


describe('Jose Test', () => {
  let jose;

  beforeAll(async () => {
    jose = await import('jose');
  });

  test('should have createRemoteJWKSet export', () => {
    expect(jose.createRemoteJWKSet).toBeDefined();
    expect(typeof jose.createRemoteJWKSet).toBe('function');
  });

  test('should work with createRemoteJWKSet', () => {
    const jwks = jose.createRemoteJWKSet('https://example.com/jwks');
    expect(jose.createRemoteJWKSet).toHaveBeenCalledWith('https://example.com/jwks');
    expect(typeof jwks).toBe('function');
  });

  test('should work with jwtVerify', async () => {
    const result = await jose.jwtVerify('token', 'key');
    expect(jose.jwtVerify).toHaveBeenCalledWith('token', 'key');
    expect(result.payload.sub).toBe('test-user-id');
  });
});