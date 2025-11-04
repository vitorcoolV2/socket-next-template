
import { PersistenceInterface } from './PersistenceInterface.mjs'
import { validateOptions, renderStaticSQL, buildDefaultConversation, processConversationRow, getMessageStats } from './persistPostgres-helpers.mjs'
// userPersistent.mjs
import pg from 'pg';
const { Pool } = pg;


import {
  debug,
  PUBLIC_MESSAGE_USER_ID,
  PUBLIC_MESSAGE_EXPIRE_DAYS,
} from '../config.mjs';

// Import schemas
import {
  userBaseSchema,
  userResultSchema,
  userSessionSchema,
  messageUSchema,
  validateEventData,
  socketInfoSchema,
  markMessagesAsReadOptionsSchema,
  markMessagesAsReadResultSchema,
  markMessagesAsDeliveredSchema,
  typingSchema,
  getUserConversationUOptionsSchema,
  getMessagesUOptionsSchema,
  activeUserSchema,
  userQuerySchema,
  sendStatusSchema,
  getConversationsListPOptionsSchema,
  markMessagesAsReadSchema,
  MESSAGE_STATUS_ORDERED
} from './schemas.mjs';


const connectionString = process.env.DATABASE_URL;

console.log("NODE_ENV", process.env.NODE_ENV,)

