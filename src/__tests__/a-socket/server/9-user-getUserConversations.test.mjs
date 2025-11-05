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
      test('should handle pagination correctly', async () => {
        // Send multiple private messages between sender and recipient
        const messages = [
          { senderId: 'sender', recipientId: 'recipient', content: 'Hi there!' },
          { senderId: 'recipient', recipientId: 'sender', content: 'Hello back!' },
          { senderId: 'sender', recipientId: 'recipient', content: 'How are you?' },
          { senderId: 'recipient', recipientId: 'sender', content: 'I am good, thanks!' },
          { senderId: 'recipient', recipientId: 'sender', content: 'I am good, thanks for more one incoming!' },
        ];

        // RU/O:3/I:2
        // SU/O:2/I:3

        for (const msg of messages) {
          const socket = msg.senderId === 'sender' ? senderSocket : recipientSocket;
          socket.emit('sendMessage', msg);
        }

        // wait a little for updateMessageStatus
        let ct = 0;
        //const sentMessage2 = 
        await new Promise((resolve) => {
          senderSocket.on('update_message_status', (msg) => {

            //expect(msg.status).toBe('pending'); //  .toBe('delivered');
            ct++;
            if (ct === 5) {
              resolve(msg);
            }
          });
        });


        // Retrieve conversation state counts with pagination
        const options = {
          ///userId: senderUser.userId,  <<<<<<<invalid option make test also
          limit: 1,
          offset: 0,
          include: [],
        };

        // Validate the result / the sender stats


        // SU/O:2/I:3
        let result = await userManager.getUserConversationsList(senderSocket.id, options);
        expect(result).toHaveLength(1);
        let conversation = result[0];
        expect(conversation.userId).toBe(SU.userId);
        expect(conversation.otherPartyId).toBe(RU.userId);
        expect(conversation.outgoing.sent).toBeGreaterThanOrEqual(1);
        expect(conversation.outgoing.pending).toBeGreaterThanOrEqual(1);
        expect(conversation.outgoing.read).toBeGreaterThanOrEqual(0);
        expect(conversation.incoming.sent).toBeGreaterThanOrEqual(3);
        expect(conversation.incoming.pending).toBeGreaterThanOrEqual(2);
        expect(conversation.incoming.read).toBeGreaterThanOrEqual(0);
        expect(conversation.lastMessageAt).toBeDefined();

        // Validate the result / the recipient stats
        // RU/O:3/I:2
        result = await userManager.getUserConversationsList(recipientSocket.id, options);
        conversation = result[0];
        expect(conversation.userId).toBe(RU.userId); // the sender stats
        expect(conversation.otherPartyId).toBe(SU.userId);
        expect(conversation.outgoing.sent).toBeGreaterThanOrEqual(3);
        expect(conversation.outgoing.pending).toBeGreaterThanOrEqual(3);
        expect(conversation.outgoing.read).toBeGreaterThanOrEqual(0);
        expect(conversation.incoming.sent).toBeGreaterThanOrEqual(2);
        expect(conversation.incoming.pending).toBeGreaterThanOrEqual(2);
        expect(conversation.incoming.read).toBeGreaterThanOrEqual(0);
        expect(conversation.lastMessageAt).toBeDefined();
      }, SOCKET_TEST_TIMEOUT * 2);

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