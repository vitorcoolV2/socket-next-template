import ClientIO from 'socket.io-client';

/**
 * Utility function to create and connect a client socket.
 * @param {string} baseUrl - The base URL of the server (e.g., `http://localhost:3001`).
 * @param {number} timeoutMs - Timeout in milliseconds for the connection (default: 5000ms).
 * @returns {Promise<Socket>} A promise that resolves to the connected socket.
 */
export const createClientSocket = (baseUrl, timeoutMs = 5000) => {
  return new Promise((resolve, reject) => {
    const clientSocket = ClientIO(baseUrl, {
      transports: ['websocket', 'polling'],
      forceNew: true,
      timeout: timeoutMs,
    });

    const timeout = setTimeout(() => {
      reject(new Error('Connection timeout'));
    }, timeoutMs);

    clientSocket.on('connect', () => {
      clearTimeout(timeout);
      console.log(clientSocket)
      resolve(clientSocket);
    });

    clientSocket.on('connect_error', (error) => {
      clearTimeout(timeout);
      reject(error);
    });
    clientSocket.on('user_authenticated', (user) => {
      console.log(user)
      clientSocket.user = Object.freeze(user);
    });
    /*clientSocket.on('user_authenticated', (user) => {
      console.log(user)
      Object.defineProperty(clientSocket, 'user', {
        get: () => user,
        configurable: false,
        enumerable: true,
      });

    });*/
  });
};


export const waitForEvent = (socket, eventName, timeoutMs = 5000) => {
  return Promise.race([
    new Promise((resolve) => socket.once(eventName, resolve)),
    new Promise((_, reject) =>
      setTimeout(() => reject(new Error(`Timeout waiting for event: ${eventName}`)), timeoutMs)
    ),
  ]);
};
