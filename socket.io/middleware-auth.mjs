import { verifyToken } from './jwt-passport/index.mjs';
import { PASSPORT_PATH, debug } from './config.mjs';

// Load passport data dynamically
const loadPassportData = async () => {
  if (PASSPORT_PATH) {
    try {
      return await import(PASSPORT_PATH, { with: { type: 'json' } }).then((module) => module.default);
    } catch (error) {
      throw error;
    }
  } else {
    throw new Error('Passport configuration is missing');
  }
};

// Token validation function
const validateContentToken = async (token) => {
  const passport = await loadPassportData();

  const result = await verifyToken(token, passport);
  return result && result.valid ? Object.freeze(result) : false;
};

/**
 * Passport Middleware
 * Authenticates the user and attaches their information to the socket.
 * Does NOT add the user to the system.
 */
export const passportMiddleware = async (socket, next) => {
  try {
    // Extract token from handshake
    const { token } = socket.handshake.auth;
    if (!token) {
      return next(new Error('Authentication failed: Missing token'));
    }

    // Validate the token
    let decodedToken;
    try {
      decodedToken = await validateContentToken(token);
      if (!decodedToken) {
        throw new Error(`Invalid token for socket ${socket.id}`);
      }
    } catch (error) {
      const message = `Error authenticating user for socket ${socket.id}: ${error.message}`;
      if (debug) console.error(message);
      return next(new Error(`Authentication failed: ${error.reason}`));
    }

    // Extract user information from the token
    const userId = decodedToken.payload.userId;
    const userName = decodedToken.payload.userName;

    // Attach user information to the socket
    const user = {
      userId,
      userName,
      state: 'authenticated',
    };

    socket.user = Object.freeze({
      ...user,
      payload: decodedToken.payload,
    });

    // Emit an event to notify the client of successful authentication
    socket.emit(`user_authenticated`, {
      success: true,
      ...user,
    });

    if (debug) {
      console.log(`User ${userName} (${userId}) authenticated successfully`);
    }

    // Proceed to the next middleware
    next();
  } catch (error) {
    // Handle errors and pass them to the next middleware
    next(new Error(`Authentication failed: ${error.message}`));
  }
};

/**
 * Test Middleware - no token, no validation
 * Connects as Authenticated and attaches their information to the socket.
 * Does NOT add the user to the system.
 */
export const testMiddleware = async (socket, next) => {
  try {
    // Simulate a hardcoded user for testing purposes
    const userId = 'test-user';
    const userName = "Test name";

    // Attach user information to the socket
    const user = {
      userId,
      userName,
      state: 'authenticated',
    };

    socket.user = Object.freeze({
      ...user,
      payload: {},
    });

    if (debug) {
      console.log(`User ${userName} (${userId}) authenticated successfully`);
    }

    // Proceed to the next middleware
    next();
  } catch (error) {
    // Handle errors and pass them to the next middleware
    next(new Error(`Authentication failed: ${error.message} `));
  }
};
/* eslint-disable import/no-anonymous-default-export */
export default { passportMiddleware, testMiddleware };