import Joi from 'joi';

const timestampSchema = Joi.date().iso().description('ISO 8601 timestamp');
// Option 2: Use regex pattern (most reliable)
// const nanoDateSchema = Joi.string().pattern(
//  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/,
//  'ISO 8601 with high precision'
//);

// Test your timestamp
/*const timestamp = '2025-10-07T10:40:35.606329747771Z';
const result = nanoDateSchema.validate(timestamp);
console.log(result.error ? result.error.message : 'VALID');*/

// Reusable Primitive Schemas
export const userIdSchema = Joi.string().min(1).max(100).description('Unique identifier for the user');
export const userNameSchema = Joi.string().min(1).max(255).description('User display name');
export const socketIdSchema = Joi.string().description('Socket ID for the user');
export const socketIdsSchema = Joi.array().items(socketIdSchema).default([]).required().description('Array of socket IDs associated with the user');
export const sessionIdSchema = Joi.string().description('Unique session ID generated for the user');

export const messageIdSchema = Joi.string().optional().max(50).description('Unique message identifier');
export const contentSchema = Joi.string().min(1).max(5000).required().description('Message content');

export const MESSAGE_STATUS_ORDERED = Object.freeze(['sent', 'pending', 'delivered', 'read', 'failed']);
export const statusSchema = Joi.string()
  .valid(...MESSAGE_STATUS_ORDERED)
  .default('sent')
  .required()
  .description('Message delivery status');
export const readAtSchema = timestampSchema
  .allow(null)
  .default(null)
  .description('When the message was read (ISO timestamp)');

// User Connection State Schema
export const userConnectionState = Joi.string()
  .valid('connected', 'authenticated', 'disconnected', 'offline')
  .required()
  .description('Current state of the user connection');

// Sender/Recipient Schema
export const senderSchema = Joi.object({
  userId: userIdSchema.required().description('Sender user ID'),
  userName: userNameSchema.optional().description('Sender display name'),
}).description('Sender information');

export const recipientSchema = Joi.object({
  userId: userIdSchema.required(),
  userName: userNameSchema.optional(),
}).description('Recipient information');

// Socket Info Schema
export const socketInfoSchema = Joi.object({
  socketId: socketIdSchema
    .required()
    .messages({
      'any.required': 'Socket ID is required.',
      'string.empty': 'Socket ID cannot be empty.',
      'string.base': 'Socket ID must be a string.',
    }),
  sessionId: sessionIdSchema
    .required()
    .messages({
      'any.required': 'Session ID is required.',
      'string.empty': 'Session ID cannot be empty.',
      'string.base': 'Session ID must be a string.',
    }),
  connectedAt: Joi.number()
    .integer()
    .default(() => Date.now())
    .required()
    .messages({
      'number.base': 'Connected At must be a valid timestamp (integer).',
      'any.required': 'Connected At is required.',
    })
    .description('Timestamp of initial connection'),
  lastActivity: Joi.number()
    .integer()
    .default(() => Date.now())
    .optional()
    .messages({
      'number.base': 'Last Activity must be a valid timestamp (integer).',
      'any.required': 'Last Activity is required.',
    })
    .description('Timestamp of last activity'),
  state: userConnectionState.required().description('Current state of the user connection'),
  payload: Joi.object().unknown(true),
}).unknown(false).description('Socket connection details');


export const socketsSchema = Joi.array()
  .items(socketInfoSchema)
  .messages({
    'array.base': 'Sockets must be an array.',
    'array.includesRequiredUnknowns': 'Each item in Sockets must match the socketInfoSchema.',
    'any.required': 'Sockets are required.',
  });



// Base User Schema
export const userBaseSchema = Joi.object({
  userId: userIdSchema.allow(null).optional(),
  userName: userNameSchema.allow(null).optional(),
  //sessionId: sessionIdSchema.allow(null).optional(),
  state: userConnectionState.required(),
  sockets: socketsSchema.required(),
  connectedAt: Joi.number().integer().default(() => Date.now()).required(),
  lastActivity: Joi.number().integer().default(() => Date.now()).required(),
}).unknown(true).strict().description('Base user schema');

// Add User Data Schema
export const addUserDataSchema = Joi.object({
  userId: userIdSchema.optional(),
  userName: userNameSchema.optional(),
}).description('Data for adding a new user');

