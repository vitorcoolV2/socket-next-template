// __mocks__/socket.io.mjs

// Import jest if needed for .fn(), though it's often available globally in Jest
// import { jest } from '@jest/globals'; // Usually not necessary for jest.fn()

// Mock socket instance - enhanced to simulate event handling
// This function creates a mock socket object that mimics a real Socket.IO socket
const createMockSocket = (id = 'mock-socket-id') => {
    const mockSocket = {
        id,
        emit: jest.fn(),
        // Use a Map to store event handlers like a real EventEmitter
        _handlers: new Map(),
        on: jest.fn(function (event, handler) {
            // Use function keyword for 'this' binding if needed later
            this._handlers.set(event, handler);
            return this; // Allow chaining if needed by real code
        }),
        join: jest.fn(),
        leave: jest.fn(),
        to: jest.fn(() => ({
            emit: jest.fn(),
        })),
        broadcast: {
            emit: jest.fn(),
        },
        handshake: {
            auth: {},
            query: {},
            headers: {},
        },
        // Method to simulate an event being emitted TO the socket (for testing its handlers)
        simulateEmit: function (event, ...args) {
            const handler = this._handlers.get(event);
            if (handler) {
                handler(...args);
            }
        },
    };
    return mockSocket;
};

// Create the *mocked* Server constructor function
// This is what will be used when the real code does 'new Server(...)'
const MockServer = jest.fn((config) => {
    // This function simulates what the real Socket.IO Server constructor does
    // It returns an object representing the server instance
    // This object should have the methods your tests (or the code under test) expect

    // Store connection listeners registered via io.on('connection', ...)
    const connectionListeners = [];

    return {
        // Mock the 'on' method of the server instance
        // This is used to register top-level events like 'connection'
        on: jest.fn((event, handler) => {
            if (event === 'connection') {
                // Store the connection handler
                connectionListeners.push(handler);
                // In a real scenario, this handler would be called when a client connects.
                // In the test, you might need a way to trigger this.
                // For now, we just store it.
            }
            // You could add other server-level event handlers here if needed
        }),

        // Mock the 'emit' method of the server instance
        emit: jest.fn(),

        // Mock the 'close' method of the server instance
        close: jest.fn(),

        // Mock the 'to' method of the server instance (for broadcasting to rooms/sockets)
        to: jest.fn(() => ({
            emit: jest.fn() // The return value of 'to' should also have an 'emit' method
        })),

        // Add other methods your tests might expect on the server instance
        // For example, 'use' for middleware, 'of' for namespaces, etc.
        // use: jest.fn(),
        // of: jest.fn(() => (/* return another mock namespace */)),

        // --- Add a helper method to trigger connection events for testing ---
        // This is *not* part of the real Socket.IO API, but useful for tests
        // You can call this method in your test to simulate a client connecting
        simulateConnection: (socketId) => {
            const mockSocket = createMockSocket(socketId);
            // Call all registered connection listeners with the mock socket
            connectionListeners.forEach(listener => listener(mockSocket));
            // Return the mock socket so the test can inspect or interact with it
            return mockSocket;
        },


        use: jest.fn((middleware) => {
            const mockSocket = {
                id: 'mock-socket-id',
                handshake: {
                    auth: { token: 'mock-token' },
                },
                on: jest.fn(),
                emit: jest.fn(),
                disconnect: jest.fn(),
            };
            const next = jest.fn();
            middleware(mockSocket, next);
        }),

        // If Socket.IO server has an 'engine' property with methods like 'close',
        // mock it if your tests access it (though less common)
        // engine: {
        //   close: jest.fn()
        // },

        // You might also need to mock other properties if your tests access them
        // For example, a way to get connected sockets (though this is often done via namespaces)
        // sockets: {
        //   on: jest.fn(),
        //   emit: jest.fn()
        // }
    };
});

// Export the *mocked* Server constructor as the default export
// This is what will be imported when the test file does 'import Server from "socket.io"'
export const Server = MockServer;

// If you also need named exports, you can add them:
// export const Server = MockServer; // Although default import is more common for socket.io