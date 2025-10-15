import { userManager } from '../../../socket.io/userManager/index.mjs';

const validToken = MOCK_TOKENS.validUser;
const eternalToken = MOCK_TOKENS.eternalUser;

describe('User Manager - Connection Metrics', () => {
  let manager;
  let mockIo;

  beforeEach(() => {
    mockIo = {
      on: jest.fn(),
      emit: jest.fn(),
      to: jest.fn(() => mockIo),
      sockets: {
        sockets: new Map(),
      },
      _middleware: [],
      use: function (middleware) {
        this._middleware.push(middleware);
      },
      invokeMiddleware: async function (socket, next) {
        for (const middleware of this._middleware) {
          await middleware(socket, next);
        }
      },
    };

    manager = userManager({ io: mockIo, defaultStorage: USER_MANAGER_PERSIST || 'memory', maxTotalConnections: 5 });

  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  /**
   * Utility function to add and authenticate a user
   */
  const addAndAuthenticateUser = async (socketId, userId, userName, token) => {
    // Step 1: Add the user
    await manager.addUser(socketId, { userId, userName });

    // Step 2: Simulate Socket.IO handshake with a valid token
    const socket = {
      id: socketId,
      handshake: {
        auth: { token }, // Ensure the token is passed here
      },
    };
    const next = jest.fn(); // Mock the next function
    await mockIo.invokeMiddleware(socket, next);

    // Step 3: Ensure authentication succeeded
    expect(next).toHaveBeenCalledWith(); // No error passed to next()

    // Validate the user's state
    const user = await manager._getUserBySocketId(socketId);
    expect(user).toBeDefined();
    expect(user.state).toBe('authenticated');

    return user; // Return the user object
  };

  describe('Scenario: User Connection Metrics', () => {
    const senderSocketId = 'sender-socket-id';
    const recipientSocketId = 'recipient-socket-id';
    const senderUserId = 'sender-user-id';
    const recipientUserId = 'recipient-user-id';

    beforeEach(async () => {
      // Add and authenticate the sender user
      await addAndAuthenticateUser(senderSocketId, senderUserId, 'Sender User', validToken);

      // Add and authenticate the recipient user
      await addAndAuthenticateUser(recipientSocketId, recipientUserId, 'Recipient User', eternalToken);
    });

    afterEach(async () => {
      // Disconnect the sender user
      await manager.disconnectUser(senderSocketId);

      // Disconnect the recipient user
      await manager.disconnectUser(recipientSocketId);
    });

    describe('Step 1: getUserConnectionMetrics', () => {
      test('should return connection metrics for a valid user', async () => {
        // Get connection metrics for the sender user
        const metrics = manager.getUserConnectionMetrics(senderUserId);

        // Validate the result
        expect(metrics.totalConnections).toBe(1); // One socket connection
        expect(metrics.activeConnections).toBe(1); // One active connection
        expect(metrics.authenticatedConnections).toBe(1); // One authenticated connection
      });

      test('should handle an invalid user gracefully', async () => {
        // Get connection metrics for an invalid user
        const metrics = manager.getUserConnectionMetrics('invalid-user-id');

        // Validate the result
        expect(metrics.totalConnections).toBe(0); // No connections
        expect(metrics.activeConnections).toBe(0); // No active connections
        expect(metrics.authenticatedConnections).toBe(0); // No authenticated connections
      });
    });

    describe('Step 2: getConnectionMetrics', () => {
      test('should return global connection metrics', async () => {
        // Get global connection metrics
        const metrics = manager.getConnectionMetrics();

        // Validate the result
        expect(metrics.totalConnections).toBe(2); // Two total connections (sender + recipient)
        expect(metrics.activeConnections).toBe(2); // Two active connections
        expect(metrics.disconnections).toBe(0); // No disconnections yet
        expect(metrics.errors).toBe(0); // No errors
        expect(metrics.activeUsers).toBe(2); // Two active users
      });

      test('should reflect disconnections in global metrics', async () => {
        // Disconnect the sender user
        await manager.disconnectUser(senderSocketId);

        // Get global connection metrics
        const metrics = manager.getConnectionMetrics();


        // Validate the result
        expect(metrics.totalConnections).toBe(2); // Total connections remain unchanged
        expect(metrics.activeConnections).toBe(1); // One active connection (recipient only)
        expect(metrics.disconnections).toBe(1); // One disconnection (sender)
        expect(metrics.errors).toBe(0); // No errors
        expect(metrics.activeUsers).toBe(1); // One active user (recipient only)
      });
    });
  });
});