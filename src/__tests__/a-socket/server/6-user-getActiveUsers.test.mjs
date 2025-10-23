import { startServer, stopServer, users as userManager } from 'a-socket/server.mjs';
import { createClientSocket } from '../utils.mjs';


const PORT = process.env.PORT || 3001;
const BASE_URL = `http://localhost:${PORT}`;

const SERVER_START_TIMEOUT = 5000; // < seconds
const HTTP_TEST_TIMEOUT = 200; // <1 second for HTTP tests
const SOCKET_TEST_TIMEOUT = 5000; // <5 seconds for socket tests


jest.setTimeout(20000); // Increase global timeout

let httpServer;

beforeAll(async () => {
  // Start the server
  httpServer = await startServer();

  // Small delay to ensure server is fully ready
  await new Promise((resolve) => setTimeout(resolve, 500));
}, SERVER_START_TIMEOUT);

afterAll(async () => {
  // Stop the server
  await stopServer();

  if (httpServer) {
    await new Promise((resolve) => httpServer.close(resolve));
  }
});

describe('Socket.IO Server Tests', () => {
  let senderSocket, recipientSocket;

  beforeEach(async () => {
    // Create and connect sockets using the utility function
    senderSocket = await createClientSocket(BASE_URL);
    senderUser = await userManager.storeUser(senderSocket.id, {
      userId: 'sender',
      userName: 'Sender'
    }, true);

    recipientSocket = await createClientSocket(BASE_URL);
    recipientUser = await userManager.storeUser(recipientSocket.id, {
      userId: 'recipient',
      userName: 'Recipient'
    }, true);
  });

  afterEach(() => {
    // Disconnect and close sockets after each test
    if (senderSocket) {
      userManager.disconnectUser(senderSocket.id);
      senderSocket.disconnect();
      senderSocket.close();
    }
    if (recipientSocket) {
      userManager.disconnectUser(recipientSocket.id);
      recipientSocket.disconnect();
      recipientSocket.close();
    }
  });

  describe('Messaging', () => {
    describe('Private Messages', () => {
      test('should send and receive a private message', async () => {

        const messageContent = 'Hello, world!';
        const message = await userManager.sendMessage(senderSocket.id, 'recipient', messageContent);

        expect(message).toMatchObject({
          status: 'pending',
          content: messageContent,
          sender: { userId: 'sender', userName: 'Sender' },
          recipientId: 'recipient',
        });
      }, SOCKET_TEST_TIMEOUT);

      test('should retrieve active users after a private message', async () => {
        // Store users
        const u1 = await userManager.storeUser(senderSocket.id, { userId: 'sender', userName: 'Sender' }, true);
        const u2 = await userManager.storeUser(recipientSocket.id, { userId: 'recipient', userName: 'Recipient' }, true);

        // Send a private message
        const messageContent = 'Hello, world!';
        await userManager.sendMessage(senderSocket.id, 'recipient', messageContent);

        // Retrieve active users
        const activeUsers = await userManager.getActiveUsers(senderSocket.id, {});

        // Validate the response
        expect(activeUsers).toBeDefined();
        expect(activeUsers.length).toBeGreaterThanOrEqual(2); // Sender and Recipient should be active

        // Check if both users are present in the active users list
        const senderInActiveUsers = activeUsers.some(user => user.userId === 'sender');
        const recipientInActiveUsers = activeUsers.some(user => user.userId === 'recipient');

        expect(senderInActiveUsers).toBe(true);
        expect(recipientInActiveUsers).toBe(true);
      }, SOCKET_TEST_TIMEOUT);
    });
  });
});