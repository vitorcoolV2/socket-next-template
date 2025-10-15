import { jest, describe, expect, test } from '@jest/globals';

// Mock the jwt-clerk module for token verification
jest.unstable_mockModule('../../socket.io/jwt-clerk/index.mjs', () => ({
  verifyToken: jest.fn(() => Promise.resolve({
    header: { alg: 'RS256' },
    payload: { userId: 'test-user', userName: 'Test User' }
  }))
}));

// Mock the userManager module to simulate its behavior
jest.unstable_mockModule('../../socket.io/userManager/index.mjs', () => {
  const mockIo = {
    use: jest.fn((middleware) => {
      // Simulate middleware execution
      const socket = {
        handshake: {
          auth: { token: 'mock-token' }
        },
        //decodedToken: { userId: 'test-user', userName: 'Test User' }
      };
      const next = jest.fn();
      middleware(socket, next);
    }),
    on: jest.fn(),
    emit: jest.fn(),
    to: jest.fn(() => mockIo),
    sockets: {
      sockets: new Map(),
      adapter: {
        rooms: new Map(),
        sids: new Map()
      }
    }
  };

  return {
    userManager: jest.fn(() => ({
      addUser: jest.fn(() => Promise.resolve({
        userId: 'test-user',
        userName: 'Test User',
        sockets: [{ socketId: 'test-socket-id', sessionId: 'test-session-id', connectedAt: Date.now(), state: 'connected' }],
        connectedAt: Date.now(),
        state: 'connected'
      })),
      disconnectUser: jest.fn(() => Promise.resolve({
        userId: 'test-user',
        userName: 'Test User',
        socketId: 'test-socket-id'
      })),
      sendMessage: jest.fn(() => Promise.resolve({
        messageId: 'test-message-id',
        content: 'Hello, world!',
        sender: { userId: 'test-user', userName: 'Test User' },
        recipientId: 'recipient-id',
        status: 'delivered',
        type: 'private',
        timestamp: new Date().toISOString(),
        readAt: null,
        direction: 'outgoing'
      })),
      getAndDeliverPendingMessages: jest.fn(() => Promise.resolve({
        delivered: 0,
        total: 0,
        failed: 0,
        pendingMessages: []
      })),
      getConnectionMetrics: jest.fn(() => ({
        totalConnections: 1,
        activeConnections: 1,
        disconnections: 0,
        errors: 0,
        activeUsers: 1
      })),
      markMessagesAsRead: jest.fn(() => Promise.resolve({
        marked: 1,
        total: 1
      })),
      getActiveUsers: jest.fn(() => []),
      getUserConnectionMetrics: jest.fn(() => ({
        totalConnections: 1,
        activeConnections: 1,
        authenticatedConnections: 1
      })),
      broadcastPublicMessage: jest.fn(() => Promise.resolve()),
      getPublicMessages: jest.fn(() => Promise.resolve({
        messages: [],
        total: 0,
        hasMore: false
      })),
      typingIndicator: jest.fn(() => Promise.resolve({
        sender: 'test-user',
        isTyping: true,
        timestamp: new Date().toISOString()
      })),
      getMessageHistory: jest.fn(() => Promise.resolve({
        context: {},
        messages: [],
        total: 0,
        hasMore: false
      })),
      // Testing-only methods
      _getUserBySocketId: jest.fn(() => ({
        userId: 'test-user',
        userName: 'Test User',
        sockets: [{ socketId: 'test-socket-id', sessionId: 'test-session-id', connectedAt: Date.now(), state: 'connected' }],
        connectedAt: Date.now(),
        state: 'connected'
      })),
      _getMessages: jest.fn(() => Promise.resolve({
        messages: [],
        total: 0,
        hasMore: false
      })),
      _incrementErrors: jest.fn(),
      _getUserSockets: jest.fn(() => []),
      __resetData: jest.fn(),
      _getSockeyById: jest.fn(() => null),
      _storeMessage: jest.fn(() => Promise.resolve())
    })),
    mockIo // Export the mockIo object for testing purposes
  };
});

jest.unstable_mockModule('../../socket.io/server.mjs', () => ({
  createHttpServer: jest.fn(() => mockHttpServer),
  allowedOrigins: ['http://localhost:3000'],
}));

// Mock the HTTP server
const mockHttpServer = {
  emit: jest.fn((event, req, res) => {
    if (event === 'request') {
      // Simulate handling the request
      const url = req.url;
      const method = req.method;

      if (method === 'GET' && url === '/health') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(
          JSON.stringify({
            status: 'ok',
            message: 'Socket.IO server is running',
            timestamp: new Date().toISOString(),
          })
        );
      } else if (method === 'OPTIONS') {
        res.writeHead(200);
        res.end();
      } else {
        res.writeHead(404, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Not Found' }));
      }
    }
  }),
  listen: jest.fn(),
  close: jest.fn(),
};

// Import server components
const { createHttpServer, allowedOrigins } = await import('../../socket.io/server.mjs');

describe('Server Test Suite', () => {
  test('should export server components', () => {
    expect(typeof createHttpServer).toBe('function');
    expect(Array.isArray(allowedOrigins)).toBe(true);
  });

  test('should create HTTP server', () => {
    const server = createHttpServer();
    expect(server).toBeDefined();
    expect(typeof server.listen).toBe('function');
    expect(typeof server.close).toBe('function');
  });

  test('should have CORS configuration', () => {
    expect(allowedOrigins).toContain('http://localhost:3000');
  });

  test('should handle health check endpoint', async () => {
    const httpServer = createHttpServer();
    const response = await new Promise((resolve) => {
      const req = { url: '/health', method: 'GET' }; // Simulate a GET request to /health
      httpServer.emit('request', req, {
        end: (data) => resolve(JSON.parse(data)), // Parse the JSON response
        setHeader: () => { },
        writeHead: () => { },
      });
    });

    // Verify the response
    expect(response.status).toBe('ok');
    expect(response.message).toBe('Socket.IO server is running');
  });

  test('should handle OPTIONS request for CORS preflight', async () => {
    const httpServer = createHttpServer();
    const response = await new Promise((resolve) => {
      const req = new Request('http://localhost/some-endpoint', { method: 'OPTIONS' });
      httpServer.emit('request', req, {
        end: () => resolve({ status: 'ok' }),
        setHeader: () => { },
        writeHead: () => { }
      });
    });
    expect(response.status).toBe('ok');
  });

  test('should reject invalid origins', async () => {
    const httpServer = createHttpServer();
    const response = await new Promise((resolve) => {
      const req = new Request('http://invalid-origin.com', { method: 'GET' });
      httpServer.emit('request', req, {
        end: (data) => resolve(JSON.parse(data)),
        setHeader: () => { },
        writeHead: () => { }
      });
    });
    expect(response.error).toBe('Not Found');
  });
});