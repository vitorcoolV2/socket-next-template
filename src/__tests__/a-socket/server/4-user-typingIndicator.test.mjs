import { startServer, stopServer, users as userManager } from 'a-socket/server.mjs';
import { createClientSocket } from '../utils.mjs';


const PORT = process.env.PORT || 3001;
const BASE_URL = `http://localhost:${PORT}`;

const SERVER_START_TIMEOUT = 10000; // < seconds
const HTTP_TEST_TIMEOUT = 200; // <1 second for HTTP tests
const SOCKET_TEST_TIMEOUT = 8000; // <5 seconds for socket tests



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
    // Create and connect sockets using the utility function
    senderSocket = await createClientSocket(BASE_URL);
    recipientSocket = await createClientSocket(BASE_URL);

    senderUser = await userManager.storeUser(senderSocket.id, {
      userId: 'sender',
      userName: 'Sender'
    }, true);
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
        //const u1 = await userManager.storeUser(senderSocket.id, { userId: 'sender', userName: 'Sender' }, true);
        //const u2 = await userManager.storeUser(recipientSocket.id, { userId: 'recipient', userName: 'Recipient' }, true);

        const messageContent = 'Hello, world!';
        const message = await userManager.sendMessage(senderSocket.id, 'recipient', messageContent);



        expect(message).toMatchObject({
          status: 'pending',
          content: messageContent,
          sender: { userId: 'sender', userName: 'Sender' },
          recipientId: 'recipient',
        });
      }, SOCKET_TEST_TIMEOUT);
    });

    describe('Typing Indicator', () => {
      test('should send and receive a typing indicator', async () => {
        const sender = await userManager.storeUser(senderSocket.id, { userId: 'sender', userName: 'Sender' }, true);
        const recipient = await userManager.storeUser(recipientSocket.id, { userId: 'recipient', userName: 'Recipient' }, true);

        const typingData = {
          isTyping: true,
          recipientId: recipient.userId,
        };

        // Sender emits the typing indicator event
        senderSocket.emit('typingIndicator', typingData);

        // Recipient listens for the typing indicator event
        const typingEvent = await new Promise((resolve) => {
          recipientSocket.on('typingIndicator', (data) => resolve(data));
        });

        // Validate the received typing indicator
        expect(typingEvent).toMatchObject({
          success: true,
          event: 'typingIndicator',
          sender: sender.userId,
          isTyping: true,
          timestamp: expect.any(String), // Timestamp should be in ISO format
        });
      }, SOCKET_TEST_TIMEOUT);


      test('should send typing indicator', async () => {
        const typingData = {
          isTyping: true,
          recipientId: recipientUser.userId,
        };

        // Sender emits the typing indicator event
        senderSocket.emit('typing', typingData);

        // Recipient listens for the typing indicator event
        const typingEvent = await new Promise((resolve) => {
          recipientSocket.on('typing', (data) =>
            resolve(data));
        });

        // Validate the received typing indicator
        expect(typingEvent).toBe(recipientUser.userId);
      }, SOCKET_TEST_TIMEOUT); // Increased timeout to 10 seconds

      test('should send stop typing indicator', async () => {
        const typingData = {
          isTyping: false,
          recipientId: recipientUser.userId,
        };

        // Sender emits the typing indicator event
        senderSocket.emit('stopTyping', typingData);

        // Recipient listens for the typing indicator event
        const typingEvent = await new Promise((resolve) => {
          recipientSocket.on('stopTyping', (data) =>
            resolve(data));
        });

        // Validate the received typing indicator
        expect(typingEvent).toBe(recipientUser.userId);
      }, SOCKET_TEST_TIMEOUT); // Increased timeout to 10 seconds      


      test('should handle stopping typing', async () => {
        const sender = await userManager.storeUser(senderSocket.id, { userId: 'sender', userName: 'Sender' }, true);
        const recipient = await userManager.storeUser(recipientSocket.id, { userId: 'recipient', userName: 'Recipient' }, true);

        const typingData = {
          isTyping: false,
          recipientId: recipient.userId,
        };

        // Sender emits the typing indicator event
        senderSocket.emit('typingIndicator', typingData);

        // Recipient listens for the typing indicator event
        const typingEvent = await new Promise((resolve) => {
          recipientSocket.on('typingIndicator', (data) => resolve(data));
        });

        // Validate the received typing indicator
        expect(typingEvent).toMatchObject({
          success: true,
          event: 'typingIndicator',
          sender: sender.userId,
          isTyping: false,
          timestamp: expect.any(String), // Timestamp should be in ISO format
        });
      }, SOCKET_TEST_TIMEOUT);



      test('should handle invalid recipient IDs', async () => {
        // Assert that no typingIndicator event will be received
        expect.assertions(1);

        // Step 1: Add sender user
        const sender = await userManager.storeUser(senderSocket.id, { userId: 'sender', userName: 'Sender' }, true);

        // Step 2: Define invalid typing data
        const invalidTypingData = {
          isTyping: true,
          recipientId: 'nonexistent-user',
        };

        // Step 3: Call the typingIndicator method
        const typingResult = await userManager.typingIndicator(senderSocket.id, invalidTypingData);

        // Step 4: Validate the result (no typing event should be sent)
        expect(typingResult).toBeNull(); // Expect the result to be null for invalid recipients

        // Step 5: Ensure no typingIndicator event is received by the recipient
        await new Promise((resolve) => {
          recipientSocket.once('typingIndicator', () => {
            throw new Error('Unexpected typing indicator event');
          });

          // Resolve the promise after a short delay if no event is received
          setTimeout(resolve, 1000);
        });
      }, SOCKET_TEST_TIMEOUT);
    });
  });
});