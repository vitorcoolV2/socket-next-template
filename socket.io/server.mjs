import { createServer } from 'http';
import { Server } from 'socket.io';
import pTimeout from 'p-timeout';
import { userManager } from 'a-socket/userManager/index.mjs';
import {
  SOCKET_MIDDLEWARE,
  INACTIVITY_CHECK_INTERVAL,
  INACTIVITY_THRESHOLD,
  MESSAGE_ACKNOWLEDGEMENT_TIMEOUT,
  PUBLIC_MESSAGE_USER_ID
} from './config.mjs';

import authMiddleware from 'a-socket/middleware-auth.mjs';

const auth_middleware = authMiddleware[SOCKET_MIDDLEWARE];

// Allowed origins for CORS
export const allowedOrigins = [
  process.env.CLIENT_URL || 'http://localhost:3000',
  'http://localhost:3000',
  'http://127.0.0.1:3000',
];

// Initialize user manager first to avoid circular dependencies
export const users = userManager({
  io: null, // Will be set after io initialization
  defaultStorage: process.env.USER_MANAGER_PERSIST || 'memory',
  maxTotalConnections: parseInt(process.env.MAX_TOTAL_CONNECTIONS, 10) || 1000,
});

// Create HTTP server
const createHttpServer = () => {
  return createServer(requestLogger);
};

const requestLogger = (req, res) => {
  if (!req || !res) {
    throw new Error('Invalid request or response object');
  }

  console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);

  // Handle CORS
  const origin = req.headers?.origin;
  if (origin && allowedOrigins.includes(origin)) {
    res.setHeader('Access-Control-Allow-Origin', origin);
  }

  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('Access-Control-Allow-Credentials', 'true');

  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }

  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(
      JSON.stringify({
        status: 'ok',
        message: 'Server is running',
        timestamp: new Date().toISOString(),
        metrics: users.getConnectionMetrics(),
      })
    );
    return;
  }

  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Not Found' }));
};

// Event handler wrapper with validation
function _createEventHandler(eventName, eventHandler) {
  return async function (data, callback) {
    if (!data || typeof data !== 'object') {
      const errorResponse = {
        success: false,
        event: eventName,
        error: 'Invalid data'
      };
      _respondOrFallback(callback, this, errorResponse);
      return;
    }

    try {
      const user = await users.getUserBySocketId(this.id);
      console.info('>>> ', [eventName], 'user:', [user?.state, user?.userId]);

      const result = await Promise.race([
        eventHandler(this, data, callback),
        new Promise((_, reject) =>
          setTimeout(() => reject(new Error('Request timed out')), 10000)
        ),
      ]);

      const successResponse = {
        success: true,
        event: eventName,
        data: result
      };
      _respondOrFallback(callback, this, successResponse);

      return result;
    } catch (error) {
      console.error('>>> ', `[${eventName}]`, 'Error:', error.message);
      users._incrementErrors();

      const errorResponse = {
        success: false,
        event: eventName,
        error: error.message
      };
      _respondOrFallback(callback, this, errorResponse);

      // Only re-throw if it's not a timeout or client error
      if (!error.message.includes('timeout') && !error.message.includes('Invalid')) {
        throw error;
      }
    }
  };
}

const _registerEventHandlers = (socket, handlers) => {
  Object.entries(handlers).forEach(([eventName, eventHandler, eventAck]) => {
    socket.on(eventName, _createEventHandler(eventName, eventHandler, eventAck));
  });
};

// Helper function to send responses or fallback
function _respondOrFallback(callback, socket, response) {
  if (typeof callback === 'function') {
    callback(response);
  } else {
    socket.emit('response', response);
  }
}

// Initialize HTTP server
const httpServer = createHttpServer();

// Initialize Socket.IO
const io = new Server(httpServer, {
  cors: {
    origin: (origin, callback) => {
      if (!origin || allowedOrigins.includes(origin)) {
        callback(null, true);
      } else {
        callback(new Error('Not allowed by CORS'));
      }
    },
    methods: ['GET', 'POST'],
    credentials: true,
  },
  transports: ['websocket', 'polling'],
  ackTimeout: 10000,
  pingInterval: 20000, // 20 seconds
  pingTimeout: 15000,  // 10 seconds TODO put it on config.mjs 
});

// Update user manager with io instance
users.setIO(io);

// Apply middleware
io.use(auth_middleware);

