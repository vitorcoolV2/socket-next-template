import { jest } from '@jest/globals';
import { Server } from 'socket.io';


// Load tokens dynamically if necessary
const invalidToken = MOCK_TOKENS.expiredUser;
const validToken = MOCK_TOKENS.validUser;
const eternalToken = MOCK_TOKENS.eternalUser;



// Import after mocking

import { userManager as actualUserManager } from '../../../socket.io/userManager/index.mjs'; // Alias to avoid conflicts


describe('User Manager Tests', () => {
  let mockIo;
  let users;

  beforeEach(() => {
    jest.clearAllMocks();
    mockIo = new Server();
    users = actualUserManager({ io: mockIo }); // Use the aliased userManager
  });

  afterEach(() => {
    if (mockIo && mockIo.close) {
      mockIo.close();
    }
  });

  // Basic Initialization Tests
  test('should initialize userManager with a mock server', () => {
    expect(users).toBeDefined();
    expect(mockIo.use).toHaveBeenCalled();
  });



  // Basic Initialization Tests
  test('should initialize userManager with a mock server', () => {
    expect(users).toBeDefined();
    expect(mockIo.use).toHaveBeenCalled();
  });

  // User Authentication Tests
  test('should authenticate a user', async () => {
    const mockSocketId = 'mock-socket-id';


    await users.addUser(mockSocketId, { userId: 'user-id', userName: 'the  name of user' })

    await users._authenticateUserWithToken(mockSocketId, validToken);

    const user = users._getUserBySocketId(mockSocketId);
    expect(user).toBeDefined();
    expect(user.state).toBe('authenticated');
  });

  test('should reject invalid tokens', async () => {
    const mockSocketId = 'mock-socket-id';

    await users.addUser(mockSocketId, { userId: 'user-id', userName: 'the  name of user' })

    await expect(users._authenticateUserWithToken(mockSocketId, invalidToken))
      .rejects.toThrow(`Error authenticating user for socket ${mockSocketId}`);
  });

  // User Management Tests
  test('should add a user', async () => {
    const mockSocketId = 'mock-socket-id';
    const userData = { userId: 'user1', userName: 'Test User' };

    const user = await users.addUser(mockSocketId, userData);
    expect(user).toBeDefined();
    expect(user.userId).toBe('user1');
    expect(user.userName).toBe('Test User');
    expect(user.state).toBe('connected');
  });

  test('should disconnect a user', async () => {
    const mockSocketId = 'mock-socket-id';
    const userData = { userId: 'user1', userName: 'Test User' };

    await users.addUser(mockSocketId, userData);
    const result = await users.disconnectUser(mockSocketId);

    expect(result).toBeDefined();
    expect(result.state).toBe('offline');
  });

  // Message Handling Tests
  test('should send a private message', async () => {
    const senderSocketId = 'sender-socket-id';
    const recipientSocketId = 'recipient-socket-id';

    // Add users
    await users.addUser(senderSocketId, { userId: 'user1', userName: 'Sender' });
    await users.addUser(recipientSocketId, { userId: 'user2', userName: 'Recipient' });

    // Authenticate users
    await users._authenticateUserWithToken(senderSocketId, validToken);
    await users._authenticateUserWithToken(recipientSocketId, eternalToken);

    // Send a message
    const result = await users.sendMessage(senderSocketId, 'user2', 'Hello, world!');
    expect(result).toMatchObject({
      status: 'delivered',
      content: 'Hello, world!',
    });
  });


  // Public Message Tests
  test('should broadcast a public message', async () => {
    const mockSocketId = 'mock-socket-id';
    const userData = { userId: 'user1', userName: 'Test User' };

    await users.addUser(mockSocketId, userData);
    await users._authenticateUserWithToken(mockSocketId, validToken);

    // Broadcast a public message
    const result = await users.broadcastPublicMessage(mockSocketId, 'This is a public message');
    expect(result).toBeDefined();
  });

  test('should retrieve public messages', async () => {
    const mockSocketId = 'mock-socket-id';
    const userData = { userId: 'user1', userName: 'Test User' };

    await users.addUser(mockSocketId, userData);
    await users._authenticateUserWithToken(mockSocketId, validToken);

    // Retrieve public messages
    const result = await users.getPublicMessages(mockSocketId);
    expect(result.messages.length).toBeGreaterThanOrEqual(0);
  });

  // Typing Indicator Tests
  test('should handle typing indicator', async () => {
    const senderSocketId = 'sender-socket-id';
    const recipientSocketId = 'recipient-socket-id';

    // Add users
    await users.addUser(senderSocketId, { userId: 'user1', userName: 'Sender' });
    await users.addUser(recipientSocketId, { userId: 'user2', userName: 'Recipient' });

    // Authenticate users
    await users._authenticateUserWithToken(senderSocketId, validToken);
    await users._authenticateUserWithToken(recipientSocketId, eternalToken);

    // Send typing indicator
    const data = { isTyping: true, recipientId: 'user2' };
    const result = await users.typingIndicator(senderSocketId, data);

    expect(result).toMatchObject({
      sender: 'user1',
      isTyping: true,
    });
  });

  // Metrics and Cleanup Tests
  test('should track connection metrics', () => {
    const metrics = users.getConnectionMetrics();
    expect(metrics).toMatchObject({
      totalConnections: 0,
      activeConnections: 0,
      disconnections: 0,
      errors: 0,
      activeUsers: 0,
    });
  });



  // Error Handling Tests
  test('should handle invalid operations gracefully', async () => {
    const mockSocketId = 'invalid-socket-id';

    await expect(users._failInsecureSocketId(mockSocketId))
      .rejects.toThrow(`Error securing socketId: ${mockSocketId}`);
  });
});