function sanitizeObject(obj) {
  const seen = new WeakSet(); // To track circular references

  try {
    // Step 1: Serialize the object
    const serialized = JSON.stringify(obj, (key, value) => {
      if (typeof value === 'function') return undefined; // Exclude functions
      if (typeof value === 'object' && value !== null) {
        if (seen.has(value)) {
          return '[Circular]'; // Handle circular references gracefully
        }
        seen.add(value);
      }
      return value;
    });

    // Step 2: Parse the sanitized object
    return JSON.parse(serialized);
  } catch (error) {
    console.error('Error sanitizing object:', error.message);
    throw new Error(`Failed to sanitize object: ${error.message}`);
  }
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
              sockets JSONB DEFAULT '[]',  -- [{sessionId,socketId,connectedAt,lastActivity}]
              created_at TIMESTAMPTZ DEFAULT NOW(), 
              connected_at TIMESTAMPTZ DEFAULT NOW(),
              last_activity TIMESTAMPTZ DEFAULT NOW(),
              state VARCHAR(20) DEFAULT 'disconnected',
              metadata JSONB DEFAULT '{}'
          );
      `);
      await this.pool.query(`
          -- users
          CREATE INDEX IF NOT EXISTS idx_user_sessions_state ON user_sessions(state);
          CREATE INDEX IF NOT EXISTS idx_user_sessions_activity ON user_sessions(last_activity);
          
      `);

      await this.pool.query(`
        CREATE TABLE IF NOT EXISTS messages (
            id SERIAL PRIMARY KEY,
            message_id VARCHAR(100) NOT NULL,
            sender_id VARCHAR(100) NOT NULL,
            sender_name VARCHAR(255) NOT NULL,
            recipient_id VARCHAR(100) NOT NULL,
            content TEXT NOT NULL,
            message_type VARCHAR(50) DEFAULT 'private',
            direction VARCHAR(10) NOT NULL CHECK (direction IN ('incoming', 'outgoing')),
            status VARCHAR(10) DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'delivered', 'read', 'failed')),
            created_at TIMESTAMPTZ DEFAULT NOW(),
            updated_at TIMESTAMPTZ DEFAULT NOW(),
            read_at TIMESTAMPTZ NULL,
            metadata JSONB DEFAULT '{}' NULL,
            CONSTRAINT idx_messages_unique_entry UNIQUE (message_id, direction)
        )
    `);


      // Create indexes if they don't exist
      await this.pool.query(`
            -- Core indexes for WHERE clause
            CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages(sender_id);
            CREATE INDEX IF NOT EXISTS idx_messages_recipient ON messages(recipient_id);
            CREATE INDEX IF NOT EXISTS idx_messages_message_id ON messages(message_id);
            CREATE INDEX IF NOT EXISTS idx_messages_direction ON messages(direction);
            CREATE INDEX IF NOT EXISTS idx_messages_status ON messages(status);
            
            -- Critical for ORDER BY performance
            CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at DESC);
            
            -- Composite index for conversation lookups
            CREATE INDEX IF NOT EXISTS idx_messages_conversation_lookup 
              ON messages(sender_id, recipient_id, created_at DESC);

            -- CREATE INDEX IF NOT EXISTS idx_messages_message_id_updated_at 
              -- ON messages (message_id, direction, updated_at DESC);

            -- CREATE INDEX IF NOT EXISTS idx_messages_composite_lookup 
              -- ON messages(sender_id, recipient_id, updated_at);
      `);


      if (debug) console.log('✅ Database tables initialized');

      // Display table contents for debugging
      await this.displayTableContents();
    } catch (error) {
      console.error('❌ Failed to initialize database tables:', error);
      throw error;
    }
  }


  async storeUser(user) {
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
        sockets = EXCLUDED.sockets, --- do not >>>>>COALESCE(user_sessions.sockets, '[]'::JSONB), ---- never merge || EXCLUDED.sockets, -- Merge sockets array
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


      if (debug) console.log('storeUser', query, values);
      // Execute the query
      await this.pool.query(query, values);

      // Log the operation
      if (debug) console.log(`Added/Updated user ${userId} to database persistence`);

      // Return the user object
      return user;
    } catch (error) {
      console.error('Error in storeUser:', error.message);
      throw error; // Re-throw the error for upstream handling
    }
  }

  /**
   * Message persistence
   */
  async storeMessage(userId, message) {
    await this.ensureInitialized(); // Ensure the database is initialized

    try {
      const { messageId, sender, recipientId, content, type, status, readAt } = message;

      // Ensure metadata is serializable
      const sanitizedMetadata = sanitizeObject(message.metadata || {});

      const direction =
        (sender.userId === recipientId && userId === recipientId) ? message.direction // can only specify outter message.direction when msg sender=recipient
          : (userId === recipientId) ? 'incoming'      // case recipient <status> incoming message
            : (userId === sender.userId) ? 'outgoing'    // case sender <status> outgoing message
              : '--NONE--'; // should never occur with input data validation

      // Construct the query for upserting the message
      const query = `
        INSERT INTO messages (
          message_id, 
          direction,         
          sender_id, 
          sender_name,
          recipient_id, 
          message_type,           
          content, 
          status,    
          created_at,   
          updated_at, 
          read_at, 
          metadata
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
        ON CONFLICT (message_id, direction) 
        DO UPDATE SET         
          status = EXCLUDED.status,
          updated_at = EXCLUDED.updated_at,
          read_at = EXCLUDED.read_at,
          metadata = EXCLUDED.metadata
        RETURNING *
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
        new Date(), // created_at updated on first persistence
        new Date(), // updated_at updated each input on message
        readAt ? new Date(readAt) : null, // Handle null readAt
        JSON.stringify({
          ...sanitizedMetadata,
        })
      ];

      // Execute the query
      console.log(query, values);
      const result = await this.pool.query(query, values);

      const finalMessage = {
        ...message,
        status: result.rows[0].status,
        createdAt: result.rows[0].created_at,
        updatedAt: result.rows[0].updated_at,
        readAt: result.rows[0].read_at,
        //metadata : result.rows[0].metadata,
      };

      // Log the operation
      if (debug) console.log(`Upserted message ${messageId} for user ${userId} in database persistence`);

      // Return the message object
      return finalMessage;
    } catch (error) {
      console.error('Error in storeMessage:', error.message);
      throw error; // Re-throw the error for upstream handling
    }
  }

  // reciving user mark (incoming.outgoing) message with status "read", read_at= <NOW>

  async markMessagesAsRead(userId, options) {
    const { messageIds } = options;
    try {
      // Step 1: Validate inputs using Joi
      const { error: validationError } = markMessagesAsReadSchema.validate({ userId, messageIds });
      if (validationError) {
        throw new Error(`Invalid input: ${validationError.message}`);
      }

      // Step 2: Construct the SQL query
      let query = `
        WITH updated_messages AS (
          UPDATE messages
          SET read_at = NOW(), status = 'read', updated_at = NOW()
          WHERE read_at IS NULL
            AND direction IN ('incoming', 'outgoing')
            AND recipient_id = $1
            AND message_id = ANY ($2)
          RETURNING *
        )
        SELECT message_id AS "messageId",
            sender_id AS "senderId",
            sender_name AS "senderName",
            recipient_id AS "recipientId",
            content,
            message_type AS "type",
            direction,
            status,
            created_at,
            updated_at,
            read_at
        FROM updated_messages;
      `;
      const params = [userId, messageIds];

      // Step 3: Execute the query
      if (debug) {
        const debugSql = renderStaticSQL(query, params);
        console.log(debugSql);
      }
      const result = await this.pool.query(query, params);

      // Step 4: Log the number of rows updated
      const markedCount = result.rows.length;
      if (debug) {
        console.log(
          `Marked ${markedCount} messages as read for user ${userId}`,
          `Matching message IDs: ${messageIds.join(', ')}`,
        );
      }

      // Step 4: Return the result
      return {
        marked: markedCount,
        updatedMessage: result.rows.map(this.mapMessages),
      };
    } catch (error) {
      console.error(`Failed to mark messages as read for userId: ${userId}`, error.message);
      throw new Error(`Database error: Failed to mark messages as read for userId: ${userId}. Details: ${error.message}`);
    }
  }

  async markMessagesAsDelivered(userId, options) {
    const { messageIds } = options;
    try {
      // Step 1: Validate inputs using Joi
      const { error: validationError } = markMessagesAsDeliveredSchema.validate({ userId, messageIds });
      if (validationError) {
        throw new Error(`Invalid input: ${validationError.message}`);
      }

      // Step 2: Construct the SQL query
      // delivered makes sense before read_at not null. if is read, is delivered. 
      let query = `
      WITH updated_messages AS (
        UPDATE messages
        SET status = 'delivered', updated_at = NOW()
        WHERE read_at IS NULL
          AND direction IN ('incoming', 'outgoing')
          AND recipient_id = $1
          AND message_id = ANY ($2)
        RETURNING *
        )
        SELECT message_id AS "messageId",
            sender_id AS "senderId",
            sender_name AS "senderName",
            recipient_id AS "recipientId",
            content,
            message_type AS "type",
            direction,
            status,
            created_at,
            updated_at,
            read_at
        FROM updated_messages;
    `;
      const params = [userId, messageIds];

      // Step 3: Execute the query
      if (debug) {
        console.log(`Executing query: ${query}`, `With parameters: ${JSON.stringify(params)}`);
      }
      const result = await this.pool.query(query, params);

      // Step 4: Log the number of rows updated
      const markedCount = result.rows.length;
      if (debug) {
        console.log(
          `Marked ${markedCount} messages as delivered for user ${userId}`,
          `Matching message IDs: ${messageIds.join(', ')}`,
        );
      }

      // Step 5: Return the result
      return {
        marked: markedCount,
        updatedMessage: result.rows.map(this.mapMessages),
      };
    } catch (error) {
      console.error(`Failed to mark messages as delivered for userId: ${userId}`, error.message);
      throw new Error(`Database error: Failed to mark messages as delivered for userId: ${userId}. Details: ${error.message}`);
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
               sockets, session_id as "sessionId",
               connected_at as "connectedAt", last_activity as "lastActivity",
               state, metadata
        FROM user_sessions         
        WHERE state IN ('authenticated')
        ORDER BY last_activity DESC
      `);

      const ret = result.rows.map(row => ({
        userId: row.userId,
        userName: row.userName,
        sockets: row.sockets || [],
        sessionId: row.sessionId,

        connectedAt: new Date(row.connectedAt).getTime(), // Convert to Unix epoch milliseconds
        lastActivity: new Date(row.lastActivity).getTime(), // Convert to Unix epoch milliseconds
        state: row.state,
        //       ...row.metadata
      }));
      return ret;
    } catch (error) {
      console.error('Error in getActiveUsers:', error);
      return [];
    }
  }


  /**
   * Query methods for user management
   */
  async getUsers(options = {}) {
    await this.ensureInitialized();
    try {
      const { error: optionsError, value: validOptions } = userQuerySchema.validate(options);
      if (optionsError) {
        console.error({ error: optionsError }, 'Invalid options');
        return [];
      }

      const { state = null, limit = 10, offset = 0, include = [] } = validOptions;

      // Build the WHERE clause dynamically and prepare parameters
      const whereClauses = [];
      const queryParams = [];
      let paramIndex = 1;

      if (state && state.length > 0) {
        whereClauses.push(`state = ANY ($${paramIndex})`);
        queryParams.push(state);
        paramIndex++;
      }

      queryParams.push(limit, offset);


      // Build the SELECT fields dynamically
      const selectFields = [
        'user_id as "userId"',
        'user_name as "userName"',
        'sockets',
        //  'session_id as "sessionId"',
        'connected_at as "connectedAt"',
        'last_activity as "lastActivity"',
        'state'
      ];

      if (include.includes('metadata')) {
        selectFields.push('metadata');
      }

      // Build the query
      const whereClause = whereClauses.length > 0 ? `WHERE ${whereClauses.join(' AND ')}` : '';
      const query = `
      SELECT ${selectFields.join(', ')}
      FROM user_sessions
      ${whereClause}
      ORDER BY last_activity DESC
      LIMIT $${paramIndex} OFFSET $${paramIndex + 1}
    `;

      // Execute the query
      if (debug) console.log(query, queryParams);
      const result = await this.pool.query(query, queryParams);
      //if (debug) console.log(result.rows);

      // Map the results
      return result.rows.map(row => ({
        userId: row.userId,
        userName: row.userName,
        sockets: row.sockets,
        //     sessionId: row.sessionId,
        connectedAt: new Date(row.connectedAt).getTime(), // Convert to Unix epoch milliseconds
        lastActivity: new Date(row.lastActivity).getTime(), // Convert to Unix epoch milliseconds
        state: row.state,
        ...(typeof row.metadata !== 'string' ? null : { metadata: row.metadata }),
      }));
    } catch (error) {
      console.error({ error }, 'Error in getUsers');
      return [];
    }
  }


  /**
   * Get user names from messages for the given user IDs 
   * @param {string[]} senderIds - Array of user IDs to get names for
   * @returns {Promise<Object>} Map of userId to userName (will include all senderIds as keys)
   */
  async _getUserNamesFromMessages(senderIds) {
    await this.ensureInitialized();

    if (!senderIds || senderIds.length === 0) {
      return {};
    }

    try {
      const query = `
        SELECT DISTINCT sender_id, sender_name 
        FROM messages 
        WHERE 
          (direction = 'incoming' AND sender_id = ANY ($1)) 
        OR
          (direction = 'outgoing' AND recipient_id = ANY ($1)) 
    `;
      const values = [senderIds];

      const result = await this.pool.query(query, values);

      // Create initial map with all senderIds as keys with null values
      const userMap = senderIds.reduce((map, senderId) => {
        map[senderId] = null;
        return map;
      }, {});

      // Update with found names from database
      result.rows.forEach(row => {
        if (userMap.hasOwnProperty(row.sender_id)) {
          userMap[row.sender_id] = row.sender_name;
        }
      });

      return userMap;
    } catch (error) {
      console.error({ error, userIds: senderIds }, 'Error in getUserNamesFromMessages');

      // Even in error case, return object with all senderIds as keys
      return senderIds.reduce((map, senderId) => {
        map[senderId] = null;
        return map;
      }, {});
    }
  }

  /**
   * Fetches a list of conversations for a user, ensuring each conversation's userId matches options.userId.
   * @param {Object} options - Input options (e.g., userId, limit, offset, include).
   * @returns {Promise<Array>} List of conversation objects where each element's userId === options.userId.
   */
  async getUserConversationsList(options = {}) {
    try {
      console.log(options);
      // Validate input options
      const validOptions = validateOptions(options, getConversationsListPOptionsSchema);
      const { userId, type, limit = 10, offset = 0, include = [] } = validOptions;

      // Build SQL query
      const whereClauses = [
        // critical to correct model results        
        '(sender_id = $1 OR recipient_id = $1)',
      ];
      const params = [userId];
      if (type) {
        whereClauses.push('message_type = $2');
        params.push(type)
      }

      const selectFields = `
        CASE 
          WHEN sender_id = $1 THEN sender_id 
          ELSE recipient_id 
        END AS "userId",
        CASE 
          WHEN sender_id = $1 AND recipient_id = $1 THEN $1
          WHEN sender_id = $1 THEN recipient_id 
          ELSE sender_id 
        END AS "otherPartyId",
        ARRAY_AGG(DISTINCT message_type) AS types,
        MIN(created_at) AS "firstMessageAt",
        MAX(created_at) AS "lastMessageAt",
        -- outgoing stats: filter by sender_id = 'sender' AND direction = 'outgoing'
        ${getMessageStats('sender_id', 'out_', 'outgoing').join(', ')}, 
        --  Incoming stats: filter by recipient_id = 'sender' AND direction = 'incoming'  
        ${getMessageStats('recipient_id', 'in_', 'incoming').join(', ')}
      `;

      if (include.includes('metadata')) {
        selectFields.push('metadata');
      }

      const whereClause = whereClauses.length > 0 ? `WHERE ${whereClauses.join(' AND ')}` : '';
      const query = `
      SELECT ${selectFields}
      FROM messages
      ${whereClause}
      GROUP BY 
        CASE 
          WHEN sender_id = $1 THEN sender_id 
          ELSE recipient_id 
        END,
        CASE 
          WHEN sender_id = $1 AND recipient_id = $1 THEN $1
          WHEN sender_id = $1 THEN recipient_id 
          ELSE sender_id 
        END
      ORDER BY "lastMessageAt" DESC
      LIMIT $3 OFFSET $4
    `;

      console.log('Outgoing stats SQL:', getMessageStats('sender_id', 'out_', 'outgoing').join(', '));
      console.log('Incoming stats SQL:', getMessageStats('recipient_id', 'in_', 'incoming').join(', '));
      params.push(limit, offset);

      console.log(query, params);
      // Execute query
      const result = await this.pool.query(query, params);

      // Get other party names
      const conversationPartyIds = [
        ...new Set(result.rows.flatMap(row => [row.userId, row.otherPartyId])),
      ];
      const conversationPartyNamesMap = await this._getUserNamesFromMessages(conversationPartyIds);

      // Map results to structured conversation objects
      const conversations = result.rows
        .map(row => {
          const _metadata = include.includes('metadata') && row.metadata ? { meta: row.metadata } : {};
          return {
            userId: row.userId,
            userName: conversationPartyNamesMap[row.userId] || null,
            otherPartyId: row.otherPartyId,
            otherPartyName: conversationPartyNamesMap[row.otherPartyId] || null,
            types: row.types || [],
            startedAt: row.firstMessageAt ? new Date(row.firstMessageAt).getTime() : null,
            lastMessageAt: row.lastMessageAt ? new Date(row.lastMessageAt).getTime() : null,
            outgoing: {
              firstMessageAt: row.firstMessageAt ? new Date(row.firstMessageAt).getTime() : null,
              lastMessageAt: row.out_lastMessageAt ? new Date(row.out_lastMessageAt).getTime() : null,
              sent: parseInt(row.out_sentCount) || 0,
              pending: parseInt(row.out_pendingCount) || 0,
              delivered: parseInt(row.out_deliveredCount) || 0,
              unread: parseInt(row.out_unreadCount) || 0,
              read: parseInt(row.out_readCount) || 0,
            },
            incoming: {
              firstMessageAt: row.firstMessageAt ? new Date(row.firstMessageAt).getTime() : null,
              lastMessageAt: row.in_lastMessageAt ? new Date(row.in_lastMessageAt).getTime() : null,
              sent: parseInt(row.in_sentCount) || 0,
              unread: parseInt(row.in_unreadCount) || 0,
              pending: parseInt(row.in_pendingCount) || 0,
              delivered: parseInt(row.in_deliveredCount) || 0,
              read: parseInt(row.in_readCount) || 0,
            },
            ...(_metadata),
          };
        })
        // Filter conversations to ensure each element's userId === options.userId
        .filter(conversation => conversation.userId === userId);

      console.log(`Generated ${conversations.length} conversations for userId: ${userId}`);
      return conversations;
    } catch (error) {
      console.error({ error }, 'Error in getUserConversationsList');
      return [];
    }
  }

  mapMessages(row) {
    return {
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
      createdAt: row.created_at,
      updatedAt: row.updated_at,
      readAt: row.read_at,
      metadata: row.metadata || {},
    }
  }

  /**
   * Retrieve all messages for a user from the database
   */
  async getMessages(_userId, options = {}) {
    await this.ensureInitialized(); // Ensure the database is initialized

    // Validate options against the schema
    const { error, value: validOps } = getMessagesUOptionsSchema.validate(options);
    if (error) {
      throw new Error(`Invalid options: ${error.message}`);
    }

    const {
      limit = 50,
      offset = 0,
      since = null,
      until = null,
      //
      type = null,
      messageId = null,
      direction = null,
      unreadOnly = false,
      senderId = null,
      recipientId = null,
      status = null,
    } = validOps;


    // Normalize type to always be an array
    const normalizedType = Array.isArray(type) ? type
      : typeof type === 'string' ? [type]
        : [];

    // Normalize status to always be an array
    const normalizedFromStatus = Array.isArray(status) ? status
      : typeof status === 'string' ? [status]
        : [];

    // Normalize message identifier to always be an array
    const normalizedMessageId = Array.isArray(messageId) ? messageId
      : typeof messageId === 'string' ? [messageId]
        : [];

    try {
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
        created_at,
        updated_at,
        read_at,
        metadata
      FROM messages
      WHERE message_type = ANY ($1)
    `;
      const params = [normalizedType];

      // Add filters dynamically
      if (messageId) {
        query += ` AND message_id = ANY ($${params.length + 1})\n`;
        params.push(normalizedMessageId);
      }

      if (status) {
        query += ` AND status = ANY ($${params.length + 1})\n`;
        params.push(normalizedFromStatus);
      }

      if (direction) {
        query += ` AND direction = $${params.length + 1}\n`;
        params.push(direction);
      }

      if (unreadOnly) {
        query += ` AND read_at IS NULL\n`;
      }

      if (since) {
        query += ` AND updated_at >= $${params.length + 1}\n`;
        params.push(new Date(since).toISOString());
      }

      if (until) {
        query += ` AND updated_at <= $${params.length + 1}\n`;
        params.push(new Date(until).toISOString());
      }

      if (senderId) {
        query += ` AND sender_id = $${params.length + 1}\n`;
        params.push(senderId);
      }
      if (recipientId) {
        query += ` AND recipient_id = $${params.length + 1}\n`;
        params.push(recipientId);
      }

      // Add sorting and pagination
      query += ` ORDER BY updated_at DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}\n`;
      params.push(limit, offset);

      // Execute the query
      if (debug) {
        const finalSQl = renderStaticSQL(query, params);
        console.log('getMessages sql:', finalSQl);
      }
      const result = await this.pool.query(query, params);

      // Transform the rows into the desired format
      const messages = result.rows.map(this.mapMessages);

      // Return the paginated result
      return {
        messages,
        total: result.rowCount,
        hasMore: result.rowCount > limit,
      };
    } catch (error) {
      console.error(`Failed to fetch messages`, error.message);
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
        'DELETE FROM messages WHERE updated_at < $1',
        [cutoff]
      );
      return result.rowCount;
    } catch (error) {
      console.error('Error in cleanupOldMessages:', error);
      return 0;
    }
  }

  async updateMessageStatus(userId, messageId, status, fromStatus = []) {
    await this.ensureInitialized(); // Ensure the database is initialized


    // Normalize fromStatus to always be an array
    const normalizedFromStatus = Array.isArray(fromStatus) ? fromStatus
      : typeof fromStatus === 'string' ? [fromStatus]
        : [];

    // Update both sender and recipient copies of the message
    try {
      const query = `
      UPDATE messages
      SET status = $1, updated_at = $2
      WHERE status = ANY ($3)
        AND message_id = $4
        AND sender_id = $5
      RETURNING   
        message_id AS "messageId",
        sender_id AS "senderId",
        sender_name AS "senderName",
        recipient_id AS "recipientId",
        content,
        message_type AS "type",
        direction,
        status,
        created_at,
        updated_at,
        read_at;
      `;

      const values = [status, new Date(), normalizedFromStatus, messageId, userId];


      if (debug) {
        const renderedQuery = renderStaticSQL(query, values);
        console.log('Rendered Query:', renderedQuery);
      }
      const result = await this.pool.query(query, values);

      // Check if any rows were updated
      if (result.rowCount === 0) {
        console.warn(
          `No rows updated for userId: ${userId}, messageId: ${messageId}, fromStatus: ${fromStatus.join(',')}, toStatus: ${status}`
        );
        return null; // Indicate that no rows were updated
      } else if (result.rowCount < 2) {
        console.warn(
          `Unless some sent message deleted, it is expected to update both incoming and outgoing messages for userId: ${userId}, messageId: ${messageId}, fromStatus: ${fromStatus}, toStatus: ${status}`
        );
      }

      // Log updated rows
      if (debug) {
        console.log(
          `Updated status from "${fromStatus.join(',')}" to "${status}" for message: ${messageId}, userId: ${userId}`,
          result.rows
        );
      }

      return result.rows.map(this.mapMessages); // Return all updated rows for visibility
    } catch (error) {
      console.error(
        `Failed to update message status for userId: ${userId}, messageId: ${messageId}, fromStatus: ${fromStatus.join(',')}, toStatus: ${status}`,
        error.message
      );
      throw error; // Re-throw the error for upstream handling
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

