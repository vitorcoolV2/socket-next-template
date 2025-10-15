

const MOCK_JWKS = global.MOCK_JWKS;


const mockJwksRsa = jest.fn((options) => {
    return {
        getSigningKey: jest.fn((kid, callback) => {
            process.nextTick(() => {
                const key = MOCK_JWKS.keys.find(k => k.kid === kid);
                if (key) {
                    callback(null, key);
                } else {
                    const error = new Error(`Unable to find a signing key that matches '${kid}'`);
                    error.name = 'SigningKeyNotFoundError';
                    callback(error, null);
                }
            });
        }),
        getKeys: jest.fn((callback) => {
            process.nextTick(() => {
                callback(null, MOCK_JWKS.keys);
            });
        }),
        _mockOptions: options
    };
});

// Export the mock function as the DEFAULT export
export default mockJwksRsa;