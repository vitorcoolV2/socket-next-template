import { userManager } from '../../../socket.io/userManager/index.mjs';

const validToken = MOCK_TOKENS.validUser;
const eternalToken = MOCK_TOKENS.eternalUser;

describe('User Manager - Typing Indicator', () => {
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

  describe('Scenario: Typing Indicator Interaction', () => {
    const senderSocketId = 'sender-socket-id';
    const recipientSocketId = 'recipient-socket-id';
    const senderUserId = 'sender-user-id';
    const recipientUserId = 'recipient-user-id';
    let sender;
    let recipient;

    beforeEach(async () => {
      // Add and authenticate the sender user
      sender = await addAndAuthenticateUser(senderSocketId, senderUserId, 'Sender User', validToken);

      // Add and authenticate the recipient user
      recipient = await addAndAuthenticateUser(recipientSocketId, recipientUserId, 'Recipient User', eternalToken);
    });

    afterEach(async () => {
      // Disconnect the sender user
      const resp1 = await manager.disconnectUser(senderSocketId);
      expect(resp1.state).toBe('offline'); // Validate the sender's state
      expect(resp1.sockets.length).toBe(0); // Validate that no sockets remain

      // Disconnect the recipient user
      const resp2 = await manager.disconnectUser(recipientSocketId);
      expect(resp2.state).toBe('offline'); // Validate the recipient's state
      expect(resp2.sockets.length).toBe(0); // Validate that no sockets remain
    });

    describe('Step 1: Typing Indicator Sent Successfully', () => {
      test('should send a typing indicator to the recipient', async () => {
        // Simulate the sender typing
        const isTyping = true;
        const result = await manager.typingIndicator(senderSocketId, {
          isTyping,
          recipientId: recipientUserId,
        });

        // Validate the result
        expect(result).toBeDefined();
        expect(result.sender).toBe(senderUserId);
        expect(result.isTyping).toBe(isTyping);
        expect(typeof result.timestamp).toBe('string'); // Ensure timestamp is a string

        // Verify that the typing indicator was emitted to the recipient
        expect(mockIo.to).toHaveBeenCalledWith(expect.any(String)); // Ensure the recipient's socket ID was targeted
        expect(mockIo.emit).toHaveBeenCalledWith('typingIndicator', {
          success: true,
          event: 'typingIndicator',
          sender: senderUserId,
          isTyping,
          timestamp: expect.any(String), // Ensure timestamp is included
        });
      });
    });

    describe('Step 2: Typing Indicator Stopped Successfully', () => {
      test('should stop the typing indicator for the recipient', async () => {
        // Simulate the sender stopping typing
        const isTyping = false;
        const result = await manager.typingIndicator(senderSocketId, {
          isTyping,
          recipientId: recipientUserId,
        });

        // Validate the result
        expect(result).toBeDefined();
        expect(result.sender).toBe(senderUserId);
        expect(result.isTyping).toBe(isTyping);
        expect(typeof result.timestamp).toBe('string'); // Ensure timestamp is a string

        // Verify that the typing indicator was emitted to the recipient
        expect(mockIo.to).toHaveBeenCalledWith(expect.any(String)); // Ensure the recipient's socket ID was targeted
        expect(mockIo.emit).toHaveBeenCalledWith('typingIndicator', {
          success: true,
          event: 'typingIndicator',
          sender: senderUserId,
          isTyping,
          timestamp: expect.any(String), // Ensure timestamp is included
        });
      });
    });

    describe('Step 3: Invalid Recipient', () => {
      test('should handle an invalid recipient gracefully', async () => {
        // Simulate the sender typing to an invalid recipient
        mockIo.to.mockClear();
        mockIo.emit.mockClear();

        const isTyping = true;
        const invalidRecipientId = 'invalid-recipient-id';
        const result = await manager.typingIndicator(senderSocketId, {
          isTyping,
          recipientId: invalidRecipientId,
        });

        // Validate the result
        expect(result).toBeNull(); // No result should be returned for an invalid recipient

        // Verify that no typing indicator was emitted
        expect(mockIo.to).not.toHaveBeenCalled(); // No recipient socket ID should be targeted
        expect(mockIo.emit).not.toHaveBeenCalled(); // No typing indicator should be emitted
      });
    });

    describe('Step 4: Missing Data', () => {
      test('should reject invalid or missing data', async () => {
        // Simulate sending invalid data
        await expect(
          manager.typingIndicator(senderSocketId, {})
        ).rejects.toThrow('Error handling typingIndicator');

        // Simulate sending missing data
        await expect(
          manager.typingIndicator(senderSocketId, null)
        ).rejects.toThrow('Error handling typingIndicator');
      });
    });
  });
});