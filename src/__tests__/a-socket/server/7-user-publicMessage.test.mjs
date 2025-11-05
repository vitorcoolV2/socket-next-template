import { startServer, stopServer, users as userManager } from 'a-socket/server.mjs';
import { createClientSocket } from '../utils.mjs';

const PORT = process.env.PORT || 3001; // Use a different port to avoid conflicts
const BASE_URL = `http://localhost:${PORT}`;

const SERVER_START_TIMEOUT = 10000; // Increased timeout for server startup

const SOCKET_TEST_TIMEOUT = 5000;

jest.setTimeout(10000); // Increase global timeout

let httpServer, clientSocket;

beforeAll(async () => {
  // Start the server
  httpServer = await startServer();

  // Small delay to ensure server is fully ready
  await new Promise(resolve => setTimeout(resolve, 500));
}, SERVER_START_TIMEOUT);

afterAll(async () => {
  // Stop the server
  await stopServer();

  if (httpServer) {
    await new Promise((resolve) => httpServer.close(resolve));
  }
});

beforeEach(async () => {
  // Connect client for each test
  clientSocket = await createClientSocket(BASE_URL);
});

afterEach(async () => {
  // Clean up client after each test
  if (clientSocket) {
    clientSocket.disconnect();
    clientSocket.close();
  }
});

describe('Socket.IO Server Tests', () => {
  let senderSocket, otherSocket;
  let senderUser;

  beforeEach(async () => {
    // Create and connect sockets
    senderSocket = await createClientSocket(BASE_URL);
    senderUser = await userManager.storeUser(senderSocket.id, {
      userId: 'sender',
      userName: 'Sender',
    }, true);

    otherSocket = await createClientSocket(BASE_URL);
    otherUser = await userManager.storeUser(otherSocket.id, {
      userId: 'other',
      userName: 'Other',
    }, true);
  });

  afterEach(async () => {
    // Disconnect and clean up sockets
    if (senderSocket) {
      userManager.disconnectUser(senderSocket.id);
      senderSocket.disconnect();
      senderSocket.close();
    }
    if (otherSocket) {
      userManager.disconnectUser(otherSocket.id);
      otherSocket.disconnect();
      otherSocket.close();
    }
  });

  describe('Messaging', () => {

    const messageContent = 'Hello, world! checking in';

    describe('Public Messages', () => {
      test('should broadcast public message', async () => {
        // Replace sendMessage with broadcastPublicMessage
        const sentMessage = await userManager.broadcastPublicMessage(senderSocket.id, messageContent);
        /*
                const receivedMessage = await new Promise((resolve) => {
                  otherSocket.on('public_message', (msg) => resolve(msg)); // Listen for public_message instead of private_message
                });
        
                expect(receivedMessage).toMatchObject({
                  content: messageContent,
                  sender: { userId: 'sender', userName: 'Sender' },
                });*/

        // Validate the sent message
        expect(sentMessage).toBeDefined();
        expect(sentMessage.messageId).toBeDefined();
        expect(sentMessage.status).toBe('sent');
        expect(sentMessage.createdAt).toBeDefined();
      }, SOCKET_TEST_TIMEOUT);


      test('should fetch public messages', async () => {

        // Fetch public messages
        const publicMessages1 = await userManager.getPublicMessages(senderSocket.id);
        const publicMessages2 = await userManager.getPublicMessages(otherSocket.id);


        expect(publicMessages2).toBeDefined();
        expect(publicMessages2.messages.length).toBeGreaterThanOrEqual(1);
        expect(publicMessages2.messages.some(msg => msg.content === messageContent && msg.sender.userId === senderUser.userId)).toBe(true);

        // Validate the fetched messages
        expect(publicMessages1).toBeDefined();
        expect(publicMessages1.messages.length).toBeGreaterThanOrEqual(1);
        expect(publicMessages1.messages.some(msg => msg.content === messageContent && msg.sender.userId === senderUser.userId)).toBe(true);
      }, SOCKET_TEST_TIMEOUT * 2);
    });


  });
});