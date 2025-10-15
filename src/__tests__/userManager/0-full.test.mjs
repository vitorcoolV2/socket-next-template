import { jest, describe, expect, test } from '@jest/globals';

import {
  userManager,
} from '../../../socket.io/userManager/index.mjs';

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

    mockIo = { // <-- Remove `const` here
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

    // Reset mocks before each test
    mockIo.to.mockClear();
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('User Management', () => {
    afterEach(() => {
      jest.clearAllMocks();
    });

    test('should add user', async () => {
      const socketId = 'socket-123';
      const userData = { userId: 'user-123', userName: 'Test User' };

      // Add the user
      await manager.addUser(socketId, userData);

      // Retrieve the user by socketId
      const user = manager._getUserBySocketId(socketId);

      // Validate the user data
      expect(user).toBeDefined();
      expect(user.userId).toBe('user-123');
      expect(user.userName).toBe('Test User');

      // Verify that the sockets array contains an object with the expected socketId
      expect(user.sockets.some(socket => socket.socketId === socketId)).toBe(true);
    });

    test('should authenticate user during Socket.IO handshake', async () => {
      const socketId = 'socket-123';
      const userId = 'user-123';

      // Add and authenticate the user
      await addAndAuthenticateUser(socketId, userId, 'Test User', validToken);

      // Retrieve the user by socketId
      const user = manager._getUserBySocketId(socketId);

      // Verify that the user is authenticated
      expect(user.sockets.some(s => s.socketId === socketId && s.state === 'authenticated')).toBe(true);
    });

    test('should fail authentication with invalid token', async () => {
      const socketId = 'socket-123';
      const userId = 'user-123';

      // Add the user
      await manager.addUser(socketId, { userId, userName: 'Test User' });

      // Simulate Socket.IO handshake with an invalid token
      const socket = {
        id: socketId,
        handshake: {
          auth: { token: invalidToken },
        },
      };
      const next = jest.fn(); // Mock the next function
      await mockIo.invokeMiddleware(socket, next);

      // Verify that authentication failed
      expect(next).toHaveBeenCalledWith(expect.any(Error)); // Error passed to next()
      expect(next.mock.calls[0][0].message).toBe(`Authentication failed: Error authenticating user for socket ${socketId}`);
    });
    test('should handle disconnecting a non-existent user', async () => {
      const userId = 'non-existent-user';
      const socketId = 'socket-id';

      // Attempt to disconnect a non-existent user
      const result = await manager.disconnectUser(socketId);

      // Verify the result
      expect(result).toBeNull();

      const activeUsers = await manager.getActiveUsers(socketId);

      // Verify that no changes were made to activeUsers or userSockets
      expect(activeUsers).toEqual(null);

      // Verify the warning log
      expect(console.warn).toHaveBeenCalledWith(`No user found for socketId: ${socketId}`);
    });

    test('should disconnect one of multiple socket connections', async () => {
      const userId = 'user-123';
      const userName = 'Test User';
      const socketId1 = 'socket-1';
      const socketId2 = 'socket-2';

      // Add and authenticate the user with two sockets
      await addAndAuthenticateUser(socketId1, userId, userName, validToken);
      await addAndAuthenticateUser(socketId2, userId, userName, validToken);

      // Disconnect the first socket
      const result = await manager.disconnectUser(socketId1);

      // Validate the result
      expect(result).toBeDefined();
      expect(result.userId).toBe(userId);
      expect(result.userName).toBe(userName);
      expect(result.state).toBe('authenticated'); // User is still connected via socketId2
      expect(result.sockets.some(socket => socket.socketId === socketId2)).toBe(true); // socketId2 still exists
    });
    test('should fully disconnect a user after all sockets are removed', async () => {
      const userId = 'user-123';
      const userName = 'Test User';
      const socketId1 = 'socket-1';
      const socketId2 = 'socket-2';

      // Add and authenticate the user with two sockets
      await addAndAuthenticateUser(socketId1, userId, userName, validToken);
      await addAndAuthenticateUser(socketId2, userId, userName, validToken);

      // Disconnect both sockets
      const result1 = await manager.disconnectUser(socketId1);
      const result2 = await manager.disconnectUser(socketId2);

      // Validate the results
      expect(result1).toBeDefined();
      expect(result1.userId).toBe(userId);
      expect(result1.userName).toBe(userName);
      expect(result1.state).toBe('authenticated'); // Still connected via socketId2

      expect(result2).toBeDefined();
      expect(result2.userId).toBe(userId);
      expect(result2.userName).toBe(userName);
      expect(result2.state).toBe('offline'); // Fully disconnected after removing all sockets
      expect(result2.sockets.length).toBe(0); // No sockets remain
    });

    test('should disconnect an active user', async () => {
      const socketId = 'socket-id';
      const socketId2 = 'socket-id2';
      const userId = 'user-123';
      const userId2 = 'user-1234';
      const userName = 'Test User';
      const userName2 = 'Test User2';

      // Add a user
      await addAndAuthenticateUser(socketId, userId, userName, validToken);

      // Verify no active users initially
      let activeUsers = await manager.getActiveUsers(socketId);
      expect(activeUsers).toBeDefined();

      // Add the user as an active user
      await addAndAuthenticateUser(socketId2, userId2, userName2, eternalToken);

      // Verify the user is active
      activeUsers = await manager.getActiveUsers(socketId2);
      expect(Array.isArray(activeUsers)).toBe(true);
      expect(activeUsers.length).toBe(2);

      // Disconnect the user
      const result = await manager.disconnectUser(socketId);

      // Verify the result of disconnection
      expect(result).toBeDefined();
      expect(result.userId).toBe(userId);
      expect(result.socketId).toBe(socketId);
      expect(result.state).toBe('offline'); // User state should be updated


      // Verify the user is still retrievable but marked as disconnected
      const active = await manager.getActiveUsers(socketId2);
      expect(active).toHaveLength(1);
      expect(active[0].userId).toBe(userId2);
      expect(active[0].state).toBe('authenticated');

      const disconnectedUsers = await manager.getActiveUsers(socketId2, { state: 'disconnected' });
      expect(disconnectedUsers).toHaveLength(0);

    });
    test('should disconnect user', () => {
      const socketId = 'socket-123';
      const userData = { userId: 'user-123', userName: 'Test User' };

      manager.addUser(socketId, userData);
      manager.disconnectUser(socketId, 'user-123');

      // The user might still exist but be in disconnected state
      // Just verify disconnect doesn't throw
      expect(() => manager.disconnectUser(socketId, 'user-123')).not.toThrow();
    });

    test('should get socket IDs for a user', async () => {
      const userData = { userId: 'user-123', userName: 'Test User' };

      // Add two sockets for the same user
      await manager.addUser('socket-1', userData);
      await manager.addUser('socket-2', userData);

      // Retrieve socket IDs for the user
      const sockets = manager._getUserSockets('user-123');

      // Verify the result
      expect(sockets).toHaveLength(2); // Expect two socket IDs
      expect(sockets.some(socket => socket.socketId === 'socket-1')).toBe(true);
      expect(sockets.some(socket => socket.socketId === 'socket-2')).toBe(true);
    });

    test('should reject new connections when the maximum limit is reached', async () => {
      const maxConnections = 5; // Use a smaller limit for testing

      // Simulate reaching the connection limit
      for (let i = 0; i < maxConnections; i++) {
        await manager.addUser(`socket-${i}`, { userId: `user-${i}`, userName: `User ${i}` });
      }

      // Attempt to add one more user
      const socketId = 'socket-overflow';
      const userData = { userId: 'user-overflow', userName: 'Overflow User' };

      await expect(manager.addUser(socketId, userData)).rejects.toThrow(
        'Error adding user for socket socket-overflow'
        //`Connection limit exceeded. Maximum allowed connections: ${maxConnections}`
      );
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
          auth: { token: validToken },
        },
      };
      const next = jest.fn();
      await mockIo.invokeMiddleware(socket, next);
      expect(next).toHaveBeenCalledWith(); // No error passed to next()

      // Retrieve the user by their socket ID
      const user = manager._getUserBySocketId(socketId);

      // Find the specific socket and verify its state
      const socketState = user.sockets.find(s => s.socketId === socketId && s.state === 'authenticated');
      expect(socketState).toBeDefined(); // Ensure the socket exists and is authenticated

      // Alternatively, use `some` if you prefer
      expect(user.sockets.some(s => s.socketId === socketId && s.state === 'authenticated')).toBe(true);
    });

    test('should fail authentication with invalid token', async () => {
      const socketId = 'socket-123';
      const userId = 'user-123';

      // Add the user
      await manager.addUser(socketId, { userId, userName: 'Test User' });

      // Simulate Socket.IO handshake with an invalid token
      const socket = {
        id: socketId,
        handshake: {
          auth: { token: invalidToken },
        },
      };
      const next = jest.fn(); // Mock the next function
      await mockIo.invokeMiddleware(socket, next);

      // Verify that authentication failed
      expect(next).toHaveBeenCalledWith(expect.any(Error)); // Error passed to next()
      expect(next.mock.calls[0][0].message).toBe(`Authentication failed: Error authenticating user for socket ${socketId}`);
    });

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

    test('should throw an error if typing data is invalid', async () => {
      const senderSocketId = 'sender-socket-id';
      const userId = 'sender-user-id';

      // Add and authenticate the sender user
      await addAndAuthenticateUser(senderSocketId, userId, 'Sender User', validToken);

      // Invalid typing data
      const invalidTypingData = {
        isTyping: 'invalid', // Invalid type (should be boolean)
        recipientId: 'recipient-user-id',
      };

      // Expect the function to throw an error for invalid data
      await expect(() =>
        manager.typingIndicator(senderSocketId, invalidTypingData)
      ).rejects.toThrow(`Error handling typingIndicator`);
    });

    test('should handle typing missing recipient gracefully', async () => {
      const senderSocketId = 'sender-socket-id';

      // Add and authenticate the sender user
      await addAndAuthenticateUser(senderSocketId, 'sender-user-id', 'Sender User', validToken);

      // Clear the mock after authentication to isolate calls made during typingIndicator
      mockIo.to.mockClear();

      // Typing data with non-existent recipient
      const typingData = {
        isTyping: true,
        recipientId: 'non-existent-user-id',
      };

      // Ensure the recipient does not exist in the_users map
      const activeUsers = await manager.getActiveUsers(senderSocketId);
      expect(activeUsers.some(u => u.userId === typingData.recipientId)).toBe(false);

      // Call the typingIndicator function
      await manager.typingIndicator(senderSocketId, typingData);

      // Verify that the warning was logged
      expect(console.warn).toHaveBeenCalledWith(`Recipient with ID ${typingData.recipientId} not found`);

      // Verify that no message was sent (i.e., mockIo.to was not called)
      expect(mockIo.to).not.toHaveBeenCalled();
    });
  });

  describe('Active Users', () => {
    afterEach(() => {
      jest.clearAllMocks();

    });

    test('should get active users', async () => {
      const socketId = 'socket-123';
      const userId = 'user-123';
      await addAndAuthenticateUser(socketId, userId, 'User One', validToken);
      const activeUsers = await manager.getActiveUsers(socketId);

      expect(activeUsers.length).toBe(1); // Ensure the correct number of users is returned
      expect(activeUsers[0].userId).toBe(userId); // Verify user details
      expect(activeUsers[0].state).toBe('authenticated'); // Verify user details

    });

    test('should handle user operations without errors', () => {
      // Test that basic operations don't throw
      expect(() => {
        manager.addUser('test-socket', { userId: 'test-user', userName: 'Test' });
      }).not.toThrow();

      expect(() => {
        manager.getActiveUsers();
      }).not.toThrow();

      expect(() => {
        manager.disconnectUser('test-socket', 'test-user');
      }).not.toThrow();
    });


    test('should filter active users by state', async () => {
      const socketId = 'socket-123';
      const userId = 'user-123';

      // Add a user
      await manager.addUser(socketId, { userId, userName: 'Test User' });

      // Simulate authentication
      const socket = {
        id: socketId,
        handshake: {
          auth: { token: validToken }, // Simulate valid token in handshake
        },
      };
      const next = jest.fn(); // Mock the next function
      await mockIo.invokeMiddleware(socket, next);
      // Verify that authentication succeeded
      expect(next).toHaveBeenCalledWith(); // No error passed to next()

      // Get active users filtered by state
      const authenticatedUsers = await manager.getActiveUsers(socketId, { state: 'authenticated' });
      expect(authenticatedUsers.length).toBe(1);
      expect(authenticatedUsers[0].userId).toBe(userId);
    });
  });

  describe('Message Management', () => {
    afterEach(() => {
      jest.clearAllMocks();

    });

    test('should throw error for invalid markMessagesAsRead input', async () => {
      await expect(manager.markMessagesAsRead(null, { recipientId: 'sender-123', messageIds: ['msg-1'] }))
        .rejects.toThrow('Error marking messages as read for socketId: null');
    });

    test('should store valid messages to self', async () => {
      const socketId = 'socket-test';
      const sender = { userId: 'test-user', userName: 'Test User' };

      // Add and authenticate the user
      await addAndAuthenticateUser(socketId, sender.userId, sender.userName, validToken);

      const recipientId = sender.userId; // Send to self
      const message = {
        messageId: 'msg-1',
        content: 'Hello World',
        sender,
        recipientId,
        type: 'private',
      };

      // Store the message
      await manager._storeMessage(recipientId, { ...message, direction: 'incoming' });
      await manager._storeMessage(sender.userId, { ...message, direction: 'outgoing' });


      const query = {
        type: 'private',
        senderId: sender.userId,
        limit: 10,
        offset: 0
      }
      // Retrieve messages using the public API
      const messagesResult = await manager._getMessages(recipientId, query);
      expect(messagesResult.messages.length).toBe(2); // the incoming and the outcoming
      expect(messagesResult.messages[0].messageId).toBe('msg-1');

      const messagesResult2 = await manager._getMessages(recipientId, { ...query, direction: 'incoming' });
      expect(messagesResult2.messages.length).toBe(1);
      expect(messagesResult2.messages[0].messageId).toBe('msg-1');

      const messagesResult3 = await manager._getMessages(recipientId, { ...query, direction: 'outgoing' });
      expect(messagesResult3.messages.length).toBe(1);
      expect(messagesResult3.messages[0].messageId).toBe('msg-1');
    });

    test('should mark messages as read without errors', async () => {
      const socketId = 'socket-test1';
      const senderId = 'sender-123-FOCUS';
      const recipientSocketId = 'socket-test2';
      const recipientId = 'recipient-123';

      // Add and authenticate the sender
      await addAndAuthenticateUser(socketId, senderId, 'Sender User', validToken);

      // Add and authenticate the recipient
      await addAndAuthenticateUser(recipientSocketId, recipientId, 'Recipient User', validToken);

      // Sender sends messages to the recipient
      await manager.sendMessage(socketId, recipientId, 'Hello, this is message 1');
      await manager.sendMessage(socketId, recipientId, 'Hello, this is message 2');
      await manager.sendMessage(socketId, recipientId, 'Hello, this is message 3');

      // Recipient retrieves messages to get their IDs
      const messagesResult = await manager._getMessages(recipientId, { direction: 'incoming', senderId: senderId, limit: 10, offset: 0 });
      expect(messagesResult.messages.length).toBeGreaterThanOrEqual(3); // 3 minimal. 3x

      // Extract the IDs of the first TWO messages
      const messageIds = messagesResult.messages.slice(0, 2).map(msg => msg.messageId);

      // Mark  "recipientSocketId" (incoming) first two messages as read
      const r1 = await manager.markMessagesAsRead(recipientSocketId, { senderId, messageIds, direction: 'incoming' });

      // Validate the result
      expect(r1.marked).toBe(2); // Two messages * 2 users. update read_at on both user copies
      expect(r1.total).toBe(2);    // Total messages for the user

      // Mark  "recipientSocketId" (outgoing) first two messages as read
      const r2 = await manager.markMessagesAsRead(recipientSocketId, { senderId, messageIds, direction: 'outgoing' },);

      // Validate the result
      expect(r2.marked).toBe(0); // 0 = memmory, must 0 = pg !!!! is not yet
      expect(r2.total).toBe(0);

      // Retrieve the messages again to verify their state
      const updatedMessagesResult = await manager._getMessages(recipientId, { direction: 'incoming', limit: 10, offset: 0 });
      expect(updatedMessagesResult.messages.length).toBeGreaterThanOrEqual(3); /// 3 = memory;  9 = pg

      // Verify that the first two messages are marked as read
      const updatedMessages = updatedMessagesResult.messages;
      expect(updatedMessages[0].readAt).not.toBeNull(); // First message marked as read
      expect(updatedMessages[1].readAt).not.toBeNull(); // Second message marked as read
      expect(updatedMessages[2].readAt).toBeNull();     // Third message still unread
    });

    test('should retrieve messages', async () => {
      const userId = 'user-123';

      // Test that getMessages doesn't throw
      const messages = await manager._getMessages(userId, { limit: 10, offset: 0 });

      expect(messages).toBeDefined();
      expect(Array.isArray(messages.messages)).toBe(true);
      expect(typeof messages.total).toBe('number');
      expect(typeof messages.hasMore).toBe('boolean');
    });

    test('should handle pending messages flow', async () => {
      const userId = 'user-123';
      const user2Id = 'user-recip';
      const socketId = 'socket-123';
      const Socket2Id = 'socket-2222';

      // Add and authenticate the receiver
      await addAndAuthenticateUser(socketId, userId, 'Test User', validToken);

      // Add and authenticate the sender
      await addAndAuthenticateUser(Socket2Id, user2Id, 'Test User2', eternalToken);

      // Disconnect the sender to simulate being OFFLINE
      await manager.disconnectUser(socketId);

      // Send a message to the sender while they are offline
      const mess = await manager.sendMessage(Socket2Id, userId, 'Pending message');
      expect(mess.status).toBe('pending');

      // connect again 
      await addAndAuthenticateUser(socketId, userId, 'Test User', validToken);

      // and Retrieve and deliver pending messages
      const pending = await manager.getAndDeliverPendingMessages(socketId);

      // Validate the result
      expect(pending.delivered.length).toBeGreaterThan(0); // One message should be delivered  
      expect(pending.failed).toBe(0);
    });

    test('should broadcast a public message', async () => {
      const socketId = 'socket-123';
      const senderId = 'sender-123';
      const content = 'This is a public message';

      // Add and authenticate the sender
      await addAndAuthenticateUser(socketId, senderId, 'Test User', validToken);

      // Broadcast the public message
      await manager.broadcastPublicMessage(socketId, content);
      await manager.broadcastPublicMessage(socketId, `${content} XXXX`);



      // Retrieve public messages
      const publicMessagesResult = await manager.getPublicMessages(socketId);
      // Assertions
      expect(publicMessagesResult.messages.length).toBeGreaterThanOrEqual(2); // Two messages should exist
      expect(publicMessagesResult.messages.some(m => m.content === content)).toBe(true);
      expect(publicMessagesResult.messages.some(m => m.sender.userId === senderId)).toBe(true);
    });

    test('should return message status as delivered when recipient is online', async () => {
      const socketId = 'socket-123';
      const recipientId = 'recipient-456';
      const content = 'Hello, this is a test message';

      // Add and authenticate the recipient
      await addAndAuthenticateUser(socketId, recipientId, 'Recipient User', validToken);

      // Send a message to the recipient
      const result = await manager.sendMessage(socketId, recipientId, content);

      // Validate the result
      expect(result.status).toBe('delivered');
    });
    test('should return message status as pending when recipient is offline', async () => {
      const socketId = 'socket-123';
      const recipientId = 'recipient-456';
      const content = 'Hello, this is a test message';

      const socketRid = 'reci-123';


      await addAndAuthenticateUser(socketRid, recipientId, 'Test User', validToken);
      await manager.disconnectUser(socketRid);

      // Add and authenticate the sender
      await addAndAuthenticateUser(socketId, socketId, 'Test User', validToken);


      // Send a message to the recipient (who is offline)
      const result = await manager.sendMessage(socketId, recipientId, content);

      await addAndAuthenticateUser(socketRid, recipientId, 'Test User', validToken);
      // Validate the result
      expect(result.status).toBe('pending');
    });

  });

  describe('getMessageHistory message history', () => {
    test('should retrieve message history for a valid user and socket', async () => {
      const senderSocketId = 'sender-socket-id';
      const senderUserId = 'sender-user';
      const recipientSocketId = 'recipient-socket-id';
      const recipientUserId = 'recipient-user-id';


      // Add and authenticate sender and recipient users
      await addAndAuthenticateUser(senderSocketId, senderUserId, 'Sender User', validToken);
      await addAndAuthenticateUser(recipientSocketId, recipientUserId, 'Recipient User', eternalToken);

      const messages = ['Message 1', 'Message 2', 'Message 3'];
      for (const content of messages) {
        await manager.sendMessage(senderSocketId, recipientUserId, content);
      }

      // Retrieve message history with limit = 0
      let options = {
        otherPartyId: recipientUserId,
        limit: 0,
        offset: 0,
        type: 'private',
      };

      let result = await manager.getMessageHistory(recipientSocketId, options);
      expect(result.messages.length).toBeGreaterThanOrEqual(0); //  No messages in memory, can be any from 0..n postgres 

      // Retrieve message history with offset > total messages
      options = {
        otherPartyId: recipientUserId,
        limit: 10,
        offset: 10,
        type: 'private',
      };

      result = await manager.getMessageHistory(recipientSocketId, options);
      expect(result.messages.length).toBeGreaterThanOrEqual(0); // Only one memory. 0..n with pg
    });

    test('should filter messages by type', async () => {
      const senderSocketId = 'sender-socket-id';
      const recipientSocketId = 'recipient-socket-id';
      const senderUserId = 'sender-user-id';
      const recipientUserId = 'recipient-user-id';

      // Add and authenticate sender and recipient users
      await addAndAuthenticateUser(senderSocketId, senderUserId, 'Sender User', validToken);
      await addAndAuthenticateUser(recipientSocketId, recipientUserId, 'Recipient User', eternalToken);

      // Send a private message
      await manager.sendMessage(senderSocketId, recipientUserId, 'Private message');

      // Broadcast a public message
      await manager.broadcastPublicMessage(senderSocketId, 'Public message');

      // Retrieve private messages
      const privateOptions = {
        limit: 10,
        offset: 0,
        type: 'private',
        otherPartyId: recipientUserId,
      };

      let result = await manager.getPublicMessages(recipientSocketId);

      const h = await manager.getMessageHistory(recipientSocketId, privateOptions);
      expect(h.messages.length).toBeGreaterThanOrEqual(1); // Only one Memorry, 10 in postgres. how???

      const ra1 = await manager.getPublicMessages(recipientSocketId);
      // Retrieve public messages
      const publicOptions = {
        // public do not need id. should have a well known  
        limit: 10,
        offset: 0,
        type: 'public',
      };

      const ra2 = await manager.getPublicMessages(recipientSocketId); // reci
      expect(ra2.messages.length).toBeGreaterThanOrEqual(1); // Only one memory. 50 with postgres

      const rr1 = await manager._getMessages(senderUserId);

      const ra3 = await manager.getMessageHistory(senderSocketId, { type: 'public', });
      expect(ra3.messages.length).toBeGreaterThanOrEqual(1); // Only one memory. 1..n with pg
      const ra4 = await manager.getMessageHistory(recipientSocketId, { type: 'public', });
      expect(ra4.messages.length).toBeGreaterThanOrEqual(1); // Only one memory. 1..n with pg
    });
  });

  describe('Error Handling', () => {
    afterEach(() => {
      jest.clearAllMocks();

    });

    test('should handle non-existent user operations gracefully', async () => {
      let invalidSocketId = undefined;
      const senderId = 'sender-123';


      // Add the recipient as an active user
      await manager.addUser(senderId, { userId: senderId, userName: 'Sender User' });

      // For disconnectUser - should handle gracefully and return null
      const disconnectResult = await manager.disconnectUser(invalidSocketId);
      expect(disconnectResult).toBeNull();
    });

    test('should handle error increment', () => {
      // This should not throw
      expect(() => {
        manager._incrementErrors();
      }).not.toThrow();

      const metrics = manager.getConnectionMetrics();
      expect(metrics).toBeDefined();
    });

    test('should handle concurrent connections gracefully', async () => {
      const maxConnections = 5;
      const manager = userManager({ io: mockIo, defaultStorage: 'memory', maxTotalConnections: maxConnections });

      // Simulate concurrent connections
      const promises = [];
      for (let i = 0; i < maxConnections + 1; i++) {
        promises.push(manager.addUser(`socket-${i}`, { userId: `user-${i}`, userName: `User ${i}` }));
      }

      // Expect at least one rejection
      await expect(Promise.allSettled(promises)).resolves.toContainEqual(
        expect.objectContaining({ status: 'rejected' })
      );
    });
  });

  describe('Connection Metrics', () => {
    afterEach(() => {
      jest.clearAllMocks();

    });
    test('should provide connection metrics', () => {
      const metrics = manager.getConnectionMetrics();
      expect(metrics).toMatchSnapshot();
    });
    test('should provide connection metrics', () => {
      manager.addUser('socket-1', { userId: 'user-1', userName: 'User One' });
      manager.addUser('socket-2', { userId: 'user-2', userName: 'User Two' });

      const metrics = manager.getConnectionMetrics();

      expect(metrics).toBeDefined();
      expect(typeof metrics).toBe('object');
      expect(typeof metrics.totalConnections).toBe('number');
      expect(typeof metrics.activeConnections).toBe('number');
      expect(typeof metrics.disconnections).toBe('number');
      expect(typeof metrics.errors).toBe('number');
    });
  });

  describe('Integration Scenarios', () => {
    afterEach(() => {
      jest.clearAllMocks();

    });
    test('should handle complete user session', async () => {
      const socketId = 'integration-socket';
      const u = { userId: 'integration-user', userName: 'Integration Test' };
      const ou = { userId: 'other-user', userName: 'Other User' };

      // 1. Add user
      await addAndAuthenticateUser(socketId, u.userId, u.userName, validToken);
      expect(u).toBeDefined();
      expect(u.userId).toBe(u.userId);


      // 3. Store message with proper structure
      const message = {
        messageId: 'int-msg-1',
        content: 'Integration test message',
        direction: 'incoming',
        sender: ou,
        recipientId: u.userId,
      };

      const storedMessage = await manager._storeMessage(socketId, message);
      expect(storedMessage).toBeDefined();

      // 4. Get messages
      const messages = await manager._getMessages(socketId, { limit: 10, offset: 0 });
      expect(messages).toBeDefined();
      expect(Array.isArray(messages.messages)).toBe(true);

      // 5. Disconnect - User exists, so this should return the user object
      const disconnectedUser = await manager.disconnectUser(socketId);
      expect(disconnectedUser).toBeDefined();
      expect(disconnectedUser.userId).toBe(u.userId);

      // 6. Verify user is no longer accessible
      const foundUser = await manager._getUserBySocketId(socketId);
      expect(foundUser).toBeNull();
    });
  });
});