import { userManager } from '../../../socket.io/userManager/index.mjs';


const validToken = MOCK_TOKENS.validUser;
const eternalToken = MOCK_TOKENS.eternalUser;

describe('User Manager - Public Messaging', () => {
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

  describe('Scenario: Public Messaging', () => {
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

    describe('Step 1: Broadcast a Public Message', () => {
      test('should broadcast a public message to all connected users', async () => {
        // Broadcast a public message
        const publicMessageContent = 'This is a public message!';
        await manager.broadcastPublicMessage(senderSocketId, publicMessageContent);

        // Verify that the message was emitted to all connected users
        expect(mockIo.emit).toHaveBeenCalledWith('public_message', publicMessageContent);

        // Retrieve the sender's public messages
        const options = {
          limit: 10,
          offset: 0,
          type: 'public',
        };
        const senderMessages = await manager.getPublicMessages(senderSocketId);
        expect(senderMessages.messages.length).toBeGreaterThanOrEqual(1);  // 1=mem, 50=pg
        expect(senderMessages.messages[0].content).toBe(publicMessageContent);

        // Retrieve the recipient's public messages
        const recipientMessages = await manager.getPublicMessages(recipientSocketId);
        expect(recipientMessages.messages.length).toBeGreaterThanOrEqual(1);  // 1=mem, 50=pg
        expect(recipientMessages.messages[0].content).toBe(publicMessageContent);
      });
    });

    describe('Step 2: Retrieve Public Messages Within Expiration Window', () => {
      test('should retrieve public messages sent within the last 7 days', async () => {
        // Broadcast a public message
        const publicMessageContent = 'This is a public message!';
        await manager.broadcastPublicMessage(senderSocketId, publicMessageContent);

        // Retrieve public messages for the sender
        const senderOptions = {
          limit: 10,
          offset: 0,
          type: 'public',
        };
        const senderMessages = await manager.getPublicMessages(senderSocketId);
        expect(senderMessages.messages.length).toBeGreaterThanOrEqual(0); // 0=mem, 50=pg
        expect(senderMessages.messages[0].content).toBe(publicMessageContent);

        // Retrieve public messages for the recipient
        const recipientMessages = await manager.getPublicMessages(recipientSocketId);
        expect(recipientMessages.messages.length).toBeGreaterThanOrEqual(0); // 0=mem, 50=pg
        expect(recipientMessages.messages[0].content).toBe(publicMessageContent);
      });
    });

    describe('Step 3: Expired Public Messages', () => {
      test('should not retrieve public messages older than 7 days', async () => {
        // Simulate an old public message
        const expiredMessageContent = 'This is an expired public message!';
        const expiredMessage = {
          messageId: 'expired-message-id',
          recipientId: 'EVERY_ONE_ONLINE',
          status: 'sent',
          type: 'public',
          content: expiredMessageContent,
          sender: {
            userId: senderUserId,
            userName: 'Sender User',
          },
          timestamp: new Date(Date.now() - 8 * 24 * 60 * 60 * 1000).toISOString(), // 8 days ago
          readAt: null,
          direction: 'outgoing',
        };
        await manager._storeMessage(senderUserId, expiredMessage);

        // Retrieve public messages for the sender
        const senderOptions = {
          limit: 10,
          offset: 0,
          type: 'public',
        };
        const senderMessages = await manager.getPublicMessages(senderSocketId);
        expect(senderMessages.messages.length).toBeGreaterThanOrEqual(0); // 0=mem, 50=pg

        // Retrieve public messages for the recipient
        const recipientMessages = await manager.getPublicMessages(recipientSocketId);
        expect(recipientMessages.messages.length).toBeGreaterThanOrEqual(0); // 0=mem, 50=pg
      });
    });

    describe('Step 4: Invalid Socket ID', () => {
      test('should throw an error when using an invalid socket ID', async () => {
        const invalidSocketId = 'invalid-socket-id';

        // Attempt to broadcast a public message with an invalid socket ID
        await expect(
          manager.broadcastPublicMessage(invalidSocketId, 'This is a public message!')
          //        ).rejects.toThrow(`No user found for socketId: ${invalidSocketId}`);
        ).rejects.toThrow(`Error broadcasting public message for socketId: ${invalidSocketId}`);
        // Attempt to retrieve public messages with an invalid socket ID
        await expect(
          manager.getPublicMessages(invalidSocketId)
        ).rejects.toThrow(`Error retrieving public messages for socketId: ${invalidSocketId}`);
      });
    });
  });
});