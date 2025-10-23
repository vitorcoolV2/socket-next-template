
import { Server } from 'socket.io'; // Import Socket.IO Server for type checking

import { v4 as uuidv4 } from 'uuid';

import {
  INACTIVITY_THRESHOLD,
} from '../config.mjs';

// Import schemas
import {
  userBaseSchema,
  userResultSchema,
  userSessionSchema,
  baseMessageSchema,
  validateEventData,
  socketInfoSchema,
  markMessagesAsReadOptionsSchema,
  markMessagesAsReadResultSchema,
  typingSchema,
  getMessageHistoryOptionsSchema,
  getMessagesOptionsSchema,
  activeUserSchema,
  userQuerySchema,
  MESSAGE_STATUS_ORDERED,
} from './schemas.mjs';


import { MemoryPersistence } from './persistMemory.mjs';
import { PostgresPersistence } from './persistPostgres.mjs';


import {
  debug,
  PUBLIC_MESSAGE_USER_ID,
  PUBLIC_MESSAGE_EXPIRE_DAYS,
} from '../config.mjs';


import { cleanupOldMessages as cleanupOldMessagesUtil } from './messageCleanupUtils.mjs';


const cleanupOldMessages = (threshold = 7 * 24 * 60 * 60 * 1000) => {
  return cleanupOldMessagesUtil(userMessages, debug, threshold);
};


function normalizeTimestamp(timestamp) {
  const date = new Date(timestamp);
  if (isNaN(date.getTime())) {
    throw new Error(`Invalid timestamp: ${timestamp}`);
  }
  return date.toISOString();
}

const getNormalizedOptions = (options) => {
  const normalizedOptions = { ...options };
  if (options.since) {
    normalizedOptions.since = normalizeTimestamp(options.since);
  }
  if (options.until) {
    normalizedOptions.until = normalizeTimestamp(options.until);
  }
  return normalizedOptions;
};


function getHighPrecisionISO() {
  return new Date().toISOString();
}

// Example Output: "2025-10-06T22:33:35.186Z"
const messageContextDefault = () => ({
  type: 'private',
  status: 'sent',
  direction: 'outging',
  timestamp: getHighPrecisionISO(),
  readAt: null,
});