// Disconnect User Result Schema
export const disconnectUserResultSchema = Joi.object({
  userId: userIdSchema.optional(),
  userName: userNameSchema.optional(),
  state: userConnectionState.optional(),
}).description('Result of disconnecting a user');


export const userResultSchema = Joi.object({
  userId: userIdSchema.allow(null).optional(),
  userName: userNameSchema.allow(null).optional(),
  //sessionId: sessionIdSchema.allow(null).optional(),
  state: userConnectionState.required(),
  sockets: socketsSchema.required(),
  connectedAt: Joi.number().integer().default(() => Date.now()).required()
    .description('Timestamp of initial connection'),
  lastActivity: Joi.number().integer().default(() => Date.now()).optional()
    .description('Timestamp of last activity'),
}).unknown(true).strict();


export const userSessionSchema = Joi.object({
  userId: userIdSchema.required(),
  userName: userNameSchema.required(),
  //sessionId: sessionIdSchema.required(),
  state: userConnectionState.required(),
  sockets: Joi.array()
    .items(socketInfoSchema)
    .required()
    .messages({
      'array.base': 'Sockets must be an array.',
      'array.includesRequiredUnknowns': 'Each item in Sockets must match the socketInfoSchema.',
      'any.required': 'Sockets are required.',
    }),
  connectedAt: Joi.number().integer().default(() => Date.now()).required()
    .description('Timestamp of initial connection'),
  lastActivity: Joi.number().integer().default(() => Date.now()).optional()
    .description('Timestamp of last activity'),
  auth: Joi.function()
    .optional()
    .description('Optional auth function that accepts a token and returns a boolean')
    .default(() => async () => true)
}).unknown(true).strict();


const directionSchema = Joi.string()
  .valid('incoming', 'outgoing')
  .optional()
  .allow(null)
  .default(null)
  .description('option defining "message" "OWN-relation" current user. For current user OWN message (sender=current && "outgoing") + OWN message for (message recipient && "incoming"');

// Get Messages Options Schema
/*
      limit = 50,
        offset = 0,
        since = null,
        until = null,
        messageIds = null,
        type = null,
        otherPartyId = null,
        senderId = null,
        direction = null,
        unreadOnly = false,
*/
// getMesageOptions for _getMessages(userId, options|query)
export const getMessagesUOptionsSchema = Joi.object({
  // pagination
  limit: Joi.number().integer().min(0).optional().default(50).allow(null).description('Maximum number of messages to retrieve'),
  offset: Joi.number().integer().min(0).optional().default(0).allow(null).description('Offset for pagination'),
  // date interval
  since: Joi.date().iso().optional().allow(null).default(null).description('Retrieve messages sent after this timestamp'),
  until: Joi.date().iso().optional().allow(null).default(null).description('Retrieve messages sent before this timestamp'),
  // filter set conversations
  messageIds: Joi.array().items(messageIdSchema).optional().allow(null).default(null).description('Filter messages by message id'),

  type: Joi.string().valid('private', 'public').required().default('private').description('Filter messages by type'),

  senderId: userIdSchema.optional().allow(null).default(null).description('options Filter messages by senderId'),
  recipientId: Joi.string().optional().allow(null).default(null).description('option Filter messages for incoming messages'),
  status: statusSchema.optional().allow(null).default(null),

  direction: directionSchema.optional(),
  unreadOnly: Joi.boolean().optional().default(false).description('Retrieve only unread messages'),
  otherPartyId: userIdSchema.optional().allow(null).default(null).description('Used only with type: "public". option Filter messages where the specified other party is either the sender or receiverId for'),
}).description('Options for fetching messages');


export const getUserConversationUOptionsSchema = Joi.object({
  limit: Joi.number().integer().min(0).max(100).default(20), // Number of messages to fetch
  offset: Joi.number().integer().min(0).default(0), // Offset for pagination
  type: Joi.string().optional().allow(null).valid('private', 'public').default('private'), // Type of messages to fetch
  status: statusSchema.optional().allow(null).default(null),
  otherPartyId: userIdSchema.required().default(null).description('option Filter messages where the specified other party is either the sender or receiverId'),
});
export const getUserConversationPOptionsSchema = getUserConversationUOptionsSchema.clone().keys({
  userId: userIdSchema.required().allow(null).default(null).description('option Filter userId oucoming,incoming messages'),
});

