
import { PersistenceInterface } from './PersistenceInterface.mjs'

// userPersistent.mjs
import pg from 'pg';
const { Pool } = pg;


import {
  debug,
  PUBLIC_MESSAGE_USER_ID,
  PUBLIC_MESSAGE_EXPIRE_DAYS,
} from './config.mjs';

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
  userQuerySchema
} from './schemas.mjs';


const connectionString = process.env.DATABASE_URL;

console.log("NODE_ENV", process.env.NODE_ENV,)

function sanitizeObject(obj) {
  const seen = new WeakSet();
  return JSON.parse(
    JSON.stringify(obj, (key, value) => {
      if (typeof value === 'function') return;
      if (typeof value === "object" && value !== null) {
        if (seen.has(value)) {
          return; // Skip circular references
        }
        seen.add(value);
      }
      return value;
    })
  );
}

const getPoolOptions = (connectionString) => {
  const environment = process.env.NODE_ENV || 'development';

  const configs = {
    production: {
      max: 20,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 2000,
      ssl: { rejectUnauthorized: false }
    },
    test: {
      max: 3,
      idleTimeoutMillis: 60000,
      connectionTimeoutMillis: 15000,
      ssl: false
    },
    development: {
      max: 10,
      idleTimeoutMillis: 60000,
      connectionTimeoutMillis: 10000,
      ssl: false
    }
  };

  return {
    connectionString,
    ...configs[environment]
  };
};



/**
 * PostgreSQL-based persistence layer for user management and messaging
 */
export class PostgresPersistence extends PersistenceInterface {
  constructor() {
    super();
    // Add connection validation
    if (!connectionString) {
      throw new Error('DATABASE_URL is required for PostgresPersistence');
    }

    const poolOptions = getPoolOptions(connectionString);

    // Add pool event handlers
    this.pool = new Pool(poolOptions);

    // Handle pool errors
    this.pool.on('error', (err) => {
      console.error('Unexpected pool error:', err);
    });

    this.pool.on('connect', () => {
      if (debug) console.log('New database connection established');
    });

    this.pool.on('remove', () => {
      if (debug) console.log('Database connection removed');
    });

    // Track initialization status
    this.initialized = this.initializeDatabase();

  }

  /**
 * Initialize the database tables and indexes
 */
  async initializeDatabase() {
    try {
      await this.initializeTables();
      if (debug) console.log('✅ Database fully initialized and ready for use.');
    } catch (error) {
      console.error('❌ Failed to initialize database:', error.message);
      throw error; // Propagate the error to prevent further usage
    }
  }

  /**
   * Ensure the database is initialized before performing any operations
   */
  async ensureInitialized() {
    await this.initialized; // Wait for initialization to complete
  }

  async displayTableContents() {
    try {
      // Fetch and log user_sessions table
      const usersResult = await this.pool.query('SELECT distinct user_id,count(session_id) FROM user_sessions group by user_id');
      if (debug) console.log('✅ Distinct Users:', usersResult.rowCount);

      // Fetch and log messages table
      const messagesResult = await this.pool.query('SELECT * FROM messages');
      if (debug) console.log('✅ Messages Table Contents:', messagesResult.rowCount);
    } catch (error) {
      console.error('❌ Error displaying table contents:', error);
    }
  }

