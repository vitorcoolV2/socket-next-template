import { userManager } from '../../../socket.io/userManager/index.mjs';

const validToken = MOCK_TOKENS.validUser;
const eternalToken = MOCK_TOKENS.eternalUser;

describe('User Manager - Get Users', () => {
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
    if (!user) {
      throw new Error(`Failed to add or authenticate user with socketId: ${socketId}`);
    }
    console.log(`Added user: ${JSON.stringify(user)}`); // Log the user object
    expect(user.state).toBe('authenticated');

    return user; // Return the user object
  };

  describe('Scenario: Get Users Interaction', () => {
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
      try {
        // Disconnect the sender user
        const resp1 = await manager.disconnectUser(senderSocketId);
        if (resp1) {
          expect(resp1.state).toBe('offline'); // Validate the sender's state
          expect(resp1.sockets.length).toBe(0); // Validate that no sockets remain
        } else {
          console.warn(`Failed to disconnect user with socketId: ${senderSocketId}`);
        }

        // Disconnect the recipient user
        const resp2 = await manager.disconnectUser(recipientSocketId);
        if (resp2) {
          expect(resp2.state).toBe('offline'); // Validate the recipient's state
          expect(resp2.sockets.length).toBe(0); // Validate that no sockets remain
        } else {
          console.warn(`Failed to disconnect user with socketId: ${recipientSocketId}`);
        }
      } catch (error) {
        console.error('Error during cleanup:', error.message);
      }
    });

    describe('Step 1: Retrieve All Users', () => {
      test('should retrieve all authenticated users', async () => {
        // Call getUsers with no filters
        const result = await manager.getUsers(senderSocketId);

        // Validate the result
        expect(result).toBeDefined();
        expect(Array.isArray(result)).toBe(true);
        expect(result.length).toBe(2); // Expect both sender and recipient users

        // Validate each user in the result
        const userMap = result.reduce((map, user) => {
          map[user.userId] = user;
          return map;
        }, {});

        expect(userMap[senderUserId]).toBeDefined();
        expect(userMap[senderUserId].userName).toBe('Sender User');
        expect(userMap[senderUserId].state).toBe('authenticated');

        expect(userMap[recipientUserId]).toBeDefined();
        expect(userMap[recipientUserId].userName).toBe('Recipient User');
        expect(userMap[recipientUserId].state).toBe('authenticated');
      });
    });

    describe('Step 2: Filter by State', () => {
      test('should filter users by their connection state', async () => {
        // Disconnect the recipient user
        const resp = await manager.disconnectUser(recipientSocketId);
        if (!resp) {
          throw new Error(`Failed to disconnect user with socketId: ${recipientSocketId}`);
        }
        expect(resp.state).toBe('offline');

        // Call getUsers with a filter for "authenticated" users
        const result = await manager.getUsers(senderSocketId, { state: 'authenticated' });

        // Validate the result
        expect(result).toBeDefined();
        expect(Array.isArray(result)).toBe(true);
        expect(result.length).toBe(1); // Only the sender should be authenticated

        // Validate the remaining user
        expect(result[0].userId).toBe(senderUserId);
        expect(result[0].userName).toBe('Sender User');
        expect(result[0].state).toBe('authenticated');
      });
    });

    describe('Step 3: Include Offline Users', () => {
      test('should include offline users when requested', async () => {
        // Disconnect the recipient user
        const resp = await manager.disconnectUser(recipientSocketId);
        if (!resp) {
          throw new Error(`Failed to disconnect user with socketId: ${recipientSocketId}`);
        }
        expect(resp.state).toBe('offline');

        // Call getUsers with includeOffline set to true
        const result = await manager.getUsers(senderSocketId, { includeOffline: true });

        // Validate the result
        expect(result).toBeDefined();
        expect(Array.isArray(result)).toBe(true);
        expect(result.length).toBe(2); // Both users should be included

        // Validate each user in the result
        const userMap = result.reduce((map, user) => {
          map[user.userId] = user;
          return map;
        }, {});

        expect(userMap[senderUserId]).toBeDefined();
        expect(userMap[senderUserId].userName).toBe('Sender User');
        expect(userMap[senderUserId].state).toBe('authenticated');

        expect(userMap[recipientUserId]).toBeDefined();
        expect(userMap[recipientUserId].userName).toBe('Recipient User');
        expect(userMap[recipientUserId].state).toBe('offline');
      });
    });

    describe('Step 4: Pagination', () => {
      test('should apply pagination limits and offsets', async () => {
        // Call getUsers with pagination options
        const result = await manager.getUsers(senderSocketId, { limit: 1, offset: 1 });

        // Validate the result
        expect(result).toBeDefined();
        expect(Array.isArray(result)).toBe(true);
        expect(result.length).toBe(1); // Only one user should be returned

        // Validate the returned user
        expect(result[0].userId).toBe(recipientUserId);
        expect(result[0].userName).toBe('Recipient User');
        expect(result[0].state).toBe('authenticated');
      });
    });

    describe('Step 5: Invalid Options', () => {
      test('should reject invalid or missing options', async () => {
        // Simulate sending invalid data
        await expect(
          manager.getUsers(senderSocketId, { limit: -1 })
        ).rejects.toThrow(`Error getting users for socketId: ${senderSocketId}`);

        // Simulate sending missing data
        await expect(
          manager.getUsers(senderSocketId, null)
        ).rejects.toThrow(`Error getting users for socketId: ${senderSocketId}`);
        //).rejects.toThrow('Invalid options:');
      });
    });
  });
});