import { createServer } from 'http';
import { Server } from 'socket.io';
import { userManager } from './userManager/index.mjs';

// Allowed origins for CORS
export const allowedOrigins = [
  process.env.CLIENT_URL || 'http://localhost:3000',
  'http://localhost:3000',
  'http://127.0.0.1:3000',
];

// Create HTTP server
export const createHttpServer = () => {
  return createServer((req, res) => {
    const origin = req.headers.origin;
    if (allowedOrigins.includes(origin)) {
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
          message: 'Socket.IO server is running',
          timestamp: new Date().toISOString(),
          metrics: users.getConnectionMetrics(),
        })
      );
      return;
    }

    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Not Found' }));
  });
};

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
  pingInterval: 10000 * 2,
  pingTimeout: 5000 * 2,
});

// Initialize user manager
const users = userManager({
  io,
  defaultStorage: process.env.DEFAULT_STORAGE || 'memory', // Default to 'memory' if not specified
  maxTotalConnections: parseInt(process.env.MAX_TOTAL_CONNECTIONS, 10) || 1000, // Default to 1000
});



// Event handler wrapper with validation
function createEventHandler(eventName, eventHandler) {
  return async function (data, callback) {
    try {
      const user = users.getUserBySocketId(this.id);
      console.info('>>> ', [eventName], 'user:', [user?.state, user?.socketId]);

      const result = await eventHandler(this, data, callback);
      const successResponse = { success: true, event: eventName, data: result };
      respondOrFallback(callback, this, successResponse);

      return result;
    } catch (error) {
      console.error('>>> ', `[${eventName}]`, 'Error:', error.message);
      users.incrementErrors();

      const errorResponse = { success: false, event: eventName, error: error.message };
      respondOrFallback(callback, this, errorResponse);

      throw error;
    }
  };
}

// Helper function to send responses or fallback
function respondOrFallback(callback, socket, response) {
  if (typeof callback === 'function') {
    callback(response);
  } else {
    socket.emit('response', response);
  }
}

// Connection handler
io.on('connection', (socket) => {
  console.log(`User connected with socketId: ${socket.id}`);

  // Add user to userManager
  const userData = {
    userId: socket.decodedToken.userId, // Extract userId from decoded token
    userName: socket.decodedToken.userName || 'Anonymous',
  };

  users.addUser(socket.id, userData).then((user) => {
    console.log(`User ${user.userName} (${user.userId}) added to userManager`);
  });

  // Handle disconnection
  socket.on('disconnect', () => {
    users.disconnectUser(socket.id).then((user) => {
      console.log(`User ${user?.userName} (${user?.userId}) disconnected`);
    });
  });

  // Handle sendMessage event
  socket.on(
    'sendMessage',
    createEventHandler('sendMessage', async (socket, { recipientId, content }) => {
      const senderId = socket.decodedToken.userId;
      return await users.sendMessage(senderId, recipientId, content);
    })
  );

  // Handle typingIndicator event
  socket.on(
    'typingIndicator',
    createEventHandler('typingIndicator', async (socket, data) => {
      return await users.typingIndicator(socket.id, data);
    })
  );

  // Handle markMessagesAsRead event
  socket.on(
    'markMessagesAsRead',
    createEventHandler('markMessagesAsRead', async (socket, options) => {
      return await users.markMessagesAsRead(socket.id, options);
    })
  );

  // Handle getPublicMessages event
  socket.on(
    'getPublicMessages',
    createEventHandler('getPublicMessages', async (socket) => {
      return await users.getPublicMessages(socket.id);
    })
  );
});

// Cleanup intervals
setInterval(() => {
  const cleanedMessages = users.cleanupOldMessages();
  if (cleanedMessages > 0) {
    console.log(`Cleaned up ${cleanedMessages} old messages`);
  }
}, 60 * 60 * 1000);

// Start server
const startServer = () => {
  const PORT = process.env.PORT || 3001;
  httpServer.listen(PORT, '0.0.0.0', () => {
    console.log(`> Socket.IO server ready on http://0.0.0.0:${PORT}`);
    console.log(`> Health check: http://localhost:${PORT}/health`);
  });
};

if (process.env.NODE_ENV !== 'test') {
  startServer();
}

// Export everything needed for testing
export { io, httpServer, users, createEventHandler, respondOrFallback };