// Storage Message Simple Message Schema
export const baseMessageSchema = Joi.object({
  messageId: messageIdSchema.required(),
  sender: senderSchema.required(),
  recipientId: userIdSchema.required().description('Recipient user ID'),
  content: contentSchema.required(),
  status: statusSchema.required(),
  type: Joi.string()
    .valid('private', 'public')
    .required()
    .description('Message type')
    .default('private'),
  // Optional fields - exactly matching the interface
  direction: directionSchema.optional(),
  status: statusSchema.required(),
  readAt: readAtSchema.optional(),
});

export const persistMessageSchema = baseMessageSchema.clone().keys({
  createdAt: timestampSchema.description('Message creation timestamp in ISO format'),
  updatedAt: timestampSchema.description('Message creation timestamp in ISO format'),
})

// Mark Messages as Read Schemas
export const markMessagesAsReadOptionsSchema = Joi.object({
  // Optional senderId with custom error messages
  senderId: userIdSchema.optional().messages({
    'string.base': 'senderId must be a string',
    'any.required': 'senderId is required when messageIds is not provided',
  }),

  // Optional messageIds array with custom error messages
  messageIds: Joi.array()
    .items(messageIdSchema)
    .optional()
    .messages({
      'array.base': 'messageIds must be an array of strings',
      'string.base': 'Each messageId must be a string',
      'any.required': 'messageIds is required when senderId is not provided',
    }),
})
  // Ensure at least one of senderId or messageIds is provided
  .or('senderId', 'messageIds')
  .messages({
    'object.missing': 'Either senderId or messageIds must be provided',
  });

export const markMessagesAsReadResultSchema = Joi.object({
  marked: Joi.number().integer().min(0).required().messages({
    'number.base': 'marked must be a number',
    'number.integer': 'marked must be an integer',
    'number.min': 'marked cannot be negative',
    'any.required': 'marked is required',
  }),
  total: Joi.number().integer().min(0).required().messages({
    'number.base': 'total must be a number',
    'number.integer': 'total must be an integer',
    'number.min': 'total cannot be negative',
    'any.required': 'total is required',
  }),
}).description('Result of marking messages as read');

/**
 * export const userQuerySchema = Joi.object({
  state: userConnectionState.optional(),
  includeOffline: Joi.boolean()
    .default(true)
    .description('Include offline users in results'),

  limit: Joi.number().integer().min(1).max(100).default(10)
    .description('Maximum number of users to retrieve'),

  offset: Joi.number().integer().min(0).default(0)
    .description('Number of users to skip for pagination')
});


 */
export const userIncludables = ['metadata'];
export const userQuerySchema = Joi.object({
  include: Joi.array().items(Joi.string().valid(...userIncludables)).allow(null).default([])
    .description(`Can include extra fields: ${userIncludables.join(', ')}`),

  states: Joi.array().items(userConnectionState).optional().allow(null).default(['authenticated', 'offline'])
    .description('If not specified include all. If specified Include the connection states in results'),

  limit: Joi.number().integer().min(1).max(100).default(10)
    .description('Maximum number of users to retrieve'),

  offset: Joi.number().integer().min(0).default(0)
    .description('Number of users to skip for pagination')
});

// Connection Metrics Schema
export const connectionMetricsSchema = Joi.object({
  totalConnections: Joi.number().integer().min(0).required().description('Total number of connections'),
  authenticatedConnections: Joi.number().integer().min(0).required().description('Number of authenticated connections'),
  disconnections: Joi.number().integer().min(0).required().description('Number of disconnections'),
  errors: Joi.number().integer().min(0).required().description('Number of errors encountered'),
  activeUsers: Joi.number().integer().min(0).required().description('Number of active users'),
}).description('Connection metrics schema');

// Active User Schema
export const activeUserSchema = Joi.object({
  userId: userIdSchema.required(),
  userName: userNameSchema.required(),
  sockets: Joi.array().items(socketInfoSchema).required(),
}).description('Active user schema');

// Get Messages Result Schema
export const getMessagesResultSchema = Joi.object({
  messages: Joi.array().items(baseMessageSchema).required(),
  total: Joi.number().integer().min(0).required(),
  hasMore: Joi.boolean().required(),
}).description('Result of fetching messages');

