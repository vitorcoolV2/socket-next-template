import { createServer } from 'http';
import { Server } from 'socket.io';
import {
  SOCKET_MIDDLEWARE,
  INACTIVITY_CHECK_INTERVAL,
  INACTIVITY_THRESHOLD,
  MESSAGE_ACKNOWLEDGEMENT_TIMEOUT,
  PUBLIC_MESSAGE_USER_ID,
  allowedOrigins,
} from './config.mjs';


import { catchTimeoutExceptions } from './utils.mjs';


import {
  getUsersListHandler,
  getUserConversationHandler,
  getUserConversationsListHandler,
  sendMessageHandler,
  markMessagesAsReadHandler,
  markMessagesAsDeliveredHandler,
} from './handlers/index.mjs';


import { rootMiddleware } from 'a-socket/middleware-root.mjs';
import authMiddleware from 'a-socket/middleware-auth.mjs';
const auth_middleware = authMiddleware[SOCKET_MIDDLEWARE];


// Initialize user manager first to avoid circular dependencies
import { users as usersInstance } from 'a-socket/db.mjs';

export const users = usersInstance;

// Create HTTP server
const createHttpServer = () => {
  return createServer(rootMiddleware);
};


process.on('unhandledRejection', catchTimeoutExceptions);
import {
  registerEventHandler,
  registerEventHandlers,
} from './event-utils.mjs'



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

io.use(async (socket, next) => {
  try {
    const pendingMessages = await users.getPendingMessages(socket.id);
    const { hasMore, messages, total } = pendingMessages;

    if (!hasMore && messages.length === 0) {
      return next();
    }

    messages.forEach(msg => {
      socket.emit('update_message_status', msg, (_, ack) => {
        console.log(_, ack);
      });
    });

    const messageIds = messages.map(m => m.id);
    const result = await users.markMessagesAsDelivered(socket.id, {
      messageIds,
    });

    next();
  } catch (error) {
    // Handle any errors that occur during the process
    console.error(`Middleware error: ${error.message}`);
    next(new Error('Internal server error'));
  }
})

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
    getPublicMessages: async (socket) =>
      await users.getPublicMessages(socket.id),
    broadcastPublicMessage: async (socket, { content }) => {
      const msg = await users.broadcastPublicMessage(socket.id, content);
      // Broadcast the message to all connected users
      io.emit('public_message', { ...msg, direction: 'incoming' });
      if (debug) {
        console.log(`User ${msg.userId} broadcasted public message:`, msg);
      }
      return msg
    },
    getUserConnectionMetrics: async (socket, userId) =>
      await users.getUserConnectionMetrics(userId),
    getAndDeliverPendingMessages: async (socket) =>
      await users.getPendingMessages(socket.id),

  };
  registerEventHandlers(socket, handlers);

  // Register 'sendMessage' event
  registerEventHandler(socket, { eventName: 'getUsersList', eventHandler: getUsersListHandler, });
  registerEventHandler(socket, { eventName: 'getUserConversationsList', eventHandler: getUserConversationsListHandler, });
  registerEventHandler(socket, { eventName: 'getUserConversation', eventHandler: getUserConversationHandler, });
  registerEventHandler(socket, { eventName: 'markMessagesAsRead', eventHandler: markMessagesAsReadHandler, });
  registerEventHandler(socket, { eventName: 'markMessagesAsDelivered', eventHandler: markMessagesAsDeliveredHandler, });
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
};