io.use(async (socket, next) => {
  try {
    // Check if the user is authenticated
    if (socket.user && socket.user.state === 'authenticated') {
      // Add the user to userManager
      const user = await users.storeUser(socket.id, socket.user, true);
      console.log(`User ${user.userName} (${user.userId}) added to userManager`);

      // Emit an event to notify the client of successful authentication
      socket.emit('user_authenticated', {
        success: true,
        userId: user.userId,
        userName: user.userName,
      });

      // Join the public message room
      socket.join(PUBLIC_MESSAGE_USER_ID);

      // Fetch and join rooms for all authenticated users
      const authenticatedUsers = await users.getUsers(socket.id, { states: ['authenticated', 'offline'] });
      authenticatedUsers.forEach((u) => {
        socket.join(u.userId);
      });

      // Proceed to the next middleware
      next();
    } else {
      // Deny connection for unauthenticated users
      console.error('Unauthenticated user attempted to connect');
      next(new Error('Authentication required'));
    }
  } catch (error) {
    // Handle any errors that occur during the process
    console.error(`Middleware error: ${error.message}`);
    next(new Error('Internal server error'));
  }
});

// Connection handler
io.on('connection', (socket) => {
  console.log(`User connected with socketId: ${socket.id}`);

  // Handle disconnection
  socket.on('disconnect', (reason) => {
    console.log(`User ${socket.id} disconnected: ${reason}`);
    users.disconnectUser(socket.id).then((user) => {
      console.log(`User ${user?.userName} (${user?.userId}) disconnected`);
    }).catch((error) => {
      console.error(`Error during disconnect: ${error.message}`);
    });
  });


  const handlers = {
    sendMessage: async (socket, { recipientId, content }) => {
      try {
        // Step 1: Validate input
        if (!recipientId || !content) {
          throw new Error('Recipient ID and message content are required.');
        }

        // Step 2: Create and persist the message
        const message = await users.sendMessage(socket.id, recipientId, content);
        const { emitSockets, ...msg } = message;

        // Helper function to update message status
        const updateMessageStatus = async (status) => {
          console.log(`Updating message status to "${status}" for messageId: ${msg.messageId}`);
          await users.updateMessageStatus(recipientId, msg.messageId, status);
          msg.status = status;
          io.to(socket.id).emit('messageStatusUpdate', msg);
        };

        // If no sockets to emit to, mark as pending and return
        if (!emitSockets || emitSockets.length === 0) {
          console.log(`No active sockets for recipient ${recipientId}, marking as pending`);
          await updateMessageStatus('pending');
          return msg;
        }

        // Simple timeout function
        const withTimeout = (promise, timeoutMs = 10000) => {
          return Promise.race([
            promise,
            new Promise((_, reject) =>
              setTimeout(() => reject(new Error('timeout')), timeoutMs)
            )
          ]);
        };

        // Attempt delivery with simple timeout handling
        console.log(`Attempting delivery to ${emitSockets.length} socket(s)`);

        const deliveryAttempts = emitSockets.map(async (sockId) => {
          try {
            const result = await withTimeout(
              new Promise((resolve, reject) => {
                io.to(sockId).emit('receiveMessage', msg, (ack) => {
                  if (ack === 'received') {
                    console.log(`Acknowledgment received from socket ${sockId}`);
                    resolve(sockId);
                  } else {
                    console.log(`Acknowledgment failed from socket ${sockId}`);
                    resolve({ sockId, success: false });
                  }
                });
              }),
              10000 // 10 second timeout
            );
            return result;
          } catch (error) {
            console.log(`Delivery timeout for socket ${sockId}`);
            return { sockId, success: false, reason: 'timeout' };
          }
        });

        // Wait for all attempts
        const results = await Promise.all(deliveryAttempts);

        const successfulSockets = results.filter(result =>
          typeof result === 'string' // successful deliveries return socket ID string
        );

        console.log(`Delivery completed: ${successfulSockets.length}/${emitSockets.length} successful`);

        if (successfulSockets.length > 0) {
          await updateMessageStatus('delivered');
        } else {
          await updateMessageStatus('pending');
        }

        return msg;

      } catch (error) {
        console.error('Error in sendMessage:', error.message);
        // Only throw for critical errors
        if (error.message.includes('Recipient ID') || error.message.includes('content')) {
          throw error;
        }
        // For delivery errors, return gracefully
        console.error('Delivery error, returning message as pending');
        return { ...msg, status: 'pending', error: error.message };
      }
    },
    sendMessage3: async (socket, { recipientId, content }) => {
      try {
        // Step 1: Validate input
        if (!recipientId || !content) {
          throw new Error('Recipient ID and message content are required.');
        }

        // Step 2: Create and persist the message
        const message = await users.sendMessage(socket.id, recipientId, content);
        const { emitSockets, ...msg } = message;

        // Helper function to update message status
        const updateMessageStatus = async (status) => {
          console.log(`Updating message status to "${status}" for messageId: ${msg.messageId}`);
          await users.updateMessageStatus(recipientId, msg.messageId, status);
          msg.status = status;

          // Notify the sender about the status update
          io.to(socket.id).emit('messageStatusUpdate', msg);
        };

        const acknowledgmentPromises = emitSockets.map((sockId) =>
          pTimeout(
            new Promise((resolve, reject) => {
              io.to(sockId).emit('receiveMessage', msg, (ack) => {
                if (ack === 'received') {
                  resolve(sockId); // Resolve with the socket ID
                } else {
                  console.error(new Error(`Acknowledgment failed for socket ${sockId} - ${ack.message}`));
                  resolve(null);
                }
              });
            }),
            MESSAGE_ACKNOWLEDGEMENT_TIMEOUT,
            `Acknowledgment timed out for socket ${sockId}`
          )
        );

        const [successfulSockets, errors] = await Promise.allSettled(acknowledgmentPromises).then((results) => {
          const successes = results
            .filter((result) => result.status === 'fulfilled')
            .map((result) => result.value);
          const failures = results
            .filter((result) => result.status === 'rejected')
            .map((result) => result.reason);
          return [successes, failures];
        });

        if (successfulSockets.length > 0) {
          console.log(`Acknowledgments received from sockets: ${successfulSockets.join(', ')}`);
          await updateMessageStatus('delivered');
        } else {
          console.error('All acknowledgments failed or timed out:', errors.map((err) => err.message));
          await updateMessageStatus('pending');
        }

        // Return the final message details
        return msg;
      } catch (error) {
        console.error('Error sending message:', error.message);
        throw error; // Re-throw the error for upstream handling
      }
    },
    sendMessage2: async (socket, { recipientId, content }) => {
      try {
        // Step 1: Validate input
        if (!recipientId || !content) {
          throw new Error('Recipient ID and message content are required.');
        }

        // Step 2: Create and persist the message
        const message = await users.sendMessage(socket.id, recipientId, content);
        const { emitSockets, ...msg } = message;

        // Helper function to update message status
        const updateMessageStatus = async (status) => {
          console.log(`Updating message status to "${status}" for messageId: ${msg.messageId}`);
          await users.updateMessageStatus(recipientId, msg.messageId, status);
          msg.status = status;

          // Notify the sender about the status update
          io.to(socket.id).emit('messageStatusUpdate', msg);
        };

        const acknowledgmentPromises = emitSockets.map((sockId) =>
          pTimeout(
            new Promise((resolve, reject) => {
              io.to(sockId).emit('receiveMessage', msg, (ack) => {
                if (ack === 'received') {
                  resolve(sockId); // Resolve with the socket ID
                } else {
                  reject(new Error(`Acknowledgment failed for socket ${sockId} - ${ack.message}`));
                }
              });
            }),
            MESSAGE_ACKNOWLEDGEMENT_TIMEOUT,
            `Acknowledgment timed out for socket ${sockId}`
          )
        );

        const [successfulSockets, errors] = await Promise.allSettled(acknowledgmentPromises).then((results) => {
          const successes = results
            .filter((result) => result.status === 'fulfilled')
            .map((result) => result.value);
          const failures = results
            .filter((result) => result.status === 'rejected')
            .map((result) => result.reason);
          return [successes, failures];
        });

        if (successfulSockets.length > 0) {
          console.log(`Acknowledgments received from sockets: ${successfulSockets.join(', ')}`);
          await updateMessageStatus('delivered');
        } else {
          console.error('All acknowledgments failed or timed out:', errors.map((err) => err.message));
          await updateMessageStatus('pending');
        }

        // Return the final message details
        return msg;
      } catch (error) {
        console.error('Error sending message:', error.message);
        throw error; // Re-throw the error for upstream handling
      }
    },
    sendMessage2: async (socket, { recipientId, content }) => {
      try {
        // Step 1: Create the message
        const message = await users.sendMessage(socket.id, recipientId, content);
        const { emitSockets, ...msg } = message; // Extract sockets and message details

        // Helper function to update message status
        const updateStatus = async (status) => {
          console.log(`Updating message status to "${status}" for messageId: ${msg.messageId}`);
          await users.updateMessageStatus(socket.user.userId, msg.messageId, status);
          msg.status = status;
        };

        // Step 2: Send the message to recipients and handle acknowledgments
        const acknowledgmentPromises = (message?.emitSockets || []).map((sockId) => {
          console.log('to', sockId, 'emit', 'receiveMessage', msg);

          // Return a Promise for each socket's acknowledgment
          return new Promise((resolve, reject) => {
            const timeout = setTimeout(() => {
              reject(new Error(`Acknowledgment timed out for socket ${sockId}`));
            }, 10000); // 10-second timeout

            io.to(sockId).emit('receiveMessage', msg, (ack) => {
              clearTimeout(timeout);
              if (ack === 'received') {
                console.log(`Message acknowledged by socket ${sockId}`);
                resolve(sockId); // Resolve with the socket ID that acknowledged
              } else {
                console.error(`Acknowledgment failed for socket ${sockId}`);
                reject(new Error(`Acknowledgment failed for socket ${sockId}`));
              }
            });
          });
        });

        // Add a timeout promise to handle cases where no acknowledgment is received
        const timeoutPromise = new Promise((_, reject) => {
          setTimeout(() => {
            reject(new Error('All acknowledgments timed out'));
          }, 15000); // 15-second global timeout
        });

        // Step 3: Wait for the first successful acknowledgment or timeout
        let acknowledgedSocket;
        try {
          acknowledgedSocket = await Promise.race([...acknowledgmentPromises, timeoutPromise]);
          console.log(`First acknowledgment received from socket: ${acknowledgedSocket}`);
          await updateStatus('delivered'); // Update status to 'delivered'
        } catch (error) {
          console.error('Acknowledgment failed or timed out:', error.message);
          await updateStatus('pending'); // Update status to 'pending'
        }

        return msg;
      } catch (error) {
        console.error('Error sending message:', error.message);
        throw error; // Re-throw the error for upstream handling
      }
    },

    // UI
    typing: async (socket, data) => {
      const ret = await users.typingIndicator(socket.id, { isTyping: true, recipientId: data?.recipientId });
      (ret?.emitSockets || []).forEach((sockId) => {
        io.to(sockId).emit('typing', data?.recipientId);
      });

    },
    stopTyping: async (socket, data) => {
      const ret = await users.typingIndicator(socket.id, { isTyping: false, recipientId: data?.recipientId });
      (ret?.emitSockets || []).forEach((sockId) => {
        io.to(sockId).emit('stopTyping', data?.recipientId);
      });
    },
    //
    typingIndicator: async (socket, data) =>
      await users.typingIndicator(socket.id, data),
    markMessagesAsRead: async (socket, options) =>
      await users.markMessagesAsRead(socket.id, options),
    getPublicMessages: async (socket) =>
      await users.getPublicMessages(socket.id),
    broadcastPublicMessage: async (socket, { content }) =>
      await users.broadcastPublicMessage(socket.id, content),
    getMessageHistory: async (socket, options) =>
      await users.getMessageHistory(socket.id, options),
    getUsers: async (socket, options) => {
      await users.getUsers(socket.id, options).then(res => {
        socket.emit('usersList', res.map(u => {
          return {
            userId: u.userId,
            userName: u.userName,
            state: u.state,
          }
        }));
      });
    },
    getActiveUsers: async (socket, options) =>
      await users.getActiveUsers(socket.id, options),
    getUserConnectionMetrics: async (socket, userId) =>
      await users.getUserConnectionMetrics(userId),
    getAndDeliverPendingMessages: async (socket) =>
      await users.getAndDeliverPendingMessages(socket.id),
  };

  _registerEventHandlers(socket, handlers);
});