// Input/Output Schemas for Each Function
export const schemas = {
  addUser: {
    in: Joi.object({
      socketId: socketIdSchema.required(),
      userData: addUserDataSchema.required(),
    }),
    out: userBaseSchema,
  },
  disconnectUser: {
    in: Joi.object({
      socketId: socketIdSchema.required(),
    }),
    out: disconnectUserResultSchema,
  },
  getUserBySocketId: {
    in: Joi.object({
      socketId: socketIdSchema.required(),
    }),
    out: userBaseSchema,
  },
  getMessages: {
    in: Joi.object({
      meId: userIdSchema.required(),
      options: getMessagesUOptionsSchema.optional(),
    }),
    out: getMessagesResultSchema,
  },
  storeMessage: {
    in: Joi.object({
      userId: userIdSchema.required(),
      simple_message: baseMessageSchema.required(),
    }),
    out: baseMessageSchema,
  },
  sendMessage: {
    in: Joi.object({
      senderId: userIdSchema.required(),
      recipientId: userIdSchema.required(),
      content: contentSchema.required(),
    }),
    out: baseMessageSchema,
  },
  getAndDeliverPendingMessages: {
    in: Joi.object({
      userId: userIdSchema.required(),
    }),
    out: Joi.object({
      delivered: Joi.number().integer().min(0).required(),
      total: Joi.number().integer().min(0).required(),
      failed: Joi.number().integer().min(0).required(),
      pendingMessages: Joi.array().items(baseMessageSchema).required(),
    }).description('Result of delivering pending messages'),
  },
  loadUserMessages: {
    in: Joi.object({
      userId: userIdSchema.required(),
    }),
    out: Joi.array().items(baseMessageSchema),
  },
  incrementErrors: {
    in: Joi.object({}),
    out: Joi.object({}),
  },
  getConnectionMetrics: {
    in: Joi.object({}),
    out: connectionMetricsSchema,
  },
  getSocketIdsByUserId: {
    in: Joi.object({
      userId: userIdSchema.required(),
    }),
    out: Joi.array().items(socketIdSchema),
  },

  markMessagesAsRead: {
    in: Joi.object({
      socketId: socketIdSchema.required(),
      options: markMessagesAsReadOptionsSchema.optional(),
    }),
    out: markMessagesAsReadResultSchema,
  },
  getActiveUsers: {
    in: Joi.object({
      socketId: socketIdSchema.optional(),
      state: userConnectionState.optional(),
    }),
    out: Joi.array().items(activeUserSchema),
  },
  getUserConnectionMetrics: {
    in: Joi.object({
      socketId: socketIdSchema.required(),
    }),
    out: Joi.object({
      totalConnections: Joi.number().integer().min(0).required(),
      activeConnections: Joi.number().integer().min(0).required(),
      authenticatedConnections: Joi.number().integer().min(0).required(),
    }),
  },
  publicMessages: {
    in: Joi.object({}),
    out: Joi.array().items(baseMessageSchema),
  },
  broadcastPublicMessage: {
    in: Joi.object({
      socketId: socketIdSchema.required(),
      message: contentSchema.required(),
    }),
    out: Joi.object({}),
  },
};

// Typing Indicator Schema
export const typingSchema = Joi.object({
  isTyping: Joi.boolean().required().description('Indicates whether the user is typing'),
  recipientId: Joi.string().min(1).max(100).required().description('Recipient user ID'),
}).unknown(false).strict();

// U=User
export const getConversationsListUOptionsSchema = Joi.object({
  limit: Joi.number().integer().min(1).max(100).default(10),
  offset: Joi.number().integer().min(0).default(0),
  include: Joi.array().items(Joi.string().valid('metadata')).allow(null).default([]),
  otherPartyId: userIdSchema.optional().description('optional. filter result to one specific user conversation'),
  type: Joi.string().optional().allow(null).valid('private', 'public').default('private')
    .description('optional. filter result to one type of user conversation'),
});
// P=Persistence
export const getConversationsListPOptionsSchema = getConversationsListUOptionsSchema.clone().keys({
  userId: userIdSchema.required().allow(null).default(null).description('the requesting user'),
  include: Joi.array().items(Joi.string().valid('metadata')).allow(null).default([])
});

// Validation Wrapper Function
export const validateEventData = (schema, data) => {
  const { error, value } = schema.validate(data, {
    abortEarly: false,
    stripUnknown: true,
  });

  if (error) {
    return {
      valid: false,
      errors: error.details.map((detail) => ({
        message: detail.message,
        path: detail.path,
      })),
    };
  }

  return {
    valid: true,
    data: value,
  };
};


