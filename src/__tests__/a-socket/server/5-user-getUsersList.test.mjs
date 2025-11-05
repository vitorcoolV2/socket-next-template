import { startServer, stopServer, users as userManager } from 'a-socket/server.mjs';
import { createClientSocket } from '../utils.mjs';


const PORT = process.env.PORT || 3001;
const BASE_URL = `http://localhost:${PORT}`;

const SERVER_START_TIMEOUT = 5000; // < seconds
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
  let senderUser;

  beforeEach(async () => {
    // Create and connect sockets using the utility function
    senderSocket = await createClientSocket(BASE_URL);
    await userManager.storeUser(senderSocket.id, {
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
        await userManager.getUserBySocketId(senderSocket.id);

        const messageContent = 'Hello, world!';
        const message = await userManager.sendMessage(senderSocket.id, 'recipient', messageContent);

        expect(message).toMatchObject({
          status: 'sent',
          content: messageContent,
          sender: { userId: 'sender', userName: 'Sender' },
          recipientId: 'recipient',
        });
      }, SOCKET_TEST_TIMEOUT);

      test('should retrieve users after sending a private message', async () => {
        // Store users

        // Send a private message
        const messageContent = 'Hello, world!';
        await userManager.sendMessage(senderSocket.id, 'recipient', messageContent);

        // Retrieve users with filters
        const retrievedUsers = await userManager.getUsersList(senderSocket.id, {
          state: ['authenticated'],
          limit: 10,              // Retrieve up to 10 users
          offset: 0               // Start from the first user
        });

        // Validate the response
        expect(retrievedUsers).toBeDefined();
        expect(retrievedUsers.length).toBeGreaterThanOrEqual(2); // Sender and Recipient should be active

        // Check if both users are present in the retrieved users list
        const senderInRetrievedUsers = retrievedUsers.some(user => user.userId === 'sender');
        const recipientInRetrievedUsers = retrievedUsers.some(user => user.userId === 'recipient');

        expect(senderInRetrievedUsers).toBe(true);
        expect(recipientInRetrievedUsers).toBe(true);

        // Validate individual user fields
        retrievedUsers.forEach(user => {
          expect(user).toHaveProperty('userId');
          expect(user).toHaveProperty('userName');
          expect(user).toHaveProperty('state');
          expect(user).toHaveProperty('sockets');
          expect(user.state).toBe('authenticated'); // Ensure all users are authenticated          
        });
      }, SOCKET_TEST_TIMEOUT);

      //  test('should handle edge case: should disconnect first', async () => {
      // Disconnect the sender socket to invalidate it

      // });

      test('should handle edge case: no users match filters', async () => {
        // Store users

        // Retrieve users with strict filters
        const retrievedUsers = await userManager.getUsersList(senderSocket.id, {
          state: ['disconnected'],
          limit: 10,
          offset: 0
        });

        // Validate the response
        expect(retrievedUsers).toBeDefined();
        expect(retrievedUsers.length).toBe(0); // No users should match the filters
      }, SOCKET_TEST_TIMEOUT);

      test('should handle edge case: pagination beyond available users', async () => {
        // Store users

        // Retrieve users with pagination beyond available users
        const retrievedUsers = await userManager.getUsersList(senderSocket.id, {
          state: ['authenticated'],
          limit: 10,  // Request more than available
          offset: 5   // Offset beyond available users
        });

        // Validate the response
        expect(retrievedUsers).toBeDefined();
        expect(retrievedUsers.length).toBe(0); // Pagination should return no results
      }, SOCKET_TEST_TIMEOUT);

      test('should handle edge case: invalid options', async () => {
        // Attempt to retrieve users with invalid options
        await expect(
          userManager.getUsersList(senderSocket.id, {
            state: ['invalid-state'],
            limit: 10,
            offset: 0
          })
        ).rejects.toThrow(/Invalid options/); // Expect an error due to invalid options
      }, SOCKET_TEST_TIMEOUT);



      test('should handle edge case: unauthenticated socketId', async () => {
        // Attempt to retrieve users with an unauthenticated socketId
        const stangeValue = await userManager.getUsersList(senderSocket.id, {
          state: ['authenticated'],
          limit: 10,
          offset: 0
        });

        expect(stangeValue).not.toBeNull(); // this test validate anomaly. how the ek is the disconnected user diferent from null?

        const retrievedUsers = await userManager.getUsersList('invalid-socket-id-xxxx', {
          state: ['authenticated'],
          limit: 10,
          offset: 0
        });

        // Validate the response
        expect(retrievedUsers).toBeNull(); // Should return null for unauthenticated socketId
      }, SOCKET_TEST_TIMEOUT);

      test('should handle edge case: empty user store', async () => {
        // Reset the user store to simulate an empty state
        await userManager.__resetData();

        // Attempt to retrieve users
        const retrievedUsers = await userManager.getUsersList(senderSocket.id, {
          state: ['authenticated'],
          limit: 10,
          offset: 0
        });

        // Validate the response
        expect(retrievedUsers).toBeNull();
      }, SOCKET_TEST_TIMEOUT);


      test('should be able to disconnect all sockets', async () => {
        // Get user before disconnection
        const userBefore = await userManager.getUserBySocketId(senderSocket.id);
        expect(userBefore).toBeDefined();
        expect(userBefore.sockets.length).toBeGreaterThanOrEqual(1);
        expect(userBefore.sockets[0].socketId).toBeDefined();
        expect(userBefore.sockets[0].state).toBe('authenticated');
        //expect(userBefore.sockets[1].socketId).toBeDefined();
        //expect(userBefore.sockets[1].state).toBe('authenticated');

        // Disconnect all remaining sockets
        let muts;
        if (userBefore.sockets && userBefore.sockets.length > 0) {
          muts = await Promise.all(
            userBefore.sockets.map(s => userManager.disconnectUser(s.socketId))
          );
        }

        // Verify user is offline
        expect(muts.every(u => u.userId === senderUser.userId)).toBe(true); // only sockets from senderUser
        expect(muts.some(u => u.state === 'offline')).toBe(true);

        // Optional: Verify user cannot be found by socket ID
        const userAfter = await userManager.getUserBySocketId(senderSocket.id);
        expect(userAfter).toBeNull(); // or whatever your API returns
      });
    });
  }
  );
});