  /**
   * Initialize database tables if they don't exist - SIMPLER VERSION
   */
  async initializeTables() {
    try {
      await this.pool.query(`
            CREATE TABLE IF NOT EXISTS user_sessions (
                user_id VARCHAR(100) PRIMARY KEY,
                user_name VARCHAR(255) NOT NULL,
                sockets JSONB DEFAULT '{}',  -- {sessionId,socketId,connectedAt,lastActivity}   
                stored_at TIMESTAMP DEFAULT NOW(), 
                connected_at TIMESTAMP DEFAULT NOW(),
                last_activity TIMESTAMP DEFAULT NOW(),
                state VARCHAR(20) DEFAULT 'connected',
                metadata JSONB DEFAULT '{}'
            );
        `);

      await this.pool.query(`
            CREATE TABLE IF NOT EXISTS messages (
              id SERIAL PRIMARY KEY,
              message_id VARCHAR(100) NOT NULL,
              sender_id VARCHAR(100) NOT NULL,
              sender_name VARCHAR(255) NOT NULL,
              recipient_id VARCHAR(100),
              content TEXT NOT NULL,
              message_type VARCHAR(20) NOT NULL,
              direction VARCHAR(10) NOT NULL DEFAULT 'outgoing',
              status VARCHAR(20) NOT NULL DEFAULT 'sent',
              timestamp TIMESTAMP WITH TIME ZONE NOT NULL, 
              read_at TIMESTAMP WITH TIME ZONE NULL,     
              stored_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
              metadata JSONB DEFAULT '{}' NULL,          
              CONSTRAINT messages_message_id_direction_unique UNIQUE (message_id, direction)
          );
            
        `);


      // Create indexes if they don't exist
      await this.pool.query(`
            -- messages
            CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages(sender_id);
            CREATE INDEX IF NOT EXISTS idx_messages_recipient ON messages(recipient_id);
            CREATE INDEX IF NOT EXISTS idx_messages_status ON messages (status);
            CREATE INDEX IF NOT EXISTS idx_messages_message_type ON messages (message_type);
            CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON messages(timestamp);
            -- messages multi keys
            CREATE INDEX IF NOT EXISTS idx_messages_message_id_timestamp ON messages (message_id, direction, timestamp DESC);
            CREATE INDEX IF NOT EXISTS idx_messages_composite_lookup ON messages(sender_id, recipient_id, timestamp);

            -- users
            CREATE INDEX IF NOT EXISTS idx_user_sessions_state ON user_sessions(state);
            CREATE INDEX IF NOT EXISTS idx_user_sessions_activity ON user_sessions(last_activity);
            
        `);

      if (debug) console.log('✅ Database tables initialized');

      // Display table contents for debugging
      await this.displayTableContents();
    } catch (error) {
      console.error('❌ Failed to initialize database tables:', error);
      throw error;
    }
  }


  async addUser(user) {
    await this.ensureInitialized(); // Ensure the database is initialized

    try {
      // Validate the incoming user data against the schema
      const { userId, userName, sockets, sessionId, connectedAt, lastActivity, state, ...metadata } = user;

      // Ensure metadata is serializable
      const sanitizedMetadata = sanitizeObject(metadata);
      const sanitizedSockets = sanitizeObject(sockets);

      // Construct the query for upserting the user
      const query = `
      INSERT INTO user_sessions (
        user_id, 
        user_name, 
        sockets, 
        connected_at, 
        last_activity, 
        state, 
        metadata
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7)
      ON CONFLICT (user_id) 
      DO UPDATE SET 
        user_name = EXCLUDED.user_name,
        sockets = COALESCE(user_sessions.sockets, '{}'::JSONB) || EXCLUDED.sockets, -- Merge sockets array
        last_activity = EXCLUDED.last_activity,
        state = EXCLUDED.state,
        metadata = EXCLUDED.metadata
    `;

      // Prepare the values for the query
      const values = [
        userId,
        userName,
        JSON.stringify([...sanitizedSockets]), // Serialize sockets as JSON array
        new Date(connectedAt),
        new Date(lastActivity),
        state,
        JSON.stringify({
          ...sanitizedMetadata,
        })
      ];

      // Execute the query
      await this.pool.query(query, values);

      // Log the operation
      if (debug) console.log(`Added/Updated user ${userId} to database persistence`);

      // Return the user object
      return user;
    } catch (error) {
      console.error('Error in addUser:', error.message);
      throw error; // Re-throw the error for upstream handling
    }
  }

