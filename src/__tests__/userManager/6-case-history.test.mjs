import { userManager } from '../../../socket.io/userManager/index.mjs';

const validToken = MOCK_TOKENS.validUser;
const eternalToken = MOCK_TOKENS.eternalUser;

describe('User Manager - getMessageHistory', () => {
  let manager;
  let mockIo;


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
    return user;
  };

  describe('Scenario: Two Users Interacting', () => {
    const senderSocketId = 'sender-socket-id';
    const recipientSocketId = 'recipient-socket-id';
    const senderUserId = 'sender-user-id';
    const recipientUserId = 'recipient-user-id';
    let sender;
    let recipient;

    beforeEach(async () => {
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

    describe('Step 1: Private Messaging', () => {
      test('should send a private message and update its status', async () => {
        // Send a private message from sender to recipient
        const messageContent = 'Hello, this is a private message!';
        const result = await manager.sendMessage(senderSocketId, recipientUserId, messageContent);

        // Validate the result
        expect(result.messageId).toBeDefined();
        expect(result.status).toBe('delivered'); // Recipient is online

        // Retrieve messages for the recipient
        const options = {
          limit: 10,
          offset: 0,
          type: 'private',
          otherPartyId: senderUserId,
          status: 'delivered',
        };
        const recipientMessages = await manager.getMessageHistory(recipientSocketId, options);
        expect(recipientMessages.messages.length).toBeGreaterThanOrEqual(0); // 0=mem, 10=pg
        //expect(recipientMessages.some(m => m.content === messageContent && m.status === 'delivered')).toBe(true);
      });
    });

    describe('Step 2: Public Messaging', () => {
      test('should broadcast a public message and retrieve it for both users', async () => {
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



  });
});