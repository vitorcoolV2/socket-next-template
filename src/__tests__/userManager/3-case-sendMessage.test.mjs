
import { userManager } from '../../../socket.io/userManager/index.mjs';


const validToken = MOCK_TOKENS.validUser;
const eternalToken = MOCK_TOKENS.eternalUser;

describe('User Manager - sendMessage & getAndDeliverPendingMessages', () => {
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

  describe('Scenario: Sending Messages', () => {
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

    describe('Step 1: sendMessage - Valid Recipient', () => {
      test('should send a message and mark it as delivered if the recipient is online', async () => {
        mockIo.emit.mockClear();

        const messageContent = 'Hello, this is a test message!';
        const result = await manager.sendMessage(senderSocketId, recipientUserId, messageContent);

        // Validate the result
        expect(result.messageId).toBeDefined();
        expect(result.status).toBe('delivered'); // Recipient is online

        // Verify that the message was emitted to the recipient
        expect(mockIo.to).toHaveBeenCalledWith(expect.any(String)); // Ensure the recipient's socket ID was targeted
        //     
        expect(mockIo.emit).toHaveBeenCalledWith('private_message', expect.objectContaining({
          messageId: expect.any(String),
          content: messageContent,
          sender: { userId: senderUserId, userName: 'Sender User' },
          recipientId: recipientUserId,
          status: 'delivered',
          type: 'private',
          timestamp: expect.any(Date),
          readAt: null,
          direction: 'incoming',
        }));
      });
    });

    describe('Step 2: sendMessage - Offline Recipient', () => {
      test('should send a message and mark it as pending if the recipient is offline', async () => {


        // Disconnect the recipient user
        await manager.disconnectUser(recipientSocketId);


        mockIo.to.mockClear();
        mockIo.emit.mockClear();

        // Send a private message from sender to recipient
        const messageContent = 'Hello, this is a test message!';
        const result = await manager.sendMessage(senderSocketId, recipientUserId, messageContent);

        // Validate the result
        expect(result.messageId).toBeDefined();
        expect(result.status).toBe('pending'); // Recipient is offline

        // Verify that no message was emitted to the recipient
        expect(mockIo.to).not.toHaveBeenCalled(); // No recipient socket ID should be targeted
        expect(mockIo.emit).not.toHaveBeenCalled(); // No message should be emitted
      });
    });

    describe('Step 3: sendMessage - Invalid Recipient @TODO', () => {
      test('should throw an error when sending a message to an invalid recipient', async () => {
        const invalidRecipientId = 'invalid-recipient-id';
        const messageContent = 'Hello, this is a test message!';

        // Attempt to send a message to an invalid recipient
        await expect(
          manager.sendMessage(senderSocketId, invalidRecipientId, messageContent)
        ).rejects.toThrow(`Error sending message from socketId ${senderSocketId} to recipientId ${invalidRecipientId}`);
      });
    });

    describe('Step 4: getAndDeliverPendingMessages - Deliver Pending Messages', () => {
      test('should deliver pending messages when the recipient comes online', async () => {
        // Disconnect the recipient user
        await manager.disconnectUser(recipientSocketId);

        // Send a private message while the recipient is offline
        const messageContent = 'Hello, this is a test message!';
        const result = await manager.sendMessage(senderSocketId, recipientUserId, messageContent);
        expect(result.status).toBe('pending'); // Message is pending

        //const s = await manager.disconnectUser(senderSocketId);
        //expect(s.state).toBe('offline');
      });
      test('should receive pending messages when recipient comes online', async () => {

        await manager.disconnectUser(recipientSocketId);

        // Send a private message while the recipient is offline
        const messageContent = 'Hello, this is a test message!';
        const result = await manager.sendMessage(senderSocketId, recipientUserId, messageContent);
        expect(result.status).toBe('pending'); // Message is pending


        // Reconnect the recipient user
        await addAndAuthenticateUser(recipientSocketId, recipientUserId, 'Recipient User', eternalToken);

        // Retrieve and deliver pending messages
        const deliveryResult = await manager.getAndDeliverPendingMessages(recipientSocketId);

        // Validate the delivery result
        expect(deliveryResult.delivered.length).toBeGreaterThanOrEqual(1); // One message MEMORY, 3 = PG
        expect(deliveryResult.total).toBeGreaterThanOrEqual(1); //  One message MEMORY, 3 = PG
        expect(deliveryResult.failed).toBe(0); // No failures
        expect(deliveryResult.pendingMessages.length).toBe(0); // 0 pending message

        // Verify that the message status was updated to 'delivered'
        const options = {
          limit: 10,
          offset: 0,
          type: 'private',
          otherPartyId: senderUserId,
        };
        const messages = await manager._getMessages(recipientUserId, options);
        //expect(messages.messages.some(m => m.status === 'delivered')).toBe(true); // Message status updated
      });


    });

    describe('Step 5: getAndDeliverPendingMessages - No Pending Messages', () => {

      test('should handle cases where there are no pending messages', async () => {
        const sender = await manager.disconnectUser(senderSocketId);
        expect(sender.state).toBe('offline');


        // try deliver messages. will Retrieve and deliver pending messages if sender  is online
        const deliveryResult = await manager.getAndDeliverPendingMessages(recipientSocketId);

        // expected the delivery result
        expect(deliveryResult.delivered.length).toBe(0);
        expect(deliveryResult.total).toBe(0);
        expect(deliveryResult.failed).toBe(0);
        expect(deliveryResult.pendingMessages.length).toBe(0); // No pending messages. should't be one just step 4?
      });
    });

    describe('Step 6: getAndDeliverPendingMessages - Invalid Socket ID', () => {
      test('should throw an error when using an invalid socket ID', async () => {
        const invalidSocketId = 'invalid-socket-id';

        // Attempt to retrieve pending messages with an invalid socket ID
        await expect(
          manager.getAndDeliverPendingMessages(invalidSocketId)
        ).rejects.toThrow(`Error retrieving pending messages for socketId: ${invalidSocketId}`);
      });
    });
  });
});