  // mark incoming message as read
  async markMessagesAsRead(userId, options) {
    const { direction = 'incoming', messageIds = null } = options;

    // Step 1: Validate inputs
    if (!userId || typeof userId !== 'string') {
      throw new Error('Invalid userId provided');
    }
    if (messageIds !== null && (!Array.isArray(messageIds) || !messageIds.every(id => typeof id === 'string'))) {
      throw new Error('Invalid messageIds provided');
    }

    // Step 2: Handle non-incoming messages
    if (direction !== 'incoming') {
      console.warn(`UserId ${userId} attempted to mark outgoing messages as read. Ignoring.`);
      return {
        marked: 0,
        total: 0,
      };
    }

    // Step 3: Handle edge cases
    if (messageIds !== null && messageIds.length === 0) {
      // No message IDs to update, return early
      return {
        marked: 0,
        total: 0,
      };
    }

    // Step 4: Dynamically construct the SQL query
    let query = `
    UPDATE messages
    SET read_at = NOW()
    WHERE read_at IS NULL
      AND recipient_id = $1
  `;
    const params = [userId];

    if (messageIds !== null) {
      query += ` AND message_id = ANY($${params.length + 1})`;
      params.push(messageIds);
    }

    if (direction) {
      query += ` AND direction = $${params.length + 1}`;
      params.push(direction);
    }

    query += ` RETURNING message_id`;

    // Step 5: Execute the query
    try {
      const result = await this.pool.query(query, params);

      // Log the number of rows updated
      const markedCount = result.rows.length;
      if (debug) {
        console.log(
          `Marked ${markedCount} messages as read for user ${userId}`,
          `Matching message IDs: ${messageIds ? messageIds.join(', ') : 'all'}`,
          `Direction: ${direction}`
        );
      }

      return {
        marked: markedCount,
        total: messageIds ? messageIds.length : 'all',
      };
    } catch (error) {
      console.error(`Failed to mark messages as read for userId: ${userId}`, error.message);
      throw error; // Propagate the error
    }
  }

  async onUserAuthenticated(user) {
    await this.ensureInitialized(); // Ensure the database is initialized
    try {
      await this.pool.query(
        'UPDATE user_sessions SET state = $1, last_activity = $2 WHERE user_id = $3',
        ['authenticated', new Date(), user.userId]
      );
    } catch (error) {
      console.error('Error in onUserAuthenticated:', error);
      throw error;
    }
  }



  async onUserDisconnected(user) {
    await this.ensureInitialized(); // Ensure the database is initialized
    try {
      // select user_sessions sockets as [{sessionId,state,connectedAt,sessionId}] where user_id = ${user.userId}
      await this.pool.query(
        `UPDATE user_sessions 
         SET socket_ids = array_remove(socket_ids, $1),
             last_activity = $2
         WHERE user_id = $3`,
        [user.socketId, new Date(), user.userId]
      );

      // Remove user if no more socket connections
      await this.pool.query(
        `DELETE FROM user_sessions 
         WHERE user_id = $1 AND array_length(socket_ids, 1) IS NULL`,
        [user.userId]
      );
    } catch (error) {
      console.error('Error in onUserDisconnected:', error);
      throw error;
    }
  }

  async onUserActivity(user) {
    await this.ensureInitialized(); // Ensure the database is initialized
    try {
      await this.pool.query(
        'UPDATE user_sessions SET last_activity = $1 WHERE user_id = $2',
        [new Date(), user.userId]
      );
    } catch (error) {
      console.error('Error in onUserActivity:', error);
      throw error;
    }
  }


  /**
   * Message persistence
   */
  async storeMessage(userId, message) {
    await this.ensureInitialized(); // Ensure the database is initialized

    try {
      const { messageId, sender, recipientId, content, type, status, direction, timestamp, readAt } = message;

      // Ensure metadata is serializable
      const sanitizedMetadata = sanitizeObject(message.metadata || {});

      // Construct the query for upserting the message
      const query = `
      INSERT INTO messages (
        -- insert
        message_id, 
        direction,         
        sender_id, 
        sender_name,
        recipient_id, 
        message_type,           
        content, 
        -- mutatatable status, timestamp, read_at, metadata. can not mutate new message head logic properties               
        status,       
        timestamp, 
        read_at, 
        metadata
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
      ON CONFLICT (message_id, direction) 
      DO UPDATE SET         
        status = EXCLUDED.status,
        timestamp = EXCLUDED.timestamp,
        read_at = EXCLUDED.read_at,
        metadata = EXCLUDED.metadata
    `;


      // Prepare the values for the query
      const values = [
        messageId,
        direction,
        sender.userId,
        sender.userName || 'Anonymous',
        recipientId,
        type,
        content,
        status,
        new Date(message.timestamp), // Convert to Date object,
        readAt ? new Date(readAt) : null, // Handle null readAt
        JSON.stringify({
          ...sanitizedMetadata,
        })
      ];

      // Execute the query
      await this.pool.query(query, values);

      // Log the operation
      if (debug) console.log(`Upserted message ${messageId} for user ${userId} in database persistence`);

      // Return the message object
      return message;
    } catch (error) {
      console.error('Error in storeMessage:', error.message);
      throw error; // Re-throw the error for upstream handling
    }
  }

