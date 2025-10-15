import { jest, describe, expect, test } from '@jest/globals';
import { userManager } from '../../../socket.io/userManager/index.mjs';

const validToken = MOCK_TOKENS.validUser;
const eternalToken = MOCK_TOKENS.eternalUser;

describe('User Manager - markMessagesAsRead', () => {
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

  afterEach(async () => {
    jest.clearAllMocks();
    await manager.__resetData(); // Reset data to avoid side effects
  });

  const addAndAuthenticateUser = async (socketId, userId, userName, token) => {
    await manager.addUser(socketId, { userId, userName });
    const socket = { id: socketId, handshake: { auth: { token } } };
    const next = jest.fn();
    await mockIo.invokeMiddleware(socket, next);
    expect(next).toHaveBeenCalledWith();
    const user = await manager._getUserBySocketId(socketId);
    expect(user).toBeDefined();
    expect(user.state).toBe('authenticated');
    return user;
  };

  describe('Scenario: Marking Messages as Read', () => {
    const senderSocketId = 'sender-socket-id';
    const recipientSocketId = 'recipient-socket-id';
    const senderUserId = 'sender-user-id';
    const recipientUserId = 'recipient-user-id';

    beforeEach(async () => {
      await addAndAuthenticateUser(senderSocketId, senderUserId, 'Sender User', validToken);
      await addAndAuthenticateUser(recipientSocketId, recipientUserId, 'Recipient User', eternalToken);
      await manager.sendMessage(senderSocketId, recipientUserId, 'Hello, this is a test message!');
    });

    afterEach(async () => {
      await manager.disconnectUser(senderSocketId);
      await manager.disconnectUser(recipientSocketId);
    });

    describe('Step 1: Basic Functionality', () => {
      test('should mark all unread messages as read', async () => {
        const result = await manager.markMessagesAsRead(recipientSocketId, { senderId: senderUserId });
        expect(result.marked).toBeGreaterThanOrEqual(1);
        expect(result.total).toBeGreaterThanOrEqual(1);
      });
    });

    describe('Step 2: Filter by Sender ID', () => {
      test('should mark unread messages only from a specific sender', async () => {
        const result = await manager.markMessagesAsRead(recipientSocketId, { senderId: senderUserId });
        expect(result.marked).toBe(1);
        expect(result.total).toBe(1);
      });
    });

    describe('Step 3: Filter by Message IDs', () => {
      test('should mark specific unread messages by their IDs', async () => {
        await manager.sendMessage(senderSocketId, recipientUserId, 'Hello, this is a test message>>>!');
        const options = { otherPartyId: recipientUserId, unreadOnly: true, limit: 10, offset: 0, type: 'private' };
        const messages = await manager._getMessages(recipientUserId, options);
        const messageId = messages.messages[0].messageId;
        const result = await manager.markMessagesAsRead(recipientSocketId, { messageIds: [messageId] });
        expect(result.marked).toBe(1);
        expect(result.total).toBe(1);
      });
    });

    describe('Step 4: Invalid Input', () => {
      test('should reject required options', async () => {
        await expect(manager.markMessagesAsRead(recipientSocketId)).rejects.toThrow(
          `Error marking messages as read for socketId: ${recipientSocketId}`
        );
      });
      test('should reject missing options property', async () => {
        await expect(manager.markMessagesAsRead(recipientSocketId, {})).rejects.toThrow(
          `Error marking messages as read for socketId: ${recipientSocketId}`
        );
      });

    });

    describe('Step 5: No Unread Messages', () => {
      test('should return zero marked messages when no unread messages exist', async () => {
        await manager.markMessagesAsRead(recipientSocketId, { senderId: senderUserId });
        const result = await manager.markMessagesAsRead(recipientSocketId, { senderId: senderUserId });
        expect(result.marked).toBe(0);
        expect(result.total).toBe(0);
      });
    });

    describe('Step 6: Large Datasets', () => {
      test('should handle marking messages for a user with many unread messages', async () => {
        for (let i = 0; i < 10; i++) {
          await manager.sendMessage(senderSocketId, recipientUserId, `Test message ${i}`);
        }
        const result = await manager.markMessagesAsRead(recipientSocketId, { senderId: senderUserId });
        expect(result.marked).toBe(11);
        expect(result.total).toBe(11);
      });
    });

    describe('Step 7: Persistence Layer Integration', () => {
      test('should call the persistence layer with the correct message IDs', async () => {
        // Spy on the persistence layer's markMessagesAsRead method
        const spy = jest.spyOn(manager._persistenceHooks, 'markMessagesAsRead');

        // Call the markMessagesAsRead function
        const result = await manager.markMessagesAsRead(recipientSocketId, { senderId: senderUserId });

        // Assertions
        expect(result.marked).toBe(1); // Ensure one message was marked as read
        expect(result.total).toBe(1); // Ensure there was one total message

        // Verify that the persistence layer was called with the correct message IDs
        expect(spy).toHaveBeenCalledWith(
          expect.any(String), // recipientId
          expect.objectContaining({
            direction: "incoming", // Validate the direction property
            messageIds: expect.arrayContaining([expect.any(String)]) // Validate the messageIds array
          })
        );
      });
    });
  });
});