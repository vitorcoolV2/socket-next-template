import axios from 'axios';
import ClientIO from 'socket.io-client';
import { startServer, stopServer } from 'a-socket/server.mjs';

const PORT = process.env.PORT || 3001;
const BASE_URL = `http://localhost:${PORT}`;

const SERVER_START_TIMEOUT = 999; // < seconds
const HTTP_TEST_TIMEOUT = 200; // <1 second for HTTP tests
const SOCKET_TEST_TIMEOUT = 500; // <3 seconds for socket tests


jest.setTimeout(10000); // Increase global timeout

let httpServer;
beforeAll(async () => {
  // Start the server
  httpServer = await startServer();

  // Small delay to ensure server is fully ready
  await new Promise(resolve => setTimeout(resolve, 500));
}, SERVER_START_TIMEOUT);

afterAll(async () => {
  // Clean up client
  if (clientSocket) {
    clientSocket.disconnect();
    clientSocket.close();
  }

  // Stop the server
  await stopServer();

  // Close the HTTP server explicitly
  if (httpServer) {
    await new Promise((resolve) => httpServer.close(resolve));
  }
});

beforeEach(async () => {
  // Connect client for each test
  clientSocket = ClientIO(BASE_URL, {
    transports: ['websocket', 'polling'],
    forceNew: true,
    timeout: 5000,
  });

  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      reject(new Error('Connection timeout'));
    }, 5000);

    clientSocket.on('connect', () => {
      clearTimeout(timeout);
      resolve();
    });

    clientSocket.on('connect_error', (error) => {
      clearTimeout(timeout);
      reject(error);
    });
  });
});

afterEach(() => {
  // Clean up client after each test
  if (clientSocket) {
    clientSocket.disconnect();
    clientSocket.close();
  }
});

describe('Socket.IO Server Tests', () => {
  describe('HTTP Server', () => {
    test('should respond to health check', async () => {
      const response = await axios.get(`${BASE_URL}/health`);
      expect(response.status).toBe(200);
      expect(response.data).toMatchObject({
        status: 'ok',
        message: 'Server is running',
      });
    }, HTTP_TEST_TIMEOUT);

    test('should handle CORS', async () => {
      const response = await axios.get(`${BASE_URL}/health`, {
        headers: { origin: 'http://localhost:3000' },
      });
      expect(response.headers['access-control-allow-origin']).toBe('http://localhost:3000');
    }, HTTP_TEST_TIMEOUT);

    test('should return 404 for unknown routes', async () => {
      try {
        await axios.get(`${BASE_URL}/unknown-route`);
      } catch (error) {
        expect(error.response.status).toBe(404);
        expect(error.response.data).toMatchObject({ error: 'Not Found' });
      }
    }, HTTP_TEST_TIMEOUT);
  });

  test('should connect and disconnect a socket', async () => {
    expect(clientSocket.connected).toBe(true);

    const disconnectPromise = new Promise((resolve) => clientSocket.on('disconnect', resolve));
    clientSocket.disconnect();
    await disconnectPromise;

    expect(clientSocket.connected).toBe(false);
  }, SOCKET_TEST_TIMEOUT);



});