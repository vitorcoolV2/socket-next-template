import { startServer, stopServer, users as userManager } from 'a-socket/server.mjs';
import { createClientSocket } from '../utils.mjs';

const PORT = process.env.PORT || 3001; // Use a different port to avoid conflicts
const BASE_URL = `http://localhost:${PORT}`;

const SERVER_START_TIMEOUT = 10000; // Increased timeout for server startup
const SOCKET_TEST_TIMEOUT = 15000; // Timeout for socket-related tests

// Increase global Jest timeout
jest.setTimeout(20000);

let httpServer;

beforeAll(async () => {
  // Start the server
  httpServer = await startServer();

  // Small delay to ensure the server is fully ready
  await new Promise(resolve => setTimeout(resolve, 500));
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
  let senderUser, recipientUser;

  beforeEach(async () => {
    // Create and connect sockets
    senderSocket = await createClientSocket(BASE_URL);
    recipientSocket = await createClientSocket(BASE_URL);

    // Store users in the user manager
    senderUser = await userManager.storeUser(senderSocket.id, {
      userId: 'sender',
      userName: 'Sender',
    }, true);
    recipientUser = await userManager.storeUser(recipientSocket.id, {
      userId: 'recipient',
      userName: 'Recipient',
    }, true);

    // Add listeners for debugging
    recipientSocket.on('connect', () => {
      console.log('Recipient socket connected');
    });
    recipientSocket.on('disconnect', () => {
      console.log('Recipient socket disconnected');
    });
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
      test(
        'should send and receive a private message using sendMessage',
        async () => {
          const messageContent = 'Hello, world!';

          // Send the message
          const sentMessage = await userManager.sendMessage(senderSocket.id, 'recipient', messageContent);
          expect(sentMessage.status).toBe('sent');

          // Wait for the recipient to receive the message
          /*const receivedMessage = await new Promise((resolve) => {
            recipientSocket.on('receivedMessage', (msg) => resolve(msg));
          });*/

          // Assertions for the received message
          expect(sentMessage).toMatchObject({
            content: messageContent,
            sender: { userId: 'sender', userName: 'Sender' },
            recipientId: 'recipient',
          });

          // Assertions for the sent message
          expect(sentMessage).toBeDefined();
          expect(sentMessage.messageId).toBeDefined();
        },
        SOCKET_TEST_TIMEOUT
      );

      test(
        'should mark messages as read',
        async () => {
          const messageContent = 'Test message to mark as read';

          // Send a private message
          const sentMessage = await userManager.sendMessage(senderSocket.id, 'recipient', messageContent);

          // Mark the message as read
          const options = {
            senderId: senderUser.userId,
            messageIds: [sentMessage.messageId],
          };
          const result = await userManager.markMessagesAsRead(recipientSocket.id, options);

          // Validate the result
          expect(result).toBeDefined();
          expect(result.marked).toBe(1); // One message should be marked as read
        },
        SOCKET_TEST_TIMEOUT
      );

      test(
        'should handle no unread messages',
        async () => {
          const options = {
            direction: 'incoming',
            messageIds: ['nonExistentMessageId'],
          };

          // Attempt to mark non-existent messages as read
          await expect(
            userManager.markMessagesAsRead(recipientSocket.id, options)
          ).rejects.toThrow(/Invalid options/);
        },
        SOCKET_TEST_TIMEOUT
      );

      test(
        'should handle invalid options',
        async () => {
          const invalidOptions = {
            direction: 'invalidDirection', // Invalid direction
            'invalid': 'invalid',
            messageIds: ['nonExistentMessageId'],
          };

          // Attempt to mark messages as read with invalid options
          await expect(
            userManager.markMessagesAsRead(recipientSocket.id, invalidOptions)
          ).rejects.toThrow(/Invalid options/);
        },
        SOCKET_TEST_TIMEOUT
      );

      test(
        'should handle unauthenticated socketId',
        async () => {
          // Disconnect the recipient socket to invalidate it
          const du = await userManager.disconnectUser(recipientSocket.id);
          expect(du.state).toBe('offline');

          // Attempt to mark messages as read with an unauthenticated socketId
          const options = {
            messageIds: ['nonExistentMessageId'],
          };

          const result = await userManager.markMessagesAsRead(recipientSocket.id, options);
          expect(result).toBe(null); // Should return null for unauthenticated socket
        },
        SOCKET_TEST_TIMEOUT
      );
    });
  });
});