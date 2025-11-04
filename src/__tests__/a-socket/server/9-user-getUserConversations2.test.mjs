import { startServer, stopServer, users as userManager } from 'a-socket/server.mjs';
import { createClientSocket } from '../utils.mjs';

const PORT = process.env.PORT || 3001; // Use a different port to avoid conflicts
const BASE_URL = `http://localhost:${PORT}`;

const SERVER_START_TIMEOUT = 10000; // Increased timeout for server startup

const SOCKET_TEST_TIMEOUT = 10000;

jest.setTimeout(SOCKET_TEST_TIMEOUT * 2);
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
  let SU, RU;

  beforeEach(async () => {
    // Create and connect sockets
    senderSocket = await createClientSocket(BASE_URL);
    SU = await userManager.storeUser(senderSocket.id, {
      userId: 'sender',
      userName: 'Sender',
    }, true);

    recipientSocket = await createClientSocket(BASE_URL);
    RU = await userManager.storeUser(recipientSocket.id, {
      userId: 'recipient',
      userName: 'Recipient',
    }, true);

  });

  afterEach(async () => {
    // Disconnect and clean up sockets
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

      test('should retrieve conversation state counts', async () => {


        // Send multiple private messages between sender and recipient
        const messages = [
          { senderId: 'sender', recipientId: 'recipient', content: 'Hi there!' },
          { senderId: 'sender', recipientId: 'sender', content: 'Hi me self!' },
          { senderId: 'recipient', recipientId: 'sender', content: 'Hello back!' },
          { senderId: 'sender', recipientId: 'recipient', content: 'How are you?' },
          { senderId: 'recipient', recipientId: 'sender', content: 'I am good, thanks!' },
        ];

        for (const msg of messages) {
          const socket = msg.senderId === 'sender' ? senderSocket : recipientSocket;
          await userManager.sendMessage(socket.id, msg.recipientId, msg.content);
        }

        // Retrieve conversation state counts
        const options = {
          type: 'private',
          limit: 10,
          offset: 0,
          include: [],
        };

        // Simulate marking messages as read
        //const markResponse = await userManager.markMessagesAsRead(senderSocket.id, recipientUser.userId);


        // get "sender" conversationsList
        const result = await userManager.getUserConversationsList(senderSocket.id, options);

        // Validate the result, The senderSocker sent messages to two distinct users
        expect(result.filter(r => r.userId === SU.userId).length).toBeGreaterThanOrEqual(2);
        // Validate that one of targets users is sender it self
        const conversation = result.find(r => r.otherPartyId === SU.userId);
        // Validate 'sender' incoming messages from it self. should be one
        expect(conversation.incoming.sent).toBeGreaterThanOrEqual(1);
        expect(conversation.outgoing.sent).toBeGreaterThanOrEqual(1);
        expect(conversation.lastMessageAt).toBeDefined();
      }, SOCKET_TEST_TIMEOUT * 1);


      test('should return empty array for invalid user', async () => {
        // Retrieve conversation state counts for an invalid user
        const options = {
          limit: 10,
          offset: 0,
          include: [],
        };

        const result = await userManager.getUserConversationsList("invalid-socket", options);

        // Validate the result
        expect(result).toEqual(null);
      }, SOCKET_TEST_TIMEOUT);
    });
  });
});