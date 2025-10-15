import { jest, describe, expect, test } from '@jest/globals';
import { userManager } from '../../../socket.io/userManager/index.mjs';

// Load tokens dynamically if necessary
const validToken = MOCK_TOKENS.validUser;
const eternalToken = MOCK_TOKENS.eternalUser;

describe('User Manager - getMessageHistory', () => {
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

  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  test('should retrieve message history for a valid user and socket', async () => {
    const senderSocketId = 'sender-socket-id';
    const recipientSocketId = 'recipient-socket-id';
    const senderUserId = 'sender-user-id';
    const recipientUserId = 'recipient-user-id';

    // Add and authenticate sender and recipient users
    await addAndAuthenticateUser(senderSocketId, senderUserId, 'Sender User', validToken);
    await addAndAuthenticateUser(recipientSocketId, recipientUserId, 'Recipient User', eternalToken);

    // Send a message from sender to recipient
    const messageContent = 'Hello, this is a test message!';
    await manager.sendMessage(senderSocketId, recipientUserId, messageContent);

    // Retrieve message history for the recipient
    const options = {
      //userId: recipientUserId,
      limit: 10,
      offset: 0,
      type: 'private',
    };

    const result = await manager.getMessageHistory(recipientSocketId, options);

    // Validate the result
    expect(result.messages.length).toBeGreaterThanOrEqual(0); // 0=mem, 10=pg
    expect(result.messages[0].content).toBe(messageContent); // Message content matches
    expect(result.total).toBeGreaterThanOrEqual(1); //  1=mem, 10=pg
    expect(result.hasMore).toBe(false); // No more messages to paginate
  });

  test('should throw an error for invalid socket ID', async () => {
    const invalidSocketId = 'invalid-socket-id';

    // Call getMessageHistory with an invalid socket ID
    await expect(
      manager.getMessageHistory(invalidSocketId, {})
    ).rejects.toThrow(`Error fetching messages to ${invalidSocketId}`);
  });

  test('should throw an error for invalid options', async () => {
    const senderSocketId = 'sender-socket-id';
    const senderUserId = 'sender-user-id';

    // Add and authenticate the sender user
    await addAndAuthenticateUser(senderSocketId, senderUserId, 'Sender User', validToken);

    // Invalid options (missing required fields)
    const invalidOptions = {
      invalidProp: 'value',
    };

    // Call getMessageHistory with invalid options
    await expect(
      manager.getMessageHistory(senderSocketId, invalidOptions)
    ).rejects.toThrow(`Error fetching messages to ${senderSocketId}`);
  });

  test('should return an empty array when no messages are found', async () => {
    const senderSocketId = 'sender-socket-id';
    const senderUserId = 'sender-user-id';

    // Add and authenticate the sender user
    await addAndAuthenticateUser(senderSocketId, senderUserId, 'Sender User', validToken);

    // Retrieve message history for the sender (no messages exist)
    const options = {
      //userId: senderUserId,
      limit: 10,
      offset: 0,
      type: 'private',
    };

    const result = await manager.getMessageHistory(senderSocketId, options);

    // Validate the result
    expect(result.messages.length).toBe(0); // No messages should be retrieved
    expect(result.total).toBe(0); // Total messages count is zero
    expect(result.hasMore).toBe(false); // No more messages to paginate
  });

  test('should handle edge cases for limit and offset', async () => {
    const senderSocketId = 'sender-socket-id';
    const recipientSocketId = 'recipient-socket-id';
    const senderUserId = 'sender-user-id';
    const recipientUserId = 'recipient-user-id';

    // Add and authenticate sender and recipient users
    await addAndAuthenticateUser(senderSocketId, senderUserId, 'Sender User', validToken);
    await addAndAuthenticateUser(recipientSocketId, recipientUserId, 'Recipient User', validToken);

    // Send multiple messages from sender to recipient
    const messages = ['Message 1', 'Message 2', 'Message 3'];
    for (const content of messages) {
      await manager.sendMessage(senderSocketId, recipientUserId, content);
    }

    // Retrieve message history with limit = 0
    let options = {
      //userId: recipientUserId,
      limit: 0,
      offset: 0,
      type: 'private',
    };

    let result = await manager.getMessageHistory(recipientSocketId, options);
    expect(result.messages.length).toBe(0); // No messages should be retrieved

    // Retrieve message history with offset > total messages
    options = {
      //      userId: recipientUserId,
      limit: 10,
      offset: 10,
      type: 'private',
    };

    result = await manager.getMessageHistory(recipientSocketId, options);
    expect(result.messages.length).toBeGreaterThanOrEqual(0); // 0=mem, 10=pg
  });

  test('should filter messages by type', async () => {
    const senderSocketId = 'sender-socket-id';
    const recipientSocketId = 'recipient-socket-id';
    const senderUserId = 'sender-user-id';
    const recipientUserId = 'recipient-user-id';

    // Add and authenticate sender and recipient users
    await addAndAuthenticateUser(senderSocketId, senderUserId, 'Sender User', validToken);
    await addAndAuthenticateUser(recipientSocketId, recipientUserId, 'Recipient User', validToken);


    // Broadcast a public message
    await manager.broadcastPublicMessage(senderSocketId, 'Public message1');

    // Send a private message
    await manager.sendMessage(senderSocketId, recipientUserId, 'Private message1');
    // Send a private message
    await manager.sendMessage(senderSocketId, recipientUserId, 'Private message2');

    // Broadcast a public message
    await manager.broadcastPublicMessage(senderSocketId, 'Public message2');

    // Retrieve private messages
    const privateOptions = {
      //    userId: recipientUserId,
      limit: 10,
      offset: 0,
      type: 'private',
    };

    let result = await manager.getMessageHistory(recipientSocketId, privateOptions);
    expect(result.messages.length).toBeGreaterThanOrEqual(2); // 2=mem, 10=pg
    // Retrieve public messages
    const publicOptions = {
      limit: 10,
      offset: 0,
      type: 'public',
    };
    result = await manager.getPublicMessages(recipientSocketId);
    expect(result.messages.length).toBeGreaterThanOrEqual(2); // 2=mem, 50=pg

    result = await manager.getMessageHistory(senderSocketId, publicOptions);
    expect(result.messages.length).toBeGreaterThanOrEqual(2); // 2=mem, 10=pg

    result = await manager.getMessageHistory(recipientSocketId, publicOptions);
    expect(result.messages.length).toBeGreaterThanOrEqual(2); // 2=mem, 10=pg
  });
});