import { createServer } from 'http';
import { Server } from 'socket.io';

import { userManager } from './userManager.mjs';
import passportData from './passport.json' assert { type: 'json' };
import { verifyToken } from './jwt-clerk.mjs';

// Function to validate => token
const validateContentToken = async (token) => {
  try {
    return await verifyToken(token, passportData);
  } catch (error) {
    console.error('Token validation failed:', error.message);
    return null;
  }
};

const PORT = process.env.PORT || 3001;

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
        })
      );
      return;
    }

    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Not Found' }));
  });
};

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
  defaultStorage: 'postgres',
});

// Connection handler
io.use(async (socket, next) => {
  // Extract token from handshake auth
  const token = socket.handshake.auth.token;

  if (!token) {
    return next(new Error('Authentication required: Missing token'));
  }

  // Validate the token
  const decodedToken = await validateContentToken(token);
  if (!decodedToken) {
    return next(new Error('Authentication failed: Invalid token'));
  }

  // Attach decoded token to the socket for future use
  socket.decodedToken = decodedToken;

  // Proceed to the next middleware
  next();
});

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

  // Example: Handle custom events
  socket.on('sendMessage', async ({ recipientId, content }) => {
    try {
      const senderId = socket.decodedToken.userId;
      const message = await users.sendMessage(senderId, recipientId, content);
      console.log(`Message sent:`, message);
    } catch (error) {
      console.error('Error sending message:', error.message);
    }
  });
});

// Start server
const serverCallback = () => {
  console.log(`> Socket.IO server ready on http://0.0.0.0:${PORT}`);
  console.log(`> Health check: http://localhost:${PORT}/health`);
};

if (process.env.NODE_ENV !== 'test') {
  httpServer.listen(PORT, '0.0.0.0', serverCallback);
}

// Export everything needed for testing
export { io, httpServer, users };