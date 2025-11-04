import ClientIO from 'socket.io-client';
import {
  MESSAGE_ACKNOWLEDGEMENT_TIMEOUT
} from 'a-socket/config.mjs'

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
      reconnection: false,
      ackTimeout: MESSAGE_ACKNOWLEDGEMENT_TIMEOUT,  // Must match server
      pingTimeout: MESSAGE_ACKNOWLEDGEMENT_TIMEOUT,
      pingInterval: MESSAGE_ACKNOWLEDGEMENT_TIMEOUT / 2
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


export const sendMessageWaitEvent_old = async (socket, content, recipientId, timeoutMs = 5000) => {
  const result = new Promise((resolve, reject) => {
    socket.timeout(timeoutMs).emit('sendMessage', { recipientId, content }, (_, event_) => {
      if (_) return reject(_);

      const event = Array.isArray(event_) ? event_[0] : event_;
      return resolve(event.success ? event.result : event.error);
    });
    return
  });
  return result;
};


/**
 * Retries an asynchronous function until it succeeds or the timeout is reached.
 *
 * @param {Function} fn - The asynchronous function to retry.
 * @param {number} timeout - Total time (in milliseconds) to keep retrying.
 * @param {number} interval - Time (in milliseconds) to wait between retries.
 * @throws {Error} Throws an error if the function does not succeed within the timeout.
 */
export const retryWithTimeout = async (fn, timeout, interval) => {
  const start = Date.now(); // Record the start time

  while (Date.now() - start < timeout) {
    try {
      await fn(); // Attempt to execute the function
      return; // Success: exit the loop if the function resolves without errors
    } catch (error) {
      // Log the error for debugging purposes (optional)
      console.warn(`Retry failed: ${error.message}. Retrying in ${interval}ms...`);
    }

    // Wait for the specified interval before retrying
    await new Promise(resolve => setTimeout(resolve, interval));
  }

  // If the timeout is reached, throw an error
  throw new Error('Timeout waiting for condition');
};



export const sendMessageWaitEvent = async (socket, content, recipientId, timeoutMs = 5000) => {
  const result = await new Promise((resolve, reject) => {

    const ioTimeout = Math.min(timeoutMs - 100, 100);  // !50,
    try {
      socket.timeout(ioTimeout).emit('sendMessage', { recipientId, content, clientTimeout: timeoutMs }, (err, response) => {
        if (err) {
          // Socket.IO timeout or network error
          return reject(err);
        }

        const event = Array.isArray(response) ? response[0] : response;

        if (event.success === false) {
          // Server returned explicit error
          const error = new Error(event.error);
          error.code = 'SERVER_ERROR';
          return reject(error);
        }

        // Success case - return the message object directly
        return resolve(event.result);
      });
    } catch (error) {
      console.error(error);
    }
  });
  return result;
};