  async getUnreadMessages(userId, options = {}) {
    const { conversationPartnerId, messageIds, direction } = options;

    // Base query to fetch unread messages for the user
    let query = `
    SELECT 
        message_id AS "messageId",
        sender_id AS "senderId",
        sender_name AS "senderName",
        recipient_id AS "recipientId",
        content,
        message_type AS "type",
        direction,
        status,
        timestamp,
        read_at AS "readAt",
        metadata
    FROM messages
    WHERE recipient_id = $1
      AND read_at IS NULL
  `;
    const params = [userId];

    // Add filters based on provided options
    if (conversationPartnerId) {
      query += ` AND sender_id = $${params.length + 1}`;
      params.push(conversationPartnerId);
    }

    if (messageIds && messageIds.length > 0) {
      // Dynamically generate placeholders for message IDs
      const placeholders = messageIds.map((_, i) => `$${params.length + i + 1}`).join(', ');
      query += ` AND message_id IN (${placeholders})`;
      params.push(...messageIds);
    }

    // Add direction filter if provided
    if (direction === 'incoming') {
      query += ` AND direction = 'incoming'`;
    } else if (direction === 'outgoing') {
      query += ` AND direction = 'outgoing'`;
    }

    try {
      // Execute the query with the constructed parameters
      const result = await this.pool.query(query, params);
      return result.rows;
    } catch (error) {
      console.error(`Failed to fetch unread messages for userId: ${userId}`, error.message);
      throw error; // Propagate the error
    }
  }

  /**
   * Query methods for user management
   */
  async getActiveUsers() {
    await this.ensureInitialized(); // Ensure the database is initialized
    try {
      const result = await this.pool.query(`
        SELECT user_id as "userId", user_name as "userName", 
               socket_ids as "socketIds", session_id as "sessionId",
               connected_at as "connectedAt", last_activity as "lastActivity",
               state, metadata
        FROM user_sessions         
        WHERE state IN ('authenticated', 'connected')
        ORDER BY last_activity DESC
      `);

      const ret = result.rows.map(row => ({
        userId: row.userId,
        userName: row.userName,
        socketIds: row.socketIds || [],
        sessionId: row.sessionId,
        connectedAt: row.connectedAt,
        lastActivity: row.lastActivity,
        state: row.state,
        ...row.metadata
      }));
      return ret;
    } catch (error) {
      console.error('Error in getActiveUsers:', error);
      return [];
    }
  }