// Cleanup intervals
setInterval(() => {
  // Example cleanup - implement this method in userManager
  users.cleanupOldMessages?.().then((cleanedCount) => {
    if (cleanedCount > 0) {
      console.log(`Cleaned up ${cleanedCount} old messages`);
    }
  }).catch((error) => {
    console.error(`Cleanup error: ${error.message}`);
  });
}, 60 * 60 * 1000); // Every hour

// Graceful shutdown
const gracefulShutdown = () => {
  console.log('Received shutdown signal, closing server...');

  httpServer.close((err) => {
    if (err) {
      console.error('Error during server shutdown:', err);
      process.exit(1);
    }

    console.log('Server closed successfully');
    process.exit(0);
  });

  // Force close after 10 seconds
  setTimeout(() => {
    console.log('Forcing server shutdown');
    process.exit(1);
  }, 10000);
};

process.on('SIGTERM', gracefulShutdown);
process.on('SIGINT', gracefulShutdown);

// Start server
// Export the start/stop functions
export const startServer = () => {
  const PORT = process.env.PORT || 3001;
  return new Promise((resolve, reject) => {
    httpServer.listen(PORT, '0.0.0.0', (err) => {
      if (err) {
        reject(err);
        return;
      }
      console.log(`> Socket.IO server ready on http://0.0.0.0:${PORT}`);
      console.log(`> Health check: http://localhost:${PORT}/health`);
      resolve(io);
    });
  });
};

export const stopServer = () => {
  return new Promise((resolve) => {
    if (httpServer.listening) {
      httpServer.close(() => {
        console.log('Server stopped');
        resolve();
      });
    } else {
      resolve();
    }
  });
};

if (process.env.NODE_ENV !== 'test') {
  startServer();
}

// Export everything needed for testing
export {
  io,
  createHttpServer,
  INACTIVITY_CHECK_INTERVAL,
  INACTIVITY_THRESHOLD,

  //httpServer,
  //requestLogger,
  //createHttpServer,
  //users,
  //_createEventHandler,
  //_respondOrFallback
};