export const userManager = (options = {}) => {
  const { defaultStorage = 'memory', maxTotalConnections = 1000 } = options;
  // set socket instance
  let __io = options.io;
  const setIO = (io) => {
    // Validate that io is an instance of Server
    if (!(io instanceof Server) && process.env.NODE_ENV !== 'test') {
      throw new Error('Invalid or missing io instance. Expected an instance of socket.io Server.');
    }
    __io = io;
  };
  const getIO = () => {
    return __io;
  }
  if (options.io) setIO(options.io);

  // Use the provided maxTotalConnections value
  const MAX_TOTAL_CONNECTIONS = maxTotalConnections;
  if (debug) console.log(`Max total connections set to: ${MAX_TOTAL_CONNECTIONS}`);



  // Initialize persistence layer based on defaultStorage
  let persistence;
  if (defaultStorage === 'postgresql') {
    persistence = new PostgresPersistence();
  } else {
    persistence = new MemoryPersistence();
  }


  // Maps for tracking users, sockets, and messages
  const the_users = new Map(); // userId -> user data 

  const activeUsers = new Map(); // socketId -> userid to retrive the user data

  const userConversations = new Map(); // userId -> Map(conversationPartnerId -> messages[])

  const MAX_PUBLIC_MESSAGES = 100; // Maximum number of public messages to retain

  // Metrics
  let totalConnections = 0;
  let activeConnections = 0;
  let disconnections = 0;
  let errors = 0;

  /**
   * Generate a unique session ID
   */
  const generateSessionId = () => uuidv4();

  const generateMessageId = () => `msg-${Date.now()}-${Math.random().toString(36).substring(2, 9)}`;

  /**
   * Safe operation wrapper for error handling (supports both sync and async operations)
   */
  const safeOperationCE = (operation, errorMessage) => {
    try {
      const result = operation(); // Execute the operation

      // Check if the result is a promise (indicating an async operation)
      if (result && typeof result.then === 'function') {
        // Handle async operations
        return result.then(res => {
          return res;
        }).catch((error) => {
          const message = `${errorMessage}: ${error.message}`;
          if (debug) console.error(message);
          _incrementErrors();

          // Create a new error with a custom message          
          const newError = new Error(message);
          newError.operation = operation;
          newError.cause = error;
          throw newError;
        });
      }

      // Return the result for synchronous operations
      return result;
    } catch (error) {
      const message = `${errorMessage}: ${error.message}`;
      if (debug) console.error(message);
      _incrementErrors();

      // Create a new error with a custom message          
      const newError = new Error(message);
      newError.operation = operation;
      newError.cause = error;
      throw newError;
    }
  };

  // CE custom errors
  const safeOperation = async (operation, errorMessage) => {
    try {
      const result = await operation();
      return result;
    } catch (error) {
      const message = `${errorMessage}: ${error.message}`;
      if (debug) console.error(message);
      _incrementErrors();

      // Create a new error with a custom message
      const newError = new Error(message);
      newError.operation = operation;
      newError.cause = error;
      throw newError;
    }
  };

  /**
   * Validate user data using the imported userSchema
   */
  const validateUserData = (userData) => {
    const { error } = userResultSchema.validate(userData);
    if (error) {
      throw new Error(`Invalid user  ${error.message}`);
    }
  };

  /**
   * Validate user session data using the imported userSessionSchema
   */
  const validateUserSessionData = (userData) => {
    const { error } = userSessionSchema.validate(userData);
    if (error) {
      throw new Error(`Invalid user session  ${error.message}`);
    }
  };

  /**
   * Validates a user object against the userBaseSchema.
   * @param {Object} user - The user object to validate.
   * @returns {Object|null} - The validated user object or null if validation fails.
   */
  const validateUser = (user) => {
    const { error, value: validatedUser } = userBaseSchema.validate(user);
    if (error) {
      console.error(`Validation failed for user: ${JSON.stringify(user)}`);
      console.error(`Validation error: ${error.details.map(d => d.message).join(', ')}`);
      return null;
    }
    return validatedUser;
  };

  const storeUser = async (socketId, userData, auth = false) => {
    return safeOperation(async () => {
      // Validate input parameters
      if (!socketId || typeof socketId !== 'string') {
        throw new Error('Invalid socketId provided');
      }

      if (debug) {
        console.log(`Adding user with socketId: ${socketId}, userData:`, userData);
      }

      // Check connection limits
      if (activeConnections >= MAX_TOTAL_CONNECTIONS) {
        console.warn(`Connection limit exceeded for socketId: ${socketId}`);
        throw new Error(`Connection limit exceeded. Maximum allowed connections: ${MAX_TOTAL_CONNECTIONS}`);
      }

      // Retrieve existing user and socket information
      const userId = activeUsers.get(socketId);
      const _u = userId ? the_users.get(userId) : null;
      const _sockets = _u?.sockets || [];
      const _socket = _sockets.find((s) => s.socketId === socketId);

      // Generate session ID and timestamps
      const _sessionId = (_socket?.sessionId || userData.sessionId || generateSessionId());
      const _connectedAt = (_socket?.connectedAt || userData.connectedAt || Date.now());

      const lastActivity =
        process.env.NODE_ENV === 'test'
          ? userData.lastActivity || Date.now() // For testing purposes only
          : Date.now();

      // Update or create the socket
      const this_socket = {
        socketId,
        sessionId: _sessionId,
        connectedAt: _connectedAt,
        state: auth ? 'authenticated' : (userData.state || 'connected'),
        lastActivity,
      };

      // Merge existing sockets with the current socket
      const sockets = [
        this_socket,
        ..._sockets.filter((s) => s.socketId !== socketId), // Exclude the old socket with the same ID
      ];

      // Create or update the user object
      const user = {
        userId: userData.userId || null,
        userName: userData.userName || 'Anonymous',
        sockets: sockets,
        connectedAt: _connectedAt,
        lastActivity: lastActivity,
        state: reduceUserSocketsState(sockets), // Determine the user's state based on sockets
      };

      // Validate user data
      try {
        validateUserData(user);
        validateUserSessionData(user);
      } catch (error) {
        console.error('Validation failed:', error.message);
        throw error;
      }

      // Update in-memory stores
      the_users.set(user.userId, user);
      activeUsers.set(socketId, user.userId);

      // Increment connection counters
      totalConnections++;
      activeConnections++;

      // Persist the user data
      return await persistence.storeUser(user).then(us => {


        // Log the successful connection
        if (debug) {
          console.log(`User connected:`, {
            userId: user.userId,
            userName: user.userName,
            socketId,
            state: user.state,
          });
        }
        return user;
      }).catch((error) => {
        console.error(`Failed to persist user ${user.userId}:`, error.message);
        // Clean up resources if persistence fails
        the_users.delete(user.userId);
        activeUsers.delete(socketId);
        totalConnections--;
        activeConnections--;
        throw new Error(`Error persisting user ${user.userId}: ${error.message}`);
      });

    }, `Error storing user for socket ${socketId}`);
  };


  const reduceUserSocketsState = (sockets) => {
    if (!sockets || sockets.length === 0) return 'offline';
    if (sockets.some(s => s.state === 'authenticated')) return 'authenticated';
    if (sockets.some(s => s.state === 'connected')) return 'connected';
    return 'disconnected';
  };

  /**
   * Disconnect a user
   */
  const disconnectUser = async (socketId) => {
    return safeOperation(async () => {
      // Step 2: Retrieve the user associated with the socketId
      const user = await getUserBySocketId(socketId);
      if (!user) {
        return null;
      }

      // Remove the socket from the user's sockets array
      user.sockets = (user.sockets || []).filter(si =>
        si.socketId !== socketId
      );

      // Update the user's state based on remaining sockets
      user.lastActivity = Date.now();
      user.state = reduceUserSocketsState(user.sockets);

      // Check if the user has been inactive for more than INACTIVITY_THRESHOLD
      const currentTime = Date.now();
      const isInactive = user.lastActivity && currentTime - user.lastActivity > INACTIVITY_THRESHOLD;


      // Call persistence hook for user disconnection        
      return await persistence.storeUser(user).then(u => {
        if (user.sockets.length === 0) {
          activeUsers.delete(socketId);
          activeConnections--;
          disconnections++;
          //return null
        }

        // Log the disconnection
        if (debug) console.log(
          isInactive
            ? `User ${user.userName} disconnected due to inactivity.`
            : `User ${user.userName} disconnected from socket ${socketId}`
        );

        // Notify other users about the disconnection
        __io.emit('user_disconnected', {
          userId: user.userId,
          userName: user.userName,
          state: user.state,
          reason: isInactive ? 'inactivity' : 'manual',
        });

        return {
          ...user,
          socketId,
        };
      });

    }, `Error disconnecting user for socket ${socketId}`);
  };
  /**
   * Get user by socketId
   */
  const getUserBySocketId = async (socketId) => {
    return safeOperation(async () => {
      const userId = activeUsers.get(socketId);
      const user = the_users.get(userId);
      if (!user) {
        return null;
      }
      return user;

    }, `Error getting user by socketId: ${socketId}`);
  }
    ;/**
   * Get socket by socketId
   */
  const _getSockeyById = (socketId) => {
    return safeOperation(() => {
      const r = __io.sockets.rooms.has(socketId)
      const userId = activeUsers.get(socketId);
      const user = the_users.get(userId);
      if (!user) {
        return null;
      }
      const socket = user.sockets.find(s.socketId === socketId)
      return socket;

    }, `Error getting user by socketId: ${socketId}`);
  };

  /**
   * Increment errors counter
   */
  const _incrementErrors = () => {
    errors++;
  };

  /**
   * Get connection metrics
   */
  const getConnectionMetrics = () => {
    return safeOperation(() => ({
      totalConnections,
      activeConnections,
      disconnections,
      errors,
      activeUsers: activeUsers.size, //Array.from(activeUsers.values()).filter(u => u.state === 'authenticated' || u.state === 'connected').length,
    }), 'Error getting connection metrics');
  };

  /**
   * Verbose fail, Ensure socketId belongs to a registered and authenticated user
   */
  const _failInsecureSocketId = async (socketId) => {
    return safeOperation(async () => {
      // Step 1: Validate socketId
      if (!socketId || typeof socketId !== 'string') {
        throw new Error('Invalid socketId provided');
      }

      // Step 2: Retrieve the user associated with the socketId
      const user = await getUserBySocketId(socketId);
      if (!user) {
        throw new Error(`No user found for socketId: ${socketId}`);
      }

      // Step 3: Validate user data
      validateUserData(user);

      // Step 4: Ensure the user is authenticated
      if (user.state !== 'authenticated') {
        throw new Error(`User ${user.userId} is not authenticated`);
      }

      // Return the authenticated user
      return user;
    }, `Error securing socketId: ${socketId}`);
  };


  /**
 * Silent fail, Ensure socketId belongs to a registered and authenticated user
 */
  const _silenteFailInsecureSocketId = async (socketId) => {
    return safeOperation(async () => {
      // Step 1: Validate socketId
      if (!socketId || typeof socketId !== 'string' || socketId === undefined) {
        console.warn(`No user found for socketId: ${socketId}`);
        return null;
      }

      // Step 2: Retrieve the user associated with the socketId
      const user = await getUserBySocketId(socketId);
      if (!user) {
        console.warn(`No user found for socketId: ${socketId}`);
        return null;
      }

      // Step 3: Validate user data
      validateUserData(user);

      // Step 4: Ensure the user is authenticated
      if (user.state !== 'authenticated') {
        console.warn(`user found is not authenticated for socketId: ${socketId}`);
        return null;
      }

      // Return the authenticated user
      return user;
    }, `silente response rrror securing socketId: ${socketId}`);
  };

  /**
   * Load users from persistence (e.g., usersessions) if the_users is empty
   */
  const __loadUsers = async (force = false) => {
    // Check if users are already loaded or if forced reload is requested
    if (the_users.size > 0 && !force) {
      if (debug) console.log('Users already loaded in memory. Skipping persistence query.');
      return;
    }

    if (debug) console.log('No users found in memory. Querying persistence to populate the_users.');

    // Ensure the persistence hook exists
    if (!persistence.getUsers) {
      console.warn('Persistence method for fetching users is not available.');
      return;
    }

    try {
      // Fetch users from persistence
      const persistedUsers = await persistence.getUsers();
      if (debug) console.log(`Persisted users fetched: ${JSON.stringify(persistedUsers)}`);

      // Validate and add users to the in-memory map
      if (persistedUsers && Array.isArray(persistedUsers)) {
        persistedUsers.forEach(user => {
          const { error, value: validatedUser } = userBaseSchema.validate(user);
          if (!error) {
            the_users.set(validatedUser.userId, validatedUser);
          } else {
            console.error(
              `Failed to validate persisted user: ${error.details.map(d => d.message).join(', ')}`
            );
          }
        });

        if (debug) {
          console.log(
            `Users added to the_users: ${JSON.stringify(Array.from(the_users.values()))}`
          );
        }
      } else {
        console.warn('No valid users retrieved from persistence.');
      }
    } catch (error) {
      console.error('Failed to fetch users from persistence:', error.message);
      throw new Error('Error retrieving users from persistence');
    }
  };

  const getUsers2 = async (socketId, options = {}) => {
    return safeOperation(async () => {
      // Log the options and initial state of the_users
      if (debug) {
        console.log(`getUsers called with options: ${JSON.stringify(options)}`);
        console.log(`Initial the_users size: ${the_users.size}`);
      }

      // Step 1: secutiry silent result . Validate the user associated with the socketId
      const user = await _silenteFailInsecureSocketId(socketId);
      if (!user) {
        return null;
      }

      // Step 0: Validate the options against the schema
      const { error: optionsError, value: validatedOptions } = userQuerySchema.validate(options);
      if (optionsError) {
        throw new Error(`Invalid options: ${optionsError.details.map(d => d.message).join(', ')}`);
      }



      // Step 2: Destructure validated options with defaults applied
      const { states, limit, offset } = validatedOptions;

      // Step 3: Load users from persistence if the_users is empty
      await __loadUsers(the_users.size === 1);

      // Log the loaded users
      //if (debug) console.log(`Loaded users: ${JSON.stringify(Array.from(the_users.values()))}`);

      // Step 4: Retrieve all users from memory
      let filteredUsers = Array.from(the_users.values());

      // Apply filters
      if (state) {
        filteredUsers = filteredUsers.filter(user => user.state === state);
        //if (debug) console.log(`Filtered by state (${state}): ${JSON.stringify(filteredUsers)}`);
      }
      if (!includeOffline) {
        filteredUsers = filteredUsers.filter(user => user.state !== 'offline');
        //if (debug) console.log(`Filtered out offline users: ${JSON.stringify(filteredUsers)}`);
      }

      // Step 5: Apply pagination
      const paginatedUsers = filteredUsers.slice(offset, offset + limit);
      //if (debug) console.log(`Paginated users: ${JSON.stringify(paginatedUsers)}`);

      if (paginatedUsers.length === 0) {
        console.warn('Pagination returned no results. Check offset and limit values.');
      }

      // Step 6: Format the result and validate against userBaseSchema
      const usersList = paginatedUsers
        .map(user => ({
          userId: user.userId,
          userName: user.userName,
          state: user.state,
          sockets: [...user.sockets.map(s => s)],
          connectedAt: user.connectedAt,
          lastActivity: Date.now(),
        }))
        .map(validateUser) // Validate each user
        .filter(user => user !== null); // Exclude invalid users

      if (usersList) {
        __io.to(socketId).emit('usersList', usersList);
      } else {
        console.warn('Failed to retrieve users list.');
      }

      if (debug) console.log(`Final users list: ${JSON.stringify(usersList)}`);
      return usersList;
    }, `Error getting users for socketId: ${socketId}`);
  };

  const getUsers = async (socketId, options = {}) => {
    return safeOperation(async () => {
      // Log the options and initial state of the_users
      if (debug) {
        console.log(`getUsers called with options: ${JSON.stringify(options)}`);
        console.log(`Initial the_users size: ${the_users.size}`);
      }

      // Step 1: Validate the user associated with the socketId
      const user = await _silenteFailInsecureSocketId(socketId);
      if (!user) {
        return null;
      }

      // Step 2: Validate the options against the schema
      const { error: optionsError, value: validatedOptions } = userQuerySchema.validate(options);
      if (optionsError) {
        throw new Error(`Invalid options: ${optionsError.details.map(d => d.message).join(', ')}`);
      }

      // Step 3: Destructure validated options with defaults applied
      const { states, limit, offset } = validatedOptions;

      // Step 4: Load users from persistence if the_users is empty
      await __loadUsers(the_users.size < 50);

      // Log the loaded users
      if (debug) {
        console.log(`Loaded users: ${JSON.stringify(Array.from(the_users.values()))}`);
      }

      // Step 5: Retrieve all users from memory
      let filteredUsers = Array.from(the_users.values());

      // Apply filters
      if (states && states.length > 0) {
        filteredUsers = filteredUsers.filter(user => states.includes(user.state));
        //if (debug) console.log(`Filtered by states (${JSON.stringify(states)}): ${JSON.stringify(filteredUsers)}`);

      }

      // Step 6: Apply pagination
      const paginatedUsers = filteredUsers.slice(offset, offset + limit);
      if (debug && paginatedUsers.length === 0) {
        console.warn('Pagination returned no results. Check offset and limit values.');
      }

      // Step 7: Format the result and validate against userBaseSchema
      const usersList = paginatedUsers
        .map(user => ({
          userId: user.userId,
          userName: user.userName,
          state: user.state,
          //sockets: [...user.sockets.map(s => s.socketId)], // Include only socket IDs
          sockets: user.sockets,
          connectedAt: user.connectedAt,
          lastActivity: Date.now(),
        }))
        .map(validateUser) // Validate each user
        .filter(user => user !== null); // Exclude invalid users

      // Log the final result
      if (debug) {
        console.log(`Final users list: ${JSON.stringify(usersList)}`);
      }

      return usersList;
    }, `Error getting users for socketId: ${socketId}`);
  };

  /**
  * Send a message to a recipient
  */
  const sendMessage = async (socketId, recipientId, content) => {
    return safeOperation(async () => {
      // Step 1: Validate the sender
      const user = await _silenteFailInsecureSocketId(socketId);
      if (!user) {
        const ret = { success: false, error: `No user found for socketId: ${socketId}` };
        if (debug) console.log(ret);
        return ret;
      }

      // Step 2: Validate the recipient
      if (!the_users.has(recipientId)) {
        const ret = { success: false, error: `No user found for userId: ${recipientId}` };
        if (debug) console.log(ret);
        return ret;
      }

      // Step 3: Generate a unique messageId
      const messageId = generateMessageId();

      // Create the base message object
      const simple_message = {
        messageId,
        content,
        sender: { userId: user.userId, userName: user.userName },
        recipientId,
        status: 'sent', // Initial status
        type: 'private',
        timestamp: getHighPrecisionISO(),
        readAt: null,
      };

      // Validate the message against the schema
      const { valid, errors, data: msg } = validateEventData(baseMessageSchema, simple_message);
      if (!valid) {
        const errorMessage = errors.map(e => e.message).join(', ');
        throw new Error(`Validation failed: ${errorMessage}`);
      }

      // Store the message in both sender's and recipient's conversations
      await _storeMessage(recipientId, { ...msg, direction: 'incoming', status: 'sent' });
      await _storeMessage(user.userId, { ...msg, direction: 'outgoing', status: 'sent' });
      await updateMessageStatus(user.userId, msg.messageId, 'pending');
      msg.status = 'pending';

      // Check if the recipient is online
      const recipientSockets = Array.from(the_users.get(recipientId)?.sockets || []).filter(s =>
        __io.sockets.adapter.rooms.has(s.socketId)
      )

      // Return the message with its final status
      const emitSockets = recipientSockets.map(s => s.socketId);
      return { ...msg, direction: 'outgoing', emitSockets };
    }, `Error sending message from socketId ${socketId} to recipientId ${recipientId}`);
  };


  /**
  * Update the state of specific messages for a user.
  * @param {string} userId - The ID of the user whose messages are being updated.
  * @param {string[]} messageId - A message IDs to update.
  * @param {string} newStatus - The new state to assign to the messages (e.g., 'delivered', 'read').
  */
  const updateMessageStatus = async (userId, messageId, newStatus) => {
    return safeOperation(async () => {
      if (!userId || typeof userId !== 'string') {
        throw new Error('Invalid userId provided');
      }
      if (typeof messageId !== 'string') {
        throw new Error('Invalid messageId provided');
      }
      if (!MESSAGE_STATUS_ORDERED.filter(s => s !== MESSAGE_STATUS_ORDERED[0]).includes(newStatus)) {
        throw new Error(`Invalid newState: ${newStatus}`);
      }


      const _idx = MESSAGE_STATUS_ORDERED.indexOf(newStatus) - 1;
      const fromStatus = MESSAGE_STATUS_ORDERED[_idx];
      // Update message states in the persistence layer
      return await persistence.updateMessageStatus(userId, messageId, newStatus, fromStatus);

    }, `Error updating message state for userId: ${userId}`);
  };

  const getAndDeliverPendingMessages = async (socketId) => {
    return safeOperation(async () => {
      // Step 1: Validate the user associated with the socketId
      const user = await _failInsecureSocketId(socketId);
      const userId = user.userId;

      // Step 2 - Mandatory arguments
      const direction = 'incoming';
      const status = 'pending';        // we want on delivery pendeng, first is find the previous state, right? :)
      const type = 'private';

      // Step 2: Define the query options
      const options = {
        limit: 50, // Maximum number of messages to retrieve
        offset: 0, // Start from the first message
        since: null, // Optional: Ignore messages older than a certain date
        until: null, // Optional: Ignore messages newer than a certain date
        messageIds: null, // Optional: Filter by specific message IDs
        direction, // Incoming messages
        status, // Pending messages
        type, // Private messages
        senderId: null, // Optional: Filter by specific sender
        otherPartyId: userId, // Filter messages for the current user
        unreadOnly: true, // Only retrieve unread messages
      };

      // Step 3: Apply time-based policies (if applicable)
      const sinceDate = new Date();
      sinceDate.setDate(sinceDate.getDate() - 7); // Ignore messages older than 7 days
      options.since = sinceDate.toISOString();

      // Step 4: Validate the options against the schema
      const { error: optionsError, value: validOptions } = getMessagesOptionsSchema.validate(options);
      if (optionsError) {
        throw new Error(`Invalid options: ${optionsError.message}`);
      }

      // Debugging logs
      if (debug) {
        console.log(`Fetching pending messages for userId: ${userId} with options:`, validOptions);
      }

      // Step 5: Retrieve pending messages
      const messagesResult = await _getMessages(userId, validOptions);
      const pendingMessages = messagesResult.messages.filter(msg => msg.status === 'pending');
      const totalPending = pendingMessages.length;

      // Step 5: Process each pending message
      const deliveredMessageIds = [];
      const undeliveredMessageIds = [];
      const failedMessageIds = [];

      for (const msg of pendingMessages) {
        try {
          // Validate the message structure
          const { valid, errors } = validateEventData(baseMessageSchema, msg);
          if (!valid) {
            console.error(`Invalid message ${msg.messageId}:`, errors.map(e => e.message).join(', '));
            failedMessageIds.push(msg.messageId);
            continue;
          }

          // Check if the recipient is online
          const recipientSockets = Array.from(the_users.get(msg.recipientId)?.sockets || []);
          if (recipientSockets.length > 0) {
            // Update the message status to 'delivered'
            msg.status = 'delivered';

            // Emit the message to the recipient's sockets
            recipientSockets.forEach(socket => {
              __io.to(socket.socketId).emit(`${msg.type}_message`, { ...msg, direction: 'incoming' });
            });

            // Store the updated message
            await _storeMessage(userId, { ...msg, direction: 'incoming' });
            await _storeMessage(msg.sender.userId, { ...msg, direction: 'outgoing' });

            // Add the message ID to the list of delivered messages
            deliveredMessageIds.push(msg.messageId);
          } else {
            // Recipient is offline - skip delivery
            undeliveredMessageIds.push(msg.messageId);
            continue;
          }
        } catch (error) {
          console.error(`Failed to deliver pending message ${msg.messageId}:`, error.message);
          failedMessageIds.push(msg.messageId);
        }
      }

      // Return the result
      return {
        delivered: deliveredMessageIds,
        total: totalPending,
        failed: failedMessageIds.length,
        undelivered: undeliveredMessageIds.length,
        pendingMessages: pendingMessages.filter(m => m.status === 'pending'), // Include all processed messages
      };
    }, `Error retrieving pending messages for socketId: ${socketId}`);
  };


  /**
   * Mark messages as read for a socketId user state in sent,received,!read
   * Socket user can only mark as read de incoming messages
   */
  const markMessagesAsRead = async (socketId, options) => {
    return safeOperation(async () => {
      // Step 1: Validate the user associated with the socketId
      const user = await _silenteFailInsecureSocketId(socketId);
      if (!user) return null;
      const userId = user.userId;

      // Overwrite director on mark message
      //options.direction = "incoming"; // for now socketId user will mark its own copy of message;
      // should sender outgoing message copy be updated too ?  It whould flag sender of recipient open-2-read
      // TODO: investigate best pratice. for NOW just socket user OWN messages
      // MEANS: --- TAKE CARE OF message owner ship issue. the socker (user as sender) outgoing message MUST NOT persist read_at flag


      // Step 2: Validate input options against the schema
      const { error: optionsError, value: validOps } = markMessagesAsReadOptionsSchema.validate(options);
      if (optionsError) {
        throw new Error(`Invalid options: ${optionsError.message}`);
      }

      const { direction, senderId: conversationPartnerId, messageIds } = validOps;

      // Step 3: Fetch unread messages from the persistence layer
      let unreadMessages = [];
      try {
        unreadMessages = await persistence.getUnreadMessages(userId, {
          conversationPartnerId,
          messageIds,
          direction: 'incoming',
        });


        // Debugging: Log fetched unread messages
        if (debug) {
          console.log(
            `Fetched ${unreadMessages.length} unread messages for userId: ${userId}`,
            `Matching message IDs: ${messageIds ? messageIds.join(', ') : 'all'}`
          );
        }

        // Step 4: Mark the fetched messages as read in the persistence layer
        const updatedMessageIds = unreadMessages.map(msg => {
          return msg.messageId;
        });
        const result = await persistence.markMessagesAsRead(userId, { direction, messageIds: updatedMessageIds });

        // Step 6: Validate the result against the schema
        const { error: resultError } = markMessagesAsReadResultSchema.validate(result);
        if (resultError) {
          throw new Error(`Invalid result: ${resultError.message}`);
        }

        return result;

      } catch (error) {
        console.error(`Failed to fetch unread messages for userId: ${userId}`, error.message);
        throw error; // Propagate the error
      }


    }, `Error marking messages as read for socketId: ${socketId}`);
  };


  /**
  * Load user messages from persistence layer into conversation structure
  */
  const _loadUserMessages = async (userId) => {
    return safeOperation(async () => {
      if (!userId || typeof userId !== 'string') {
        throw new Error('Invalid userId provided');
      }

      // Fetch messages from persistence
      let messages = [];
      try {
        messages = await persistence.getMessages(userId);
      } catch (error) {
        if (debug) console.error(`Failed to load messages for user ${userId}:`, error);
        throw error;
      }

      // Store in conversation structure
      if (messages.length > 0) {
        await Promise.all(messages.map(message => _storeMessage(message)));
      }

      return messages;
    }, `Error loading messages for userId: ${userId}`);
  };

  const __resetData = () => {
    return safeOperation(() => {
      the_users.clear();
      activeUsers.clear();

      return;
    }, `Error reseting users`);
  };



  /**
  * Store a message with proper conversation tracking
  */
  const _storeMessage = async (userId, message) => {
    return safeOperation(async () => {
      if (!userId || typeof userId !== 'string') {
        throw new Error('Invalid userId provided');
      }

      message.status = message.status || 'sent';
      message.type = message.type || 'private';
      message.timestamp = message.timestamp || getHighPrecisionISO();


      // Validate the message against the schema
      const { valid, errors, data: msg } = validateEventData(baseMessageSchema, message);
      if (!valid) {
        const errorMessage = errors.map(e => e.message).join(', ');
        throw new Error(`Validation failed: ${errorMessage}`);
      }

      // Store the message in the persistence layer
      await persistence.storeMessage(userId, msg);

      if (debug) {
        console.log(`Message stored for user ${userId}:`, msg);
      }

      return msg;
    }, `Error storing message for userId: ${userId}`);
  };

  /**
   * Get socket IDs for a specific userId
   */
  const _getUserSockets = (userId) => {
    return safeOperation(() => {
      if (!userId || typeof userId !== 'string') {
        throw new Error('Invalid userId provided');
      }

      const user = the_users.get(userId);

      return user ? Array.from(user.sockets || []) : [];
    }, `Error getting socket IDs for userId: ${userId}`);
  };


  /**
   * Get messages for a user with optional filters and pagination
   */

  const _getMessages = async (userId, options = {}) => {
    return safeOperation(async () => {
      // Step 1: Validate userId
      if (!userId || typeof userId !== 'string') {
        throw new Error('Invalid userId provided');
      }

      // Step 2: Set default type and normalize options
      options.type = options.type || 'private';
      const normalizedOptions = getNormalizedOptions(options);

      // Step 3: Validate options against schema
      const { value: validOps, error: optionsError } = getMessagesOptionsSchema.validate(normalizedOptions);
      if (optionsError) {
        throw new Error(`Invalid options: ${optionsError.message}`);
      }

      // Step 4: Determine the userId for the query
      const __userId = validOps.type === 'public' ? PUBLIC_MESSAGE_USER_ID : userId;

      // Step 5: Apply public message expiration filter
      if (validOps.type === 'public') {
        const expireDate = new Date();
        expireDate.setDate(expireDate.getDate() - PUBLIC_MESSAGE_EXPIRE_DAYS);
        validOps.since = expireDate.toISOString();
      }

      // Step 6: Fetch messages from persistence
      return await persistence.getMessages(__userId, validOps).then(messagesResp => {
        // Step 7: Extract messages, total, and hasMore
        const { messages, total, hasMore } = messagesResp;

        // Step 8: Apply unreadOnly filter
        if (validOps.unreadOnly) {
          messages = messages.filter(msg => !msg.readAt);
        }

        // Step 9: Sort messages chronologically
        messages.sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp));

        // Step 10: Return structured response
        return {
          messages,
          total,
          hasMore,
        };

      }).catch(error => {
        console.error(`Failed to fetch messages for userId: ${__userId}`, error.message);
        throw new Error(`Error fetching messages for userId: ${__userId}. Details: ${error.message}`);
      });


    }, `Error getting messages for userId: ${userId}`);
  };

  /**
   * Get active users based on socketId and optional filters
   */
  const getActiveUsers = async (socketId, options = {}) => {
    return safeOperation(async () => {
      // Step 1: 
      const user = await _silenteFailInsecureSocketId(socketId);
      if (!user) {
        return null;
      }

      // Step 3: Extract options
      const { state = null } = options;

      // Step 4: Retrieve all active users
      const activeUsersList = Array.from(activeUsers.values())
        .map(activeUserId => the_users.get(activeUserId))
        .filter(user => {
          // Filter by state if provided
          if (state && user.state !== state) return false;
          return true;
        })
        .map((user) => {
          return {
            userId: user.userId,
            userName: user.userName,
            socketIds: [...user.sockets.map(s => s.socketId)], // Clone the sockets array
            state: user.state,
          };
        });

      return activeUsersList;
    }, `Error getting active users for socketId: ${socketId}`);
  };


  const getUserConnectionMetrics = (userId) => {
    return safeOperation(() => {
      if (!userId || typeof userId !== 'string') {
        throw new Error('Invalid userId provided');
      }

      // Retrieve the user object
      const user = the_users.get(userId);
      if (!user) {
        console.warn(`No user found for userId: ${userId}`);
        return {
          totalConnections: 0,
          activeConnections: 0,
          authenticatedConnections: 0,
        };
      }

      // Calculate metrics based on the user's sockets
      const totalConnections = user.sockets.length;
      const activeConnections = user.sockets.filter(socket => socket.state === 'authenticated' || socket.state === 'connected').length;
      const authenticatedConnections = user.sockets.filter(socket => socket.state === 'authenticated').length;

      return {
        totalConnections,
        activeConnections,
        authenticatedConnections,
      };
    }, `Error getting connection metrics for userId: ${userId}`);
  };



  const broadcastPublicMessage = (socketId, content) => {
    return safeOperation(async () => {
      const user = await _failInsecureSocketId(socketId);

      const messageId = generateMessageId();
      const recipientId = PUBLIC_MESSAGE_USER_ID; // Special ID for public messages
      const enrichedMessage = {
        messageId,
        recipientId,
        status: 'sent',
        type: 'public',
        content,
        sender: {
          userId: user.userId,
          userName: user.userName || 'Anonymous',
        },
        timestamp: getHighPrecisionISO(),
        readAt: null,
        direction: 'outgoing',
      };

      const { valid, errors, data: msg } = validateEventData(baseMessageSchema, enrichedMessage);
      if (!valid) {
        throw new Error(`Invalid message: ${errors.map(e => e.message).join(', ')}`);
      }

      // Store the message for the sender
      await _storeMessage(user.userId, { ...msg, direction: 'outgoing' });

      // Store the message globally for all users
      msg.status = 'delivered';
      msg.direction = 'incoming';
      await _storeMessage(PUBLIC_MESSAGE_USER_ID, { ...msg, direction: 'incoming' });

      // Broadcast the message to all connected users
      __io.emit('public_message', { ...msg, direction: 'incoming' });

      if (debug) {
        console.log(`User ${user.userId} broadcasted public message:`, msg);
      }

      return msg;
    }, `Error broadcasting public message for socketId: ${socketId}`);
  };

  /**
   * Retrieve public messages for a user with optional filters
   */
  const getPublicMessages = async (socketId) => {
    return safeOperation(async () => {
      const user = await _failInsecureSocketId(socketId);

      // Calculate the timestamp for 7 days ago
      const sevenDaysAgo = new Date();
      sevenDaysAgo.setDate(sevenDaysAgo.getDate() - PUBLIC_MESSAGE_EXPIRE_DAYS);

      // Construct the options object
      const options = {
        limit: 50, // Maximum number of messages to retrieve
        offset: 0, // Start from the first message
        since: sevenDaysAgo.toISOString(), // Only retrieve messages from the last 7 days
        until: null, // No upper bound for the timestamp
        type: 'public', // Only retrieve public messages
        //    direction: 'outgoing', // Align with stored direction for public messages
        unreadOnly: false, // Include both read and unread messages
        otherPartyId: PUBLIC_MESSAGE_USER_ID, // Special ID for public messages
      };

      // Validate the options against the schema
      const { error, value: validatedOptions } = getMessagesOptionsSchema.validate(options);
      if (error) {
        throw new Error(`Invalid options: ${error.message}`);
      }

      // Retrieve public messages from the global storage
      const result = await _getMessages(PUBLIC_MESSAGE_USER_ID, validatedOptions);
      //const result = await _getMessages(user.userId, validatedOptions);

      return result;
    }, `Error retrieving public messages for socketId: ${socketId}`);
  };

  /*
  * retrive socketId user History
  */
  const getMessageHistoryold = async (socketId, options = {}) => {
    return safeOperation(async () => {
      // Step 1: Validate the socketId and user association
      const user = await _failInsecureSocketId(socketId);


      // Step 2 Validate the options against the schema
      const { error, value: cOps } = getMessageHistoryOptionsSchema.validate(options);
      if (error) {
        throw new Error(`Invalid options: ${error.message}`);
      }

      const context = (cOps.type === 'private') ?
        // Step 3: Construct the options object
        {
          limit: cOps.limit, // Maximum number of messages to retrieve
          offset: cOps.offset, // Start from the first message
          status: cOps.status,
          since: null, // Only retrieve messages from the last 7 days
          until: null, // No upper bound for the timestamp
          type: 'private', // Only retrieve public messages
          direction: 'incoming',
          unreadOnly: false,
          senderId: user.userId,
          otherPartyId: cOps.otherPartyId,
        } :
        // public
        {
          limit: cOps.limit,
          offset: cOps.offset,
          status: cOps.status,
          since: null,
          until: null,
          unreadOnly: false,
          type: 'public',
          direction: 'incoming', // Align with stored direction for public messages
          otherPartyId: PUBLIC_MESSAGE_USER_ID, // Special ID for public messages
        };

      // Step 2: Validate the incoming options against the schema
      const { error: e, value: validatedMOptions } = getMessagesOptionsSchema.validate(context);
      if (e) {
        throw new Error(`Invalid options: ${e.message}`);
      }

      // Step 3: Fetch messages using _getMessages
      const messagesResult = await _getMessages(user.userId, validatedMOptions);

      // Step 5: Construct the response
      const response = {
        context,
        messages: messagesResult.messages,
        total: messagesResult.total,
        hasMore: messagesResult.hasMore,
      };

      // Step 6: Log the operation
      if (debug) console.log(
        `Fetched ${response.messages.length} messages for user ${user.userId} '`
      );

      // Step 7: Return the response
      return response;
    }, `Error fetching messages to ${socketId}`);
  };

  const getMessageHistory = async (socketId, options = {}) => {
    return safeOperation(async () => {
      // Step 1: Validate the socketId and user association
      const user = await _failInsecureSocketId(socketId);

      // Step 2: get Joi default options to merge with user options
      const { value: mOptions } = getMessageHistoryOptionsSchema.validate(options);
      /*if (error) {
          throw new Error(`Invalid options: ${error.message}`);
        }*/

      // Step 3: Handle private messages (fetch both incoming and outgoing)
      if (mOptions.type === 'private') {
        // Fetch incoming messages (user is the recipient)
        const incomingMessagesResult = await _getMessages(mOptions.otherPartyId, {
          limit: mOptions.limit,
          offset: mOptions.offset,
          status: mOptions.status,
          since: null,
          until: null,
          type: 'private',
          direction: 'incoming',
          unreadOnly: false,
          recipientId: user.userId, // Sender is the other party
        });

        // Fetch outgoing messages (user is the sender)
        const outgoingMessagesResult = await _getMessages(user.userId, {
          limit: mOptions.limit,
          offset: mOptions.offset,
          status: mOptions.status,
          since: null,
          until: null,
          type: 'private',
          direction: 'outgoing',
          unreadOnly: false,
          recipientId: mOptions.otherPartyId, // Recipient is the other party
        });

        // Merge and sort the messages
        const allMessages = [
          ...incomingMessagesResult.messages,
          ...outgoingMessagesResult.messages,
        ].sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp)); // Chronological order

        // Apply pagination to the merged results
        const start = mOptions.offset;
        const end = mOptions.offset + mOptions.limit;
        const paginatedMessages = allMessages.slice(start, end);

        // Construct the response
        const response = {

          messages: paginatedMessages,
          total: allMessages.length,
          hasMore: end < allMessages.length,
        };

        // Log the operation
        if (debug) console.log(
          `Fetched ${response.messages.length} messages for user ${user.userId}`
        );

        return response;
      }

      // Step 4: Handle public messages (unchanged)
      if (mOptions.type === 'public') {
        const context = {
          limit: mOptions.limit,
          offset: mOptions.offset,
          status: mOptions.status,
          since: null,
          until: null,
          unreadOnly: false,
          type: 'public',
          direction: 'incoming',
          otherPartyId: PUBLIC_MESSAGE_USER_ID, // Special ID for public messages
        };

        // Validate the context
        const { error: e, value: validatedMOptions } = getMessagesOptionsSchema.validate(context);
        if (e) {
          throw new Error(`Invalid options: ${e.message}`);
        }

        // Fetch public messages
        const messagesResult = await _getMessages(user.userId, validatedMOptions);

        // Construct the response
        const response = {
          context,
          messages: messagesResult.messages,
          total: messagesResult.total,
          hasMore: messagesResult.hasMore,
        };

        // Log the operation
        if (debug) console.log(
          `Fetched ${response.messages.length} public messages for user ${user.userId}`
        );

        return response;
      }
    }, `Error fetching messages to ${socketId}`);
  };


  const typingIndicator = async (socketId, data) => {
    return safeOperation(async () => {
      // Step 1: Validate the user associated with the socketId
      const user = await _silenteFailInsecureSocketId(socketId);
      if (!user) return null;

      // Step 2: Validate the incoming data against the typingSchema
      const { error, value: validatedData } = typingSchema.validate(data);
      if (error) {
        throw new Error(`Invalid typingIndicator data: ${error.message}`);
      }

      const { isTyping, recipientId } = validatedData;

      // Step 3: Retrieve the sender's user ID
      const senderUser = await getUserBySocketId(socketId);
      if (!senderUser || !senderUser.userId) {
        throw new Error('Sender not found');
      }
      const sender = senderUser.userId;

      // Step 4: Check if the recipient exists
      const recipient = the_users.get(recipientId);
      if (!recipient) {
        console.warn(`Recipient with ID ${recipientId} not found`);
        return null; // Exit early if the recipient is missing
      }

      // Step 5: Prepare the flat typing event payload
      const timestamp = getHighPrecisionISO();

      // Step 6: Get the recipient's socket IDs
      const recipientSockets = Array.from(recipient.sockets || []);
      const emitSockets = recipientSockets.map(ss => ss.socketId);
      if (emitSockets.length > 0) {
        // Emit the typingIndicator event to all recipient sockets
        emitSockets.forEach((sockId) => {
          __io.to(sockId).emit('typingIndicator', {
            success: true,
            event: 'typingIndicator',
            sender, // Use the sender's userId            
            isTyping,
            timestamp,
          });
        });
      }

      if (debug) console.log(`Typing indicator sent: ${isTyping ? 'is typing' : 'stopped typing'}`);
      return { sender, emitSockets, isTyping, timestamp }; // Return flat response
    }, 'Error handling typingIndicator');
  };


  const updateUserState = async (userId, newState) => {
    return safeOperation(async () => {
      // Step 1: Retrieve the user by userId
      const user = the_users.get(userId);
      if (!user) {
        throw new Error(`User with ID ${userId} not found`);
      }

      // Step 2: Validate the new state
      const validStates = ['connected', 'disconnected', 'authenticated', 'offline'];
      if (!validStates.includes(newState)) {
        throw new Error(`Invalid state: ${newState}`);
      }

      // Step 3: Update the user's state
      user.state = newState;
      user.lastActivity = Date.now();

      // Step 4: Persist the updated user (if applicable)
      await persistence.storeUser(user); // Uncomment if using persistence

      // Return the updated user
      return user;
    }, `Error updating user state for userId: ${userId}`);
  };

  const _checkInactivity22 = async () => {
    return safeOperation(async () => {
      const currentTime = Date.now();
      console.log(`Processing inactivity check for ${the_users.size} users at ${new Date().toISOString()}`);

      for (const [userId, user] of the_users.entries()) {
        if (!user || !Array.isArray(user.sockets)) {
          console.warn(`Removing invalid user data for userId: ${userId}`);
          the_users.delete(userId);
          continue;
        }

        // Remove invalid sockets
        user.sockets = user.sockets.filter(socket => __io.sockets.adapter.rooms.has(socket.socketId));

        // Check if the user is inactive
        if (user.sockets.length === 0 && currentTime - user.lastActivity > INACTIVITY_THRESHOLD) {
          await disconnectUser(user.sockets[0]?.socketId); // Disconnect the user
          await updateUserState(userId, 'offline'); // Update the user's state
        }
      }
    }, 'Error checking user inactivity');
  };
  const _checkInactivity = async () => {
    return safeOperation(async () => {
      const currentTime = Date.now();
      console.log(
        `Processing inactivity check for ${the_users.size} users at ${new Date().toISOString()}`
      );

      // Iterate over all users
      for (const [userId, user] of the_users.entries()) {
        if (!user || !Array.isArray(user.sockets)) {
          console.warn(`Removing invalid user data for userId: ${userId}`);
          the_users.delete(userId);
          continue; // Skip invalid users
        }

        // Remove invalid sockets
        user.sockets = user.sockets.filter(
          (socket) => socket && typeof socket.lastActivity === 'number'
        );

        if (user.sockets.length === 0) {
          console.warn(`No valid sockets remaining for user ${userId}. Removing user.`);
          the_users.delete(userId);
          continue;
        }

        // Track whether the user has any active sockets
        let hasActiveSockets = false;

        // Iterate over each socket for the user
        for (const socket of user.sockets) {
          if (!socket || typeof socket.lastActivity !== 'number') {
            console.warn(`Invalid socket data for userId: ${userId}`);
            continue; // Skip invalid sockets
          }

          // Check if the socket is inactive
          if (currentTime - socket.lastActivity > INACTIVITY_THRESHOLD) {
            console.log(
              `Socket ${socket.socketId} for user ${user.userName} (${userId}) is inactive. Disconnecting...`
            );

            try {
              await disconnectUser(socket.socketId);
            } catch (error) {
              console.error(`Failed to disconnect socket ${socket.socketId}:`, error.message);
            }
          } else {
            hasActiveSockets = true; // Mark the user as having at least one active socket
          }
        }

        // If no active sockets remain, transition the user to offline
        if (!hasActiveSockets && user.state !== 'offline') {
          user.state = 'offline';

          try {
            await persistence.storeUser({
              userId,
              state: 'offline',
            });

            console.log(
              `User ${user.userName} (${userId}) transitioned to offline due to inactivity.`
            );

            // Notify other users about the disconnection
            __io.emit('user_disconnected', {
              userId,
              userName: user.userName,
              state: 'offline',
              reason: 'inactivity',
            });
          } catch (error) {
            console.error(`Failed to persist offline state for user ${userId}:`, error.message);
          }
        }
      }
    }, 'Error checking user inactivity');
  };


  /**
   * Public API
   */
  return {
    setIO,
    getIO,
    disconnectUser,
    sendMessage,
    //
    getConnectionMetrics,
    //
    markMessagesAsRead, // Add this function to the public API
    getAndDeliverPendingMessages,
    //
    getActiveUsers,     // Add this function to the public API
    getUserConnectionMetrics,
    broadcastPublicMessage,
    getPublicMessages,
    typingIndicator,
    getMessageHistory,
    getUsers,
    updateUserState,
    storeUser,
    _incrementErrors,
    getUserSockets: _getUserSockets,
    updateMessageStatus,
    //storeMessage: _storeMessage,
    // Testing purposes    

    getUserBySocketId,
    _checkInactivity: process.env.NODE_ENV === 'test' ? _checkInactivity : undefined, // Expose only in test environment
    _getMessages: process.env.NODE_ENV === 'test' ? _getMessages : undefined, // Expose only in test environment
    // _incrementErrors: process.env.NODE_ENV === 'test' ? _incrementErrors : undefined, // Expose only in test environment
    _getUserSockets: process.env.NODE_ENV === 'test' ? _getUserSockets : undefined, // Expose only in test environment     
    __resetData: process.env.NODE_ENV === 'test' ? __resetData : undefined,
    _getSockeyById: process.env.NODE_ENV === 'test' ? _getSockeyById : undefined,
    _failInsecureSocketId: process.env.NODE_ENV === 'test' ? _failInsecureSocketId : undefined,
    _storeMessage: process.env.NODE_ENV === 'test' ? _storeMessage : undefined, // Expose only in test environment

  };
};