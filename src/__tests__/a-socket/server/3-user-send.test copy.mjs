import { startServer, stopServer, users as userManager } from 'a-socket/server.mjs';
import { createClientSocket } from '../utils.mjs';

const PORT = process.env.PORT || 3001; // Use a different port to avoid conflicts
const BASE_URL = `http://localhost:${PORT}`;

const SERVER_START_TIMEOUT = 10000; // Increased timeout for server startup
const HTTP_TEST_TIMEOUT = 200;
const SOCKET_TEST_TIMEOUT = 15000;



jest.setTimeout(20000); // Increase global timeout

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
  let senderSocket, recipientSocket;
  let senderUser, recipientUser;

  beforeEach(async () => {
    // Create and connect sockets
    senderSocket = await createClientSocket(BASE_URL);
    recipientSocket = await createClientSocket(BASE_URL);

    senderUser = await userManager.storeUser(senderSocket.id, {
      userId: 'sender',
      userName: 'Sender',
    }, true);
    recipientUser = await userManager.storeUser(recipientSocket.id, {
      userId: 'recipient',
      userName: 'Recipient',
    }, true);

    // Pequeno atraso para garantir que ambos os sockets estão prontos
    await new Promise(resolve => setTimeout(resolve, 500));
  });

  afterEach(async () => {
    // Disconnect and clean up sockets

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
        const u1 = await userManager.storeUser(senderSocket.id, { userId: 'sender', userName: 'Sender' }, true);
        const u2 = await userManager.storeUser(recipientSocket.id, { userId: 'recipient', userName: 'Recipient' }, true);


        recipientSocket.on('receiveMessage', (msg) =>
          resolve(msg));
        const messageContent = 'Hello, world!';
        const sentMessage = await userManager.sendMessage(senderSocket.id, 'recipient', messageContent);



        expect(receivedMessage).toMatchObject({
          content: messageContent,
          sender: { userId: 'sender', userName: 'Sender' },
          recipientId: 'recipient',
        });

        expect(sentMessage).toBeDefined();
        expect(sentMessage.messageId).toBeDefined();
        expect(sentMessage.status).toBe('pending');

        //expect(sentMessage.status).toBe('delivered');
      }, SOCKET_TEST_TIMEOUT);

      test('should mark messages as read', async () => {
        // Send a private message
        const messageContent = 'Test message to mark as read';
        const sentMessage = await userManager.sendMessage(senderSocket.id, 'recipient', messageContent);

        // Mark the message as read
        const options = {
          senderId: senderUser.userId,
          messageIds: [sentMessage.messageId],
        };
        const result = await userManager.markMessagesAsRead(recipientSocket.id, options);

        // Validate the result
        expect(result).toBeDefined();
        expect(result.marked).toBe(1);
      }, SOCKET_TEST_TIMEOUT);

      test('should handle no unread messages', async () => {
        // Attempt to mark non-existent messages as read
        const options = {
          direction: 'incoming',
          messageIds: ['nonExistentMessageId'],
        };
        /*     const result = await userManager.markMessagesAsRead(recipientSocket.id, options);
     
             // Validate the result
             expect(result).toBeDefined();
             expect(result.marked).toBe(0); // No messages were updated
     */
        await expect(
          userManager.markMessagesAsRead(recipientSocket.id, options)
        ).rejects.toThrow(/Invalid options/);
      }, SOCKET_TEST_TIMEOUT);

      test('should handle invalid options', async () => {
        // Attempt to mark messages as read with invalid options
        const invalidOptions = {
          direction: 'invalidDirection', // Invalid direction
          'invalid': 'invalid',
          messageIds: ['nonExistentMessageId'],
        };


        await expect(
          userManager.markMessagesAsRead(recipientSocket.id, invalidOptions)
        ).rejects.toThrow(/Invalid options/);
      }, SOCKET_TEST_TIMEOUT);

      test('should handle unauthenticated socketId', async () => {
        // Disconnect the recipient socket to invalidate it
        const du = await userManager.disconnectUser(recipientSocket.id);
        expect(du.state).toBe('offline');
        // Attempt to mark messages as read with an unauthenticated socketId
        const options = {
          messageIds: ['nonExistentMessageId'],
        };

        const result = await userManager.markMessagesAsRead(recipientSocket.id, options);
        expect(result).toBe(null);
      }, SOCKET_TEST_TIMEOUT);
    });
  });
});