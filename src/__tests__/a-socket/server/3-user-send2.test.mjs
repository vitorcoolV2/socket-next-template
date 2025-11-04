import { startServer, stopServer, users as userManager } from 'a-socket/server.mjs';
import { v4 as uuidv4 } from 'uuid';

import { createClientSocket, sendMessageWaitEvent, retryWithTimeout } from '../utils.mjs';


const PORT = process.env.PORT || 3001; // Use a different port to avoid conflicts
const BASE_URL = `http://localhost:${PORT}`;

const SERVER_START_TIMEOUT = 10000; // Increased timeout for server startup
const SOCKET_TEST_TIMEOUT = 10000; // Timeout for socket-related tests


// Increase global Jest timeout
jest.setTimeout(SOCKET_TEST_TIMEOUT * 3);

let httpServer;

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

describe('Socket.IO Server Tests', () => {
  let senderSocket, recipientSocket;
  let senderUser, recipientUser;
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


  afterEach(async () => {
    // Disconnect and close sockets after each test
    if (senderSocket) {
      await userManager.disconnectUser(senderSocket.id);
      senderSocket.disconnect();
      senderSocket.close();
    }
    if (recipientSocket) {
      await userManager.disconnectUser(recipientSocket.id);
      recipientSocket.disconnect();
      recipientSocket.close();
    }
  });

  describe('Messaging', () => {
    describe('Private Messages', () => {
      test('should send and receive a private message', async () => {
        const messageContent = 'Hello, world!';
        console.log('Sender emitting sendMessage event');

        try {
          // Send the message via the user manager
          const persistedMessage = await userManager.sendMessage(senderSocket.id, 'recipient', messageContent);

          // Validate the persisted message
          expect(persistedMessage).toMatchObject({
            content: messageContent,
            sender: { userId: 'sender', userName: 'Sender' },
            recipientId: 'recipient',
          });

          expect(persistedMessage).toBeDefined();
          expect(persistedMessage.messageId).toBeDefined();
          expect(persistedMessage.status).toBe('sent');
        } catch (error) {
          throw new Error(`Failed to send message: ${error.message}`);
        }
      }, SOCKET_TEST_TIMEOUT);

      test(
        'when cant get acknowledgment from recipient, should update message status to delivered ',
        async () => {
          const ___CONTENT = 'Hello, world UT!';

          // Enable acknowledgment on the recipient socket
          recipientSocket.on('update_message_status', (msg, ack) => {
            console.log('Recipient received message:', msg);

            expect(msg).toBeDefined();
            expect(msg.status).toBe('delivered');
            if (ack) {
              console.log('update_message_status pending acknowledgment...');
              ack({ success: true, message: 'received' }); // recipient  Acknowledge msg "receipt"
            }
          });
          const sentMessage = await sendMessageWaitEvent(senderSocket, ___CONTENT, 'recipient');
          expect(sentMessage).toBeDefined();
          expect(sentMessage.status).toBe('delivered');
        },
        SOCKET_TEST_TIMEOUT * 2
      );
      test('when recipient is offline, message should be persisted with pending status', async () => {
        const content = 'Test offline message ' + uuidv4();

        // Actually disconnect recipient
        recipientSocket.disconnect();
        await new Promise(resolve => setTimeout(resolve, 100));

        const sentMessage = await sendMessageWaitEvent(senderSocket, content, 'recipient', 5000);

        expect(sentMessage).toBeDefined();
        expect(sentMessage.status).toBe('pending');
        expect(sentMessage.content).toBe(content);
      });

      test('when recipient does not acknowledge, message status should be pending', async () => {
        const content = 'Test no-ack message ' + uuidv4();

        let receivedMessage = null;
        let statusUpdates = [];

        recipientSocket.on('update_message_status', (msg, ack) => {
          receivedMessage = msg;
          // Intentionally NOT calling ack() - simulate unresponsive client
        });

        // Listen for status updates on sender side
        senderSocket.on('update_message_status', (msg) => {
          statusUpdates.push(msg);
        });

        // Immediate response - should be 'sent'
        const sentMessage = await sendMessageWaitEvent(senderSocket, content, 'recipient');

        expect(receivedMessage).toBeTruthy(); // Verify recipient actually received it
        expect(sentMessage).toBeDefined();
        expect(sentMessage.status).toBe('pending'); // Immediate status

        // Check if status was updated to pending
        const pendingUpdate = statusUpdates.find(update =>
          update.messageId === sentMessage.messageId && update.status === 'pending'
        );

        // The final status should become 'pending' due to no acknowledgment
        expect(pendingUpdate).toBeTruthy();
      });

      test(
        'should deliver a message to multiple recipients',
        async () => {
          const messageContent = 'Hello, everyone!';
          const recipientIds = ['recipient1', 'recipient2'];

          // Create sockets for multiple recipients
          const recipientSockets = recipientIds.map(async (id) => {
            const socket = await createClientSocket(BASE_URL);
            await userManager.storeUser(socket.id, { userId: id, userName: id }, true);
            return socket;
          });

          const [recipientSocket1, recipientSocket2] = await Promise.all(recipientSockets);

          // Emit the sendMessage event from the sender socket
          const sentMessages = await Promise.all(
            recipientIds.map((id) =>
              userManager.sendMessage(senderSocket.id, id, messageContent)
            )
          );

          // Validate the messages
          sentMessages.forEach((message) => {
            expect(message).toBeDefined();
            expect(message.content).toBe(messageContent);
            expect(message.status).toBe('sent');
          });

          // Disconnect recipient sockets
          recipientSocket1.disconnect();
          recipientSocket2.disconnect();
        },
        SOCKET_TEST_TIMEOUT * 2
      );

      test(
        'should fail when sending a message to a non-existent recipient',
        async () => {
          const messageContent = 'Hello, invalid recipient!';

          await expect(
            userManager.sendMessage(senderSocket.id, 'invalidRecipient', messageContent)
          ).rejects.toThrow(/Recipient not found/);
        },
        SOCKET_TEST_TIMEOUT
      );

      test(
        'should reject sending an empty message',
        async () => {
          const content = '';

          await expect(
            userManager.sendMessage(senderSocket.id, 'recipient', content)
          ).rejects.toThrow(/\"content\" is not allowed to be empty/);
        },
        SOCKET_TEST_TIMEOUT
      );

      test(
        'when can not get acknowledgment from recipient, should update message status to pending',
        async () => {
          const content = 'Hello, world O!';

          // Enable acknowledgment on the recipient socket
          recipientSocket.on('update_message_status', (msg, ack) => {
            console.log('Recipient received message:', msg);

            expect(msg).toBeDefined();
            expect(msg.status).toBe('delivered'); //<<<<<<<<<<<
            if (ack) {
              ___the_message_id = msg.id;  /// keep this value to retrieve full message
              console.log('update_message_status pending acknowledgment...');
              ack({ success: true, message: 'received' }); // recipient  Acknowledge msg "receipt"
            }
          });

          const sentMessage = await sendMessageWaitEvent(senderSocket, content, 'recipient');

          expect(sentMessage).toBeDefined();
          expect(sentMessage.status).toBe('delivered'); // <<<<<<<<
        },
        SOCKET_TEST_TIMEOUT
      );

      test('when cant not get acknowledgment from recipient, should update message status to pending', async () => {
        // Arrange: Simulate recipient being offline
        const recipientId = 'recipient';
        const content = 'Test message';

        // Act: Send message
        const sentMessage = await sendMessageWaitEvent(senderSocket, content, 'recipient');
        expect(sentMessage.status).toBe('pending');
      }, SOCKET_TEST_TIMEOUT);
      test(
        'should fail when time to deliver recipient ack is bigger than specified timeout',
        async () => {
          // Arrange: Simulate recipient being online but unresponsive

          let sentMessage;
          let lastError;

          // Act: Send message with decreasing timeout values until it fails
          for (let timeout = 500; timeout >= 50; timeout -= 50) {
            try {
              const content = `Test message timeout ${timeout}`;
              sentMessage = await sendMessageWaitEvent(senderSocket, content, 'recipient', timeout);

              // Assert: Ensure the message was delivered successfully within the timeout
              expect(sentMessage).toBeDefined();
              expect(sentMessage.status).toBe('pending'); // Cause 'delivered' is the success status
            } catch (error) {
              // Capture the error if the message fails to deliver
              lastError = error;

              // Stop decrementing once the first failure occurs
              break;
            }
          }

          // Assert: Ensure the last attempt resulted in an error due to timeout
          expect(lastError).toBeDefined();
          expect(lastError.message).toMatch(/timed out/);
        },
        SOCKET_TEST_TIMEOUT
      );
    });
  });
});