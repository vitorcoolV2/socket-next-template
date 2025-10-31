import { createServer } from 'http';
import { Server } from 'socket.io';
import pTimeout from 'p-timeout';
import { userManager } from './userManager/index.mjs';
import {
  SOCKET_MIDDLEWARE,
  INACTIVITY_CHECK_INTERVAL,
  INACTIVITY_THRESHOLD,
  MESSAGE_ACKNOWLEDGEMENT_TIMEOUT,
  DEFAULT_REQUEST_TIMEOUT,
  PUBLIC_MESSAGE_USER_ID
} from './config.mjs';

import { typingSchema } from 'a-socket/userManager/schemas.mjs';

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
  return createServer(rootMiddleware);
};

const rootMiddleware = (req, res) => {
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

const withTimeout = (promise, timeoutError = 'Request timed out', timeoutMs = 10000) => {
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      const timeoutId = setTimeout(() => {
        clearTimeout(timeoutId); // Clear the timeout to avoid memory leaks
        reject(new Error(timeoutError));
      }, timeoutMs);
    }),
  ]).catch(error => {
    console.error('Error in withTimeout:', error.message);
    throw error; // Rethrow the error after logging
  });
};

// Prevent predictable timeout exceptions from crashing the app
const catchTimeoutExceptions = (reason, promise) => {
  console.error('Unhandled Rejection at:', promise, 'reason:', reason);

  // Exit the process only for unexpected or critical errors
  if (!['Request timed out', 'Invalid data'].includes(reason.message)) {
    console.error('Critical error detected. Exiting process...');
    process.exit(1);
  } else {
    console.warn('Predictable error detected. Continuing execution...');
  }
};

process.on('unhandledRejection', catchTimeoutExceptions);


const _registerEventHandlers = (socket, handlers) => {
  Object.entries(handlers).forEach(([eventName, eventHandler, eventAck, timeout]) => {
    registerEventHandler(socket, { eventName, eventHandler, eventAck, timeout });
  });
};

/**
 * Registers a single event handler with customizable properties.
 *
 * @param {Socket} socket - The Socket.IO socket instance.
 * @param {Object} options - Event handler configuration.
 * @param {string} options.eventName - The name of the event.
 * @param {Function} options.eventHandler - The function to handle the event.
 * @param {boolean} [options.eventAck=false] - Whether the event requires acknowledgment.
 * @param {number} [options.timeout=10000] - Timeout duration in milliseconds.
 */
const registerEventHandler = (socket, { eventName, eventHandler, eventAck = false, timeout = DEFAULT_REQUEST_TIMEOUT }) => {
  socket.on(eventName, createEventHandler(eventName, eventHandler, eventAck, timeout));
};

/**
 * Creates a wrapper for an event handler with validation, timeout, and acknowledgment support.
 *
 * @param {string} eventName - The name of the event.
 * @param {Function} eventHandler - The function to handle the event.
 * @param {boolean} eventAck - Whether the event requires acknowledgment.
 * @param {number} timeout - Timeout duration in milliseconds.
 * @returns {Function} - The wrapped event handler function.
 */
function createEventHandler(eventName, eventHandler, eventAck = false, timeout = 10000) {
  return async function (data, callback) {
    // Step 1: Validate input data
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
      // Step 2: Retrieve user information
      const user = await users.getUserBySocketId(this.id);
      console.info('>>> ', [eventName], 'user:', [user?.state, user?.userId]);

      // Step 3: Execute the event handler with a timeout
      const result = await withTimeout(
        eventHandler(this, data, callback),
        'Request timed out',
        timeout
      );

      // Step 4: Handle successful response
      const successResponse = {
        success: true,
        event: eventName,
        result
      };

      // If acknowledgment is required, ensure the callback is called
      if (eventAck && typeof callback === 'function') {
        callback(successResponse);
      } else {
        _respondOrFallback(callback, this, successResponse);
      }

      return result;
    } catch (error) {
      // Step 5: Log and handle errors
      console.error('>>> ', `[${eventName}]`, 'Error:', error.message);
      users._incrementErrors();

      const errorResponse = {
        success: false,
        event: eventName,
        error: error.message
      };

      // If acknowledgment is required, ensure the callback is called
      if (eventAck && typeof callback === 'function') {
        callback(errorResponse);
      } else {
        _respondOrFallback(callback, this, errorResponse);
      }

      // Step 6: Re-throw only unexpected or critical errors
      if (!['Request timed out', 'Invalid data'].includes(error.message)) {
        throw error;
      }
    }
  };
}

