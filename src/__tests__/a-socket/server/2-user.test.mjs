import axios from 'axios';
import { startServer, stopServer, users as userManager } from 'a-socket/server.mjs';
import { INACTIVITY_THRESHOLD } from 'a-socket/config.mjs';
import { createClientSocket, waitForEvent } from '../utils.mjs';

const PORT = process.env.PORT || 3001;
const BASE_URL = `http://localhost:${PORT}`;

const SERVER_START_TIMEOUT = 10000; // < seconds
const HTTP_TEST_TIMEOUT = 200; // <1 second for HTTP tests
const SOCKET_TEST_TIMEOUT = 5000; // <5 seconds for socket tests
const SEND_MESSAGE_TIMEOUT = 6000;


jest.setTimeout(10000); // Set global timeout



let httpServer;

beforeAll(async () => {
  // Start the server
  httpServer = await startServer();

  // Small delay to ensure server is fully ready
  await new Promise(resolve => setTimeout(resolve, 500));
}, SERVER_START_TIMEOUT);

afterAll(async () => {
  // Stop server
  await stopServer();

  // Close the HTTP server explicitly
  if (httpServer) {
    await new Promise((resolve) => httpServer.close(resolve));
  }
});



describe('Socket.IO Server Tests', () => {
  let clientSocket, clientUser;
  beforeEach(async () => {
    // Connect client for each test
    clientSocket = await createClientSocket(BASE_URL);
    clientUser = await userManager.storeUser('client-socket', {
      userId: 'client',
      userName: 'Client',
    }, true);
  });

  afterEach(async () => {
    // Clean up client after each test
    if (clientSocket) {
      userManager.disconnectUser(clientSocket.id);
      clientSocket.disconnect();
      clientSocket.close();
    }

  });
  describe('HTTP Server', () => {
    test('should respond to health check', async () => {
      const response = await axios.get(`${BASE_URL}/health`);
      expect(response.status).toBe(200);
      expect(response.data).toMatchObject({
        status: 'ok',
        message: 'Server is running',
      });
    }, HTTP_TEST_TIMEOUT);

    test('should handle CORS', async () => {
      const response = await axios.get(`${BASE_URL}/health`, {
        headers: { origin: 'http://localhost:3000' },
      });
      expect(response.headers['access-control-allow-origin']).toBe('http://localhost:3000');
    }, HTTP_TEST_TIMEOUT);

    test('should return 404 for unknown routes', async () => {
      try {
        await axios.get(`${BASE_URL}/unknown-route`);
      } catch (error) {
        expect(error.response.status).toBe(404);
        expect(error.response.data).toMatchObject({ error: 'Not Found' });
      }
    }, HTTP_TEST_TIMEOUT);
  });

  test('should connect and disconnect a socket', async () => {
    expect(clientSocket.connected).toBe(true);

    const disconnectPromise = new Promise((resolve) => clientSocket.on('disconnect', resolve));
    clientSocket.disconnect();
    await disconnectPromise;

    expect(clientSocket.connected).toBe(false);
  }, SOCKET_TEST_TIMEOUT);


  describe('UserManager Tests', () => {
    let testUserId;
    const testUserData = {
      userId: 'test-user-id',
      userName: 'Test User',
    };

    test('should add a connected user successfully', async () => {
      const user = await userManager.storeUser('test-socket-id', testUserData);
      testUserId = user.userId; // Store the userId for subsequent tests

      expect(user).toMatchObject({
        userId: testUserData.userId,
        userName: testUserData.userName,
        sockets: [
          {
            socketId: 'test-socket-id',
            sessionId: expect.any(String), // Validate sessionId is a string
            connectedAt: expect.any(Number), // Validate connectedAt is a number
            state: 'connected', // Validate the initial state
          },
        ],
        connectedAt: expect.any(Number),
        lastActivity: expect.any(Number),
        state: 'connected',
      });
    }, SOCKET_TEST_TIMEOUT);

    test('should retrieve the stored user', async () => {
      const user = await userManager.getUserBySocketId('test-socket-id');
      expect(user).toMatchObject({
        userId: testUserData.userId,
        userName: testUserData.userName,
        sockets: [
          {
            socketId: 'test-socket-id',
            sessionId: expect.any(String),
            connectedAt: expect.any(Number),
            state: 'connected',
          },
        ],
      });
    }, SOCKET_TEST_TIMEOUT);

    test('should add a authenticated user successfully', async () => {
      await userManager.disconnectUser('test-socket-id');
      const user = await userManager.storeUser('test-socket-id2', testUserData, true);
      testUserId = user.userId; // Store the userId for subsequent tests

      expect(user).toMatchObject({
        userId: testUserData.userId,
        userName: testUserData.userName,
        sockets: [
          {
            socketId: 'test-socket-id2',
            sessionId: expect.any(String), // Validate sessionId is a string
            connectedAt: expect.any(Number), // Validate connectedAt is a number
            state: 'authenticated', // Validate the initial state
          },
        ],
        connectedAt: expect.any(Number),
        lastActivity: expect.any(Number),
        state: 'authenticated',
      });
    }, SOCKET_TEST_TIMEOUT);

    test('should retrieve the stored user', async () => {
      const user = await userManager.getUserBySocketId('test-socket-id2');
      expect(user).toMatchObject({
        userId: testUserData.userId,
        userName: testUserData.userName,
        sockets: [
          {
            socketId: 'test-socket-id2',
            sessionId: expect.any(String),
            connectedAt: expect.any(Number),
            state: 'authenticated',
          },
        ],
      });
    }, SOCKET_TEST_TIMEOUT);

    test('should update the user state', async () => {
      const updatedUser = await userManager.updateUserState(testUserId, 'authenticated');
      expect(updatedUser.state).toBe('authenticated');
    }, SOCKET_TEST_TIMEOUT);


    test('should throw an error for invalid user data', async () => {
      await expect(userManager.storeUser('test-socket-id', {})).rejects.toThrow('Error storing user for socket test-socket-id: Invalid user session  \"userId\" must be a string');
    }, SOCKET_TEST_TIMEOUT);

    test('should transition inactive users to offline', async () => {
      const user = await userManager.storeUser('test-socket-id', {
        userId: 'inactive-user',
        userName: 'Inactive User',
      }, true);

      await userManager._checkInactivity();
      const u4 = await userManager.getUsersList('test-socket-id')


      // Simulate inactivity by setting lastActivity to a past timestamp
      const inactiveTime = Date.now() - (INACTIVITY_THRESHOLD * 2 + 1000); // Exceeds threshold
      user.lastActivity = inactiveTime;
      const user2 = await userManager.storeUser('test-socket-id', user);  // CAN DEBUG storeUser.... this line when i F11, it does not drill down. even so results value

      // Run the inactivity check. will be some as  const ud = await userManager.disconnectUser('test-socket-id');  expect(ud.state).toBe('offline');
      await userManager._checkInactivity();

      // authenticate use to observe other party conn state
      const otherP = await userManager.storeUser('test-socket-id2', testUserData, true);
      expect(otherP.state).toBe('authenticated');
      const userObsOtherP = await userManager.getUsersList('test-socket-id2');
      expect(userObsOtherP.some(u =>
        u.userId === 'inactive-user' &&
        u.state === 'offline'
      )).toBe(true);

      // for disconnected user. can get socketId.
      const updatedUser = await userManager.getUserBySocketId('test-socket-id');
      expect(updatedUser).toBeNull();
    }, SOCKET_TEST_TIMEOUT * 2);
  });


});