  /**
   * Retrieve all messages for a user from the database
   */
  async getMessages(userId, options = {}) {
    await this.ensureInitialized(); // Ensure the database is initialized

    // Validate options against the schema
    const { error, value: validOps } = getMessagesOptionsSchema.validate(options);
    if (error) {
      throw new Error(`Invalid options: ${error.message}`);
    }

    const {
      limit = 50,
      offset = 0,
      since = null,
      until = null,
      type = null,
      direction = null,
      unreadOnly = false,
      otherPartyId = null,
      status = null,
    } = validOps;

    try {
      // Determine the recipientId for the query
      const recipientId = type === 'public' ? PUBLIC_MESSAGE_USER_ID : userId;

      // Construct the base query
      let query = `
      SELECT 
        message_id AS "messageId",
        sender_id AS "senderId",
        sender_name AS "senderName",
        recipient_id AS "recipientId",
        content,
        message_type AS "type",
        direction,
        status,
        timestamp,
        read_at AS "readAt",
        metadata
      FROM messages
      WHERE recipient_id = $1
    `;
      const params = [recipientId];

      // Add filters dynamically
      if (type) {
        query += ` AND message_type = $${params.length + 1}`;
        params.push(type);
      }

      if (direction) {
        query += ` AND direction = $${params.length + 1}`;
        params.push(direction);
      }

      if (status) {
        query += ` AND status = $${params.length + 1}`;
        params.push(status);
      }

      if (unreadOnly) {
        query += ` AND read_at IS NULL`;
      }

      if (since) {
        query += ` AND timestamp >= $${params.length + 1}`;
        params.push(new Date(since).toISOString());
      }

      if (until) {
        query += ` AND timestamp <= $${params.length + 1}`;
        params.push(new Date(until).toISOString());
      }

      // For public messages, apply the expiration filter
      if (type === 'public') {
        const expireDate = new Date();
        expireDate.setDate(expireDate.getDate() - PUBLIC_MESSAGE_EXPIRE_DAYS);
        query += ` AND timestamp >= $${params.length + 1}`;
        params.push(expireDate.toISOString());
      }
      // Ignore otherPartyId for public messages
      if (type !== 'public' && otherPartyId) {
        query += ` AND (sender_id = $${params.length + 1} OR recipient_id = $${params.length + 2})`;
        params.push(otherPartyId, otherPartyId);
      }



      // Add sorting and pagination
      query += ` ORDER BY timestamp DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
      params.push(limit, offset);

      // Execute the query
      const result = await this.pool.query(query, params);

      // Transform the rows into the desired format
      const messages = result.rows.map(row => ({
        messageId: row.messageId,
        sender: {
          userId: row.senderId,
          userName: row.senderName,
        },
        recipientId: row.recipientId,
        content: row.content,
        type: row.type,
        direction: row.direction,
        status: row.status,
        timestamp: row.timestamp,
        readAt: row.readAt,
        metadata: row.metadata || {},
      }));

      // Return the paginated result
      return {
        messages,
        total: result.rowCount,
        hasMore: result.rowCount > limit,
      };
    } catch (error) {
      console.error(`Failed to fetch messages for userId: ${userId}`, error.message);
      throw error; // Propagate the error
    }
  }

  /**
   * Cleanup methods
   */
  async cleanupInactiveUserSessions(inactiveTime = 30 * 60 * 1000) { // 30 minutes default
    await this.ensureInitialized(); // Ensure the database is initialized
    return 0;
    try {
      const cutoff = new Date(Date.now() - inactiveTime);
      const result = await this.pool.query(
        'DELETE FROM user_sessions WHERE last_activity < $1',
        [cutoff]
      );
      return result.rowCount;
    } catch (error) {
      console.error('Error in cleanupInactiveUsers:', error);
      return 0;
    }
  }

  async cleanupOldMessages(maxAge = 365 * 3 * 24 * 60 * 60 * 1000) { // 7 * 1y=365 days default
    await this.ensureInitialized(); // Ensure the database is initialized
    try {
      const cutoff = new Date(Date.now() - maxAge);
      const result = await this.pool.query(
        'DELETE FROM messages WHERE timestamp < $1',
        [cutoff]
      );
      return result.rowCount;
    } catch (error) {
      console.error('Error in cleanupOldMessages:', error);
      return 0;
    }
  }

  async setMessagesStatus(userId, messageIds, status) {
    await this.ensureInitialized(); // Ensure the database is initialized
    try {
      const query = `
      UPDATE messages
      SET status = $1
      WHERE user_id = $2 AND message_id = ANY($3)
      RETURNING message_id;
    `;
      const result = await this.pool.query(query, [status, userId, messageIds]);

      const updatedMessageIds = result.rows.map(row => row.message_id);

      if (debug) {
        console.log(
          `Updated status to "${status}" for messages: ${updatedMessageIds.join(', ')} for userId: ${userId}`
        );
      }

      return updatedMessageIds;
    } catch (error) {
      console.error(`Failed to update message status for userId: ${userId}`, error.message);
      throw error;
    }
  }

  /**
   * Health check
   */
  async healthCheck() {
    try {
      await this.pool.query('SELECT 1');
      return { status: 'healthy', database: 'connected' };
    } catch (error) {
      return { status: 'unhealthy', database: 'disconnected', error: error.message };
    }
  }

  async close() {
    if (this.pool) {
      await this.pool.end();
      this.pool = null;
    }
  }


}