// Utility function to handle responses or fallbacks
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
      const authenticatedUsers = await users.getUsersList(socket.id, { states: ['authenticated', 'offline'] });
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
      console.log(`User ${socket.user?.userName} (${socket.user?.userId}) disconnected`);
    }).catch((error) => {
      console.error(`Error during disconnect: ${error.message}`);
    });
  });

  const TEST_DISABLE_ACK = process.env.NODE_ENV === 'test';
  // Helper function to update message status

  const handlers = {
    // UI typing
    typing: async (socket, data) => {
      //const ret = await users.typingIndicator(socket.id, { isTyping: true, recipientId: data?.recipientId });
      const emitSockets = await users.getUserSockets(data.recipientId);
      (emitSockets || []).forEach((sock) => {
        io.to(sock.socketId).emit('typing', data?.recipientId);
      });

    },
    stopTyping: async (socket, data) => {
      //const ret = await users.typingIndicator(socket.id, { isTyping: false, recipientId: data?.recipientId });
      const emitSockets = await users.getUserSockets(data.recipientId);
      (emitSockets || []).forEach((sock) => {
        io.to(sock.socketId).emit('stopTyping', data?.recipientId);
      });
    },


    markMessagesAsRead: async (socket, options) => {
      const resp = await users.markMessagesAsRead(socket.id, options);

      const emitSockets = await users.getUserSockets(resp.recipientId);

      // If no sockets to emit to, mark it with pending and return
      if (!emitSockets || emitSockets.length === 0) {
        console.log(`No active sockets for recipient ${recipientId}, marking as pending`);
        // the will bewill notify pending bellow after trying to deliver to recipient and fail
        io.to(socket.id).emit('receivedMessage', { ...msg, direction: 'outgoing' });
        emitSockets.forEach(sock => {
          io.to(sock.socketId).emit('receivedMessage', { ...msg, direction: 'incoming' })
        });
        return msg;
      } else {
        // notify without ack, recipient on pending message. will try bellow to formal deliver and acknolege
        emitSockets.forEach(sock => {
          io.to(sock.socketId).emit('receivedMessage', { ...msg, direction: 'incoming' });
        });
      }
    },
    getPublicMessages: async (socket) =>
      await users.getPublicMessages(socket.id),
    broadcastPublicMessage: async (socket, { content }) =>
      await users.broadcastPublicMessage(socket.id, content),
    // Complete server socket handler for getUserConversation

    getUsersList: async (socket, options) => {
      await users.getUsersList(socket.id, options).then(res => {
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
    getUserConversation: async (socket, options) => {
      try {
        // Call the user service to get conversation messages
        const conversationData = await users.getUserConversation(socket.id, options);

        // Emit the conversation data back to the client
        socket.emit('userConversation', {
          success: true,
          data: {
            messages: conversationData.messages.map(msg => ({
              id: msg.id,
              senderId: msg.senderId,
              recipientId: msg.recipientId,
              content: msg.content,
              timestamp: msg.timestamp,
              status: msg.status,
              type: msg.type,
              direction: msg.direction
            })),
            total: conversationData.total,
            hasMore: conversationData.hasMore,
            context: conversationData.context || null
          },
          options: options // Echo back the options for client reference
        });

        console.log(`Sent ${conversationData.messages.length} messages to user ${socket.id} for conversation with ${options.otherPartyId}`);

      } catch (error) {
        console.error('Error in getUserConversation:', error);

        // Emit error back to client
        socket.emit('userConversation', {
          success: false,
          error: error.message || 'Failed to fetch conversation',
          options: options
        });
      }
    },

    getUserConversationsList: async (socket, options) => {
      try {
        await users.getUserConversationsList(socket.id, options).then(res => {
          socket.emit('userConversationsList', {
            success: true,
            data: res.map(u => ({
              userId: u.userId,
              userName: u.userName,
              otherPartyId: u.otherPartyId,
              otherPartyName: u.otherPartyName,
              startedAt: u.startedAt,
              lastMessageAt: u.lastMessageAt,
              incoming: u.incoming,
              outgoing: u.outgoing
            }))
          });
        });
      } catch (error) {
        console.error('Error in getUserConversationsList:', error);
        socket.emit('getUserConversationsList', {
          success: false,
          error: error.message || 'Failed to fetch conversations list'
        });
      }
    },
  };
  _registerEventHandlers(socket, handlers);


  const sendMessageHandler = async (socket, { recipientId, content }) => {
    let msg;
    try {
      // Step 1: Validate input
      if (!recipientId || !content) {
        throw new Error('Recipient ID and message content are required.');
      }

      // Step 2: define support for inner functions
      // Create | persisted message with "sent" status
      msg = await users.sendMessage(socket.id, recipientId, content);
      // Normalize emitSockets for notify* func*
      const emitSockets = (await users.getUserSockets(recipientId)) || [];



      // Notify sender and recipient of the "sent" message
      // only the sender sends a message. 
      //          - the sender upon sending he has a new "outgoing" message. 
      //          - the receiver, receive the "incoming" message.
      const notifyMessage = (emitName, status) => {
        io.to(socket.id).emit(emitName, { ...msg, status, direction: "outgoing" });
        emitSockets.forEach(sock => {
          io.to(sock.socketId).emit(emitName, { ...msg, status, direction: "incoming" });
        });
      };

      /// >>>>>>>> ACTION START HEAR

      // 1. Notify "sent" status
      notifyMessage('receivedMessage', 'sent');  //+ means server receive message and persisted for async delivery

      const updateMessageAndNotify = async (status) => {
        console.log(status);
        console.log(`Updating message status to "${status}" for messageId: ${msg.messageId}`);
        const updateMsg = await users.updateMessageStatus(socket.id, msg.messageId, status);

        notifyMessage('updateMessageStatus', updateMsg.status);
        return updateMsg;
      };

      // 2: Update message status to "pending"
      try {
        msg = await updateMessageAndNotify('pending');
      } catch (error) {
        notifyMessage('updateMessageStatus', 'error');
        return msg;
      }


      // 3: Attempt delivery with timeout handling


      console.log(`Attempting delivery to ${emitSockets.length} socket(s)`);

      const deliveryAttempts = emitSockets.map(async (sockId) => {
        try {
          const result = await withTimeout(
            new Promise((resolve) => {
              const deliveryMsg = { ...msg, direction: 'incoming', status: 'delivery' };
              io.to(sockId).emit('receiveMessage', deliveryMsg, (ack) => {
                if (!TEST_DISABLE_ACK && ack === 'received') {
                  console.log(`Acknowledgment received from socket ${sockId}`);
                  resolve(sockId);
                } else {
                  console.log(`Acknowledgment failed from socket ${sockId}`);
                  resolve({ sockId, success: false });
                }
              });
            }, 'Timeout - fail to ACK recipient delivery')
          );
          return result;
        } catch (error) {
          console.log(`Delivery timeout for socket ${sockId}`);
          return { sockId, success: false, reason: 'timeout' };
        }
      });

      const results = await Promise.all(deliveryAttempts);
      const successfulDeliveries = results.filter(result => typeof result === 'string');

      console.log(`Delivery completed: ${successfulDeliveries.length}/${emitSockets.length} successful`);

      // Step 5: Update message status based on delivery results
      if (successfulDeliveries.length > 0) {
        msg = await updateMessageAndNotify('delivered');
      } else {
        // not persisting invalid server state. but can notify the client of a error on delivering with ACK          
        notifyMessage('updateMessageStatus', 'error');
      }

      return msg;
    } catch (error) {
      console.error('Error in sendMessage:', error.message);

      // Handle critical errors (e.g., missing recipient ID or content)
      if (error.message.includes('Recipient ID') || error.message.includes('content')) {
        throw error; // Re-throw critical errors
      }

      // For non-critical errors (e.g., delivery failures), return gracefully
      console.error('Delivery error, returning message as pending');
      return { ...msg, status: 'pending', error: error.message };
    }
  }
  // Register 'sendMessage' event
  registerEventHandler(socket, {
    eventName: 'sendMessage',
    eventHandler: sendMessageHandler,
    eventAck: true, // No acknowledgment required
    timeout: MESSAGE_ACKNOWLEDGEMENT_TIMEOUT // 10 seconds
  });

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