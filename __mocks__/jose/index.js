// __mocks__/jose/index.mjs
// Create the mock functions
const jwtVerify = jest.fn(() => Promise.resolve({
    payload: { sub: 'test-user-id', iss: 'test-issuer' },
    protectedHeader: { alg: 'RS256' }
}));

const createRemoteJWKSet = jest.fn(() => {
    return jest.fn(() => Promise.resolve({
        alg: 'RS256',
        kty: 'RSA'
    }));
});

const JWTVerify = jest.fn();
const JWK = {
    asKey: jest.fn()
};
const JWS = {
    verify: jest.fn()
};
const importJWK = jest.fn();
const exportJWK = jest.fn();
const SignJWT = jest.fn(() => ({
    setProtectedHeader: jest.fn().mockReturnThis(),
    setIssuer: jest.fn().mockReturnThis(),
    setAudience: jest.fn().mockReturnThis(),
    setExpirationTime: jest.fn().mockReturnThis(),
    setSubject: jest.fn().mockReturnThis(),
    setIssuedAt: jest.fn().mockReturnThis(),
    sign: jest.fn(() => Promise.resolve('mock-jwt-token'))
}));

// ESM exports - remove all module.exports references
export {
    jwtVerify,
    createRemoteJWKSet,
    JWTVerify,
    JWK,
    JWS,
    importJWK,
    exportJWK,
    SignJWT
};
/* eslint-disable import/no-anonymous-default-export */
export default {
    jwtVerify,
    createRemoteJWKSet,
    JWTVerify,
    JWK,
    JWS,
    importJWK,
    exportJWK,
    SignJWT,
    createLocalJWKSet: jest.fn(),
    decodeJwt: jest.fn(),
    compactVerify: jest.fn(),
    flattenedVerify: jest.fn(),
    generalVerify: jest.fn(),
    generateKeyPair: jest.fn(),
    exportPKCS8: jest.fn(),
    exportSPKI: jest.fn(),
    compactDecrypt: jest.fn(),
    flattenedDecrypt: jest.fn(),
    generalDecrypt: jest.fn(),
};