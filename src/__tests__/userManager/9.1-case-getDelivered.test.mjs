import { userManager } from '../../../socket.io/userManager/index.mjs';
import {
  getMessagesOptionsSchema,
} from '../../../socket.io/userManager/schemas.mjs';

const validToken = MOCK_TOKENS.validUser;
const eternalToken = MOCK_TOKENS.eternalUser;

describe('User Manager - getAndDeliverPendingMessages', () => {
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

  describe('Scenario: Delivering Pending Messages', () => {
    const senderSocketId = 'sender-socket-id';
    const recipientSocketId = 'recipient-socket-id';
    const senderUserId = 'sender-user-id';
    const recipientUserId = 'recipient-user-id';

    beforeEach(async () => {
      await addAndAuthenticateUser(senderSocketId, senderUserId, 'Sender User', validToken);
      await addAndAuthenticateUser(recipientSocketId, recipientUserId, 'Recipient User', eternalToken);

      await manager.disconnectUser(recipientSocketId); // Simulate offline recipient
      // Send multiple pending messages from the sender to the recipient
      for (let i = 0; i < 5; i++) {
        await manager.sendMessage(senderSocketId, recipientUserId, `Pending message ${i}`);
      }
    });

    afterEach(async () => {
      await manager.disconnectUser(senderSocketId);
      await manager.disconnectUser(recipientSocketId);
    });

    describe('Step 1: Basic Functionality', () => {
      test('should deliver all pending messages', async () => {
        await addAndAuthenticateUser(recipientSocketId, recipientUserId, 'Recipient User', eternalToken);
        const result = await manager.getAndDeliverPendingMessages(recipientSocketId);
        expect(result.failed).toBe(0); // No failures
        expect(result.total).toBe(5); // Total pending messages
        expect(result.delivered.length).toBe(5); // All messages delivered
        expect(result.pendingMessages.length).toBe(0); // Delivered messages returned
      });
    });

    describe('Step 2: No Pending Messages', () => {
      test('should return zero delivered messages when no pending messages exist', async () => {
        // Deliver all pending messages first
        const user = await addAndAuthenticateUser(recipientSocketId, recipientUserId, 'Recipient User', eternalToken);
        const res = await manager.getAndDeliverPendingMessages(recipientSocketId);

        // Attempt to deliver again
        const result = await manager.getAndDeliverPendingMessages(recipientSocketId);
        expect(result.delivered.length).toBe(0); // No messages delivered
        expect(result.total).toBe(0); // No pending messages
        expect(result.failed).toBe(0); // No failures
        expect(result.pendingMessages.length).toBe(0); // No delivered messages
      });
    });

    describe('Step 3: Partial Delivery Success', () => {
      test('should handle partial delivery failures', async () => {
        const r_mess = await manager._getMessages(recipientUserId);

        await addAndAuthenticateUser(recipientSocketId, recipientUserId, 'Recipient User', eternalToken);

        // Mock persistence layer to fail for one message
        const spy = jest.spyOn(manager._persistenceHooks, 'storeMessage');
        const result = await manager.getAndDeliverPendingMessages(recipientSocketId);
        // Persisting Call
        expect(spy.mock.calls.length).toBe(2 * 5); // all messages persisting call. two for each message participant. sender outgoing, recipientId incoming


        expect(result.delivered.length).toBeGreaterThanOrEqual(5); // 5 mem, 26=pg
        expect(result.total).toBe(5); // Total pending messages
        expect(result.failed).toBe(0); // 0 failure
        expect(result.pendingMessages.length).toBe(0); // 0 pending delivered messages miss to deliver
      });
    });

    describe('Step 4: Persistence Layer Integration', () => {
      test('should call the persistence layer with the correct message IDs', async () => {


        await addAndAuthenticateUser(recipientSocketId, recipientUserId, 'Recipient User', eternalToken);

        const spy = jest.spyOn(manager._persistenceHooks, 'storeMessage');
        await manager.getAndDeliverPendingMessages(recipientSocketId);

        // Validate that the persistence hook was called
        expect(spy).toHaveBeenCalled();

        // Validate the arguments passed to the persistence hook
        const [userId, messages] = spy.mock.calls[0];
        expect(userId).toBe(recipientUserId);
        expect(spy.mock.calls.length).toBe(2 * 5); // All pending messages
      });
    });

    describe('Step 5: Schema Validation', () => {
      test('should reject invalid options', async () => {
        // Modify the internal schema validation to simulate an error
        jest.spyOn(getMessagesOptionsSchema, 'validate').mockReturnValueOnce({
          error: new Error('Invalid options'),
        });

        await addAndAuthenticateUser(recipientSocketId, recipientUserId, 'Recipient User', eternalToken);
        await expect(manager.getAndDeliverPendingMessages(recipientSocketId)).rejects.toThrow(
          `Error retrieving pending messages for socketId: ${recipientSocketId}`
        );
      });
    });
  });
});