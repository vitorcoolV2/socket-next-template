import { startServer, stopServer, users as userManager } from 'a-socket/server.mjs';
import { createClientSocket } from '../utils.mjs';

const PORT = process.env.PORT || 3001; // Use a different port to avoid conflicts
const BASE_URL = `http://localhost:${PORT}`;

const SERVER_START_TIMEOUT = 10000; // Increased timeout for server startup
const HTTP_TEST_TIMEOUT = 200;
const SOCKET_TEST_TIMEOUT = 10000;



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
  let senderSocket, recipientSocket;
  let senderUser, recipientUser;

  beforeEach(async () => {
    // Create and connect sockets
    senderSocket = await createClientSocket(BASE_URL);
    senderUser = await userManager.storeUser(senderSocket.id, {
      userId: 'sender',
      userName: 'Sender',
    }, true);

    recipientSocket = await createClientSocket(BASE_URL);
    recipientUser = await userManager.storeUser(recipientSocket.id, {
      userId: 'recipient',
      userName: 'Recipient',
    }, true);
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

        const messageContent = 'Hello, world!';
        const sentMessage = await userManager.sendMessage(senderSocket.id, 'recipient', messageContent);

        expect(sentMessage).toMatchObject({
          status: 'pending',
          content: messageContent,
          sender: { userId: 'sender', userName: 'Sender' },
          recipientId: 'recipient',
        });

        // Validate the sent message
        expect(sentMessage).toBeDefined();
        expect(sentMessage.messageId).toBeDefined();
        expect(sentMessage.status).toBe('pending');
        //   await Promise((resolve, reject) => setInterval(resolve, 1000));
      }, SOCKET_TEST_TIMEOUT);

      test('should mark messages as read', async () => {
        // Send a private message
        const messageContent = 'Test message to mark as read';
        const sentMessage = await userManager.sendMessage(senderSocket.id, 'recipient', messageContent);
        expect(sentMessage.status).toBe('pending');
        const mess = await userManager._getMessages('recipient', {
          direction: 'outgoing',

          messageIds: [sentMessage.messageId]
        });

        // Mark the message as read
        const options = {
          senderId: senderUser.userId,
          messageIds: [sentMessage.messageId],
        };
        const result = await userManager.markMessagesAsRead(recipientSocket.id, options);

        // Validate the result
        expect(result).toBeDefined();
        expect(result.marked).toBe(1);
      }, SOCKET_TEST_TIMEOUT) * 2;

      test('should handle no unread messages', async () => {
        // Attempt to mark non-existent messages as read
        const options = {
          messageIds: ['nonExistentMessageId'],
        };
        const result = await userManager.markMessagesAsRead(recipientSocket.id, options);

        // Validate the result
        expect(result).toBeDefined();
        expect(result.marked).toBe(0); // No messages were updated
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
        await userManager.disconnectUser(recipientSocket.id);

        // Attempt to mark messages as read with an unauthenticated socketId
        const options = {
          messageIds: ['nonExistentMessageId'],
        };

        const result = await userManager.markMessagesAsRead(recipientSocket.id, options);
        expect(result).toBe(null);
      }, SOCKET_TEST_TIMEOUT);


      test('should retrieve empty conversation history', async () => {
        // Ensure sockets are connected and users are stored
        const senderSocketId = senderSocket.id;
        console.log('Sender Socket ID:', senderSocketId);

        const socketId = senderSocket.id;
        const options = {
          limit: 10,
          offset: 0,
          type: 'private',
          otherPartyId: recipientUser.userId,
        };

        const history = await userManager.getMessageHistory(socketId, options);

        // Validate the response
        expect(history.messages.length).toBeGreaterThan(0);
        expect(history.total).toBeGreaterThan(0);
        expect(history.hasMore).toBe(history.total > 10);
      }, SOCKET_TEST_TIMEOUT);

      test('should retrieve full conversation history', async () => {
        // Send multiple private messages between sender and recipient
        const messages = [
          { senderId: 'sender', recipientId: 'recipient', content: 'Hi there!' },
          { senderId: 'recipient', recipientId: 'sender', content: 'Hello back!' },
          { senderId: 'sender', recipientId: 'recipient', content: 'How are you?' },
          { senderId: 'recipient', recipientId: 'sender', content: 'I am good, thanks!' },
        ];


        let socketId;
        let msgs = [];
        for (const msg of messages) {
          const socketId = msg.senderId === 'sender' ? senderSocket.id : recipientSocket.id;
          msgs.push(await userManager.sendMessage(socketId, msg.recipientId, msg.content));
        }

        // Fetch message history for the sender
        const options = {
          limit: 10,
          offset: 0,
          type: 'private',
          otherPartyId: 'recipient',
        };


        socketId = senderSocket.id;
        const history = await userManager.getMessageHistory(socketId, options);

        // Validate the fetched messages
        expect(history.messages.length).toBeGreaterThanOrEqual(messages.length);
        expect(history.total).toBeGreaterThanOrEqual(messages.length);
        expect(history.hasMore).toBe(history.total > 10);

        // Ensure messages are in chronological order
        const sortedMessages = [...messages].sort((a, b) => a.timestamp - b.timestamp);
        sortedMessages.forEach((msg, index) => {
          expect(msg.content).toBe(sortedMessages[index].content);
          expect(msg.senderId).toBe(sortedMessages[index].senderId);
          expect(msg.recipientId).toBe(sortedMessages[index].recipientId);
        });
      }, SOCKET_TEST_TIMEOUT);
    });
  });

});