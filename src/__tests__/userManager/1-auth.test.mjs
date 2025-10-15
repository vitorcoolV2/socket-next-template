import { jest, describe, expect, test } from '@jest/globals';
import { userManager } from '../../../socket.io/userManager/index.mjs';


// Load tokens dynamically if necessary
const invalidToken = MOCK_TOKENS.expiredUser;
const validToken = MOCK_TOKENS.validUser;
const eternalToken = MOCK_TOKENS.eternalUser;


describe('User Manager', () => {
  let manager;
  let mockIo;

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
        auth: { token },
      },
    };
    const next = jest.fn(); // Mock the next function
    await mockIo.invokeMiddleware(socket, next);

    // Step 3: Ensure authentication succeeded
    expect(next).toHaveBeenCalledWith(); // No error passed to next()
  };

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


    expect(mockIo.to).not.toHaveBeenCalled();
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('User Management', () => {

    test('should add user', async () => {
      const socketId = 'socket-123';
      const userData = { userId: 'user-123', userName: 'Test User' };

      await addAndAuthenticateUser(socketId, userData.userId, userData.userName, validToken);
      const user = manager._getUserBySocketId(socketId);

      expect(user).toBeDefined();
      expect(user.userId).toBe('user-123');
      expect(user.userName).toBe('Test User');
    });

    test('should authenticate user during Socket.IO handshake', async () => {
      const socketId = 'socket-123';
      const userId = 'user-123';

      // Add a user
      await manager.addUser(socketId, { userId, userName: 'Test User' });

      // Simulate Socket.IO handshake with a valid token
      const socket = {
        id: socketId,
        handshake: {
          auth: { token: validToken }, // Use the valid token
        },
      };

      const next = jest.fn(); // Mock the next function
      await mockIo.invokeMiddleware(socket, next);

      // Verify that authentication succeeded
      expect(next).toHaveBeenCalledWith(); // No error passed to next()
      const user = manager._getUserBySocketId(socketId);
      expect(user.state).toBe('authenticated');
    });

    test('should fail authentication with invalid token', async () => {
      const socketId = 'socket-123';
      const userId = 'user-123';

      await manager.addUser(socketId, { userId, userName: 'Test User' });

      const socket = {
        id: socketId,
        handshake: {
          auth: { token: invalidToken },
        },
      };

      const next = jest.fn();
      await mockIo.invokeMiddleware(socket, next);

      expect(next).toHaveBeenCalledWith(expect.any(Error));
      expect(next.mock.calls[0][0].message).toBe(`Authentication failed: Error authenticating user for socket ${socketId}`);
    });
  });
  describe('User Typing', () => {

    test('should send typing indicator to recipient when isTyping is true', async () => {
      const senderSocketId = 'sender-socket-id';
      const recipientSocketId = 'recipient-socket-id';

      // Add and authenticate sender and recipient users
      await addAndAuthenticateUser(senderSocketId, 'sender-user-id', 'Sender User', validToken);
      await addAndAuthenticateUser(recipientSocketId, 'recipient-user-id', 'Recipient User', validToken);

      // Typing data
      const typingData = {
        isTyping: true,
        recipientId: 'recipient-user-id',
      };

      // Call the typingIndicator function
      await manager.typingIndicator(senderSocketId, typingData);

      // Verify that the recipient received the typing indicator
      expect(mockIo.to).toHaveBeenCalledWith(recipientSocketId);
      expect(mockIo.emit).toHaveBeenCalledWith('typingIndicator', {
        success: true,
        event: 'typingIndicator',
        sender: 'sender-user-id',       // Flattened sender ID
        isTyping: true,                 // Flattened isTyping
        timestamp: expect.any(String),  // Flattened timestamp
      });
    });

  })

  describe('Connection Metrics', () => {
    test('should provide connection metrics', () => {
      manager.addUser('socket-1', { userId: 'user-1', userName: 'User One' });
      manager.addUser('socket-2', { userId: 'user-2', userName: 'User Two' });

      const metrics = manager.getConnectionMetrics();
      expect(metrics.totalConnections).toBe(2);
      expect(metrics.activeConnections).toBe(2);
    });
  });
});