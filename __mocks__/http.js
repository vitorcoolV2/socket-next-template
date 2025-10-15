// ESM format HTTP mock
export const createServer = jest.fn(() => {
    const mockServer = {
        listen: jest.fn((port, host, callback) => {
            if (typeof host === 'function') {
                callback = host;
            }
            if (callback) {
                process.nextTick(callback);
            }
            return mockServer;
        }),
        close: jest.fn((callback) => {
            if (callback) {
                process.nextTick(callback);
            }
        }),
        on: jest.fn(),
        address: jest.fn(() => ({ port: 3001, family: 'IPv4', address: '0.0.0.0' })),
    };
    return mockServer;
});

export default { createServer };