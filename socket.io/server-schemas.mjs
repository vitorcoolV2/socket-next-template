import Joi from 'joi';

export const userConnectionState = Joi.string()
  .valid(
    'connected', 'authenticated', 'disconnected', 'offline'
  )

export const userSchema = Joi.object({
  userId: Joi.string().allow(null).optional().description('Unique identifier for the user'),
  userName: Joi.string().allow(null).optional().description('Display name of the user'),
  sessionId: Joi.string().allow(null).optional().description('Unique session ID generated for the user'),
  state: Joi.string()
    .valid('connected', 'disconnected', 'offline')
    .required()
    .description('Current state of the user connection'),
  socketIds: Joi.array().items(Joi.string()).default([]).required()
    .description('Array of active socket IDs for the user'),
  connectedAt: Joi.number().integer().default(() => Date.now()).required()
    .description('Timestamp of initial connection'),
  lastActivity: Joi.number().integer().default(() => Date.now()).required()
    .description('Timestamp of last activity'),
}).unknown(true).strict();


export const userSessionSchema = Joi.object({
  userId: Joi.string().required().description('Unique identifier for the user'),
  userName: Joi.string().required().description('Display name of the user'),
  sessionId: Joi.string().required().description('Unique session ID generated for the user'),
  state: Joi.string()
    .valid('connected', 'authenticated', 'disconnected', 'offline')
    .required()
    .description('Current state of the user connection'),
  socketIds: Joi.array().items(Joi.string()).default([])
    .required()
    .description('Array of active socket IDs for the user'),
  connectedAt: Joi.number().integer().default(() => Date.now()).required()
    .description('Timestamp of initial connection'),
  lastActivity: Joi.number().integer().default(() => Date.now()).required()
    .description('Timestamp of last activity'),
  auth: Joi.function()
    .optional()
    .description('Optional auth function that accepts a token and returns a boolean')
    .default(() => async () => true)
}).unknown(true).strict();

// Authentication schema
export const authenticateSchema = Joi.object({
  userId: Joi.string().min(3).max(50).optional().messages({
    'string.base': 'User ID must be a string.',
    'string.empty': 'User ID is required and cannot be empty.',
    'string.min': 'User ID must be at least {#limit} characters long.',
    'string.max': 'User ID cannot exceed {#limit} characters.',
    'any.required': 'User ID is required.',
  }),

  userName: Joi.string().min(2).max(100).optional().messages({
    'string.base': 'Username must be a string.',
    'string.empty': 'Username is required and cannot be empty.',
    'string.min': 'Username must be at least {#limit} characters long.',
    'string.max': 'Username cannot exceed {#limit} characters.',
    'any.required': 'Username is required.',
  }),

  token: Joi.string().max(1024).required().allow('').messages({
    'string.base': 'Token must be a string if provided.',
    'string.max': 'Token cannot exceed {#limit} characters.',
  }),
});

// Message schema
export const messageSchema = Joi.object({
  content: Joi.string().min(1).max(1000).required(),
  replyTo: Joi.string().optional(),
});

// Private message schema
export const simplePrivateMessageSchema = Joi.object({
  recipientId: Joi.string().min(3).max(50).required(),
  content: Joi.string().min(1).max(1000).required(),
});

// Typing indicator schema
export const typingSchema = Joi.object({
  isTyping: Joi.boolean().required(),
  recipientId: Joi.string().allow(null).max(50).optional(),
});


export const getMessageHistorySchema = Joi.object({
  userId: Joi.string().required(), // The ID of the user whose messages are being fetched
  limit: Joi.number().integer().min(1).max(100).default(20), // Number of messages to fetch
  offset: Joi.number().integer().min(0).default(0), // Offset for pagination
  type: Joi.string().valid('private', 'public').default('private'), // Type of messages to fetch
});

export const markMessagesReadSchema = Joi.object({
  messageIds: Joi.array().items(Joi.string()).min(1).required(),
});

export const expectedDisconnectReasons = Joi.string()
  .valid(
    'transport close',
    'transport error',
    'ping timeout',
    'client namespace disconnect',
    'server namespace disconnect',
    'client disconnect',
    'server disconnect'
  )
  .custom((value, helpers) => {
    if (value === 'ping timeout') {
      return helpers.error('any.custom', {
        message: 'Ping timeout - client may be unreachable',
      });
    }
    return value;
  }, 'Custom disconnect reason validation')
  .messages({
    'any.custom': '{{#message}}',
    'any.only': 'Disconnect reason must be one of the predefined reasons.',
  });



// Response templates - Fixed to be compatible with usage
export const responseTemplates = {
  success: (event, data = null) => ({
    success: true,
    status: 'success',
    event,
    timestamp: new Date().toISOString(),
    data,
  }),

  error: (event, message, code = 'VALIDATION_ERROR') => ({
    success: false,
    status: 'error',
    event,
    timestamp: new Date().toISOString(),
    error: {
      message,
      code,
    },
  }),

  exception: (event, error) => ({
    success: false,
    status: 'exception',
    event,
    timestamp: new Date().toISOString(),
    error: {
      message: error?.message || 'Internal server error',
      code: 'INTERNAL_ERROR',
      details: process.env.NODE_ENV === 'development' ? error?.stack : undefined,
    },
  }),

  // Additional template for validation errors
  validationError: (event, errors) => ({
    success: false,
    status: 'error',
    event,
    timestamp: new Date().toISOString(),
    error: {
      message: 'Validation failed',
      code: 'VALIDATION_ERROR',
      details: errors,
    },
  }),
};

// Helper function to create consistent error responses
export const createErrorResponse = (event, error, errorType = 'error') => {
  if (errorType === 'validation') {
    return responseTemplates.validationError(event, error);
  }

  if (errorType === 'exception') {
    return responseTemplates.exception(event, error);
  }

  return responseTemplates.error(event, error.message, error.code, error.details);
};

// Helper function for successful responses
export const createSuccessResponse = (event, data = null) => {
  return responseTemplates.success(event, data);
};


export const privateMessageSchema = Joi.object({
  // Required fields - exactly matching the interface
  messageId: Joi.string()
    .required()
    .min(1)
    .max(100)
    .description('Unique message identifier'),

  sender: Joi.object({
    userId: Joi.string()
      .required()
      .min(1)
      .max(100)
      .description('Sender user ID'),

    userName: Joi.string()
      .optional()
      .min(1)
      .max(255)
      .description('Sender display name')

  })
    .required()
    .description('Message sender information'),

  recipientId: Joi.string()
    .required()
    .min(1)
    .max(100)
    .description('Recipient user ID'),

  content: Joi.string()
    .required()
    .min(1)
    .max(5000)
    .description('Message content'),

  timestamp: Joi.string()
    .isoDate()
    .required()
    .description('Message creation timestamp in ISO format'),

  isPrivate: Joi.boolean()
    .required()
    .description('Whether the message is private'),

  type: Joi.string()
    .valid('private', 'public')
    .required()
    .description('Message type')
    .default('private'),

  // Optional fields - exactly matching the interface
  direction: Joi.string()
    .valid('incoming', 'outgoing')
    .optional()
    .description('Message direction relative to current user'),

  status: Joi.string()
    .valid('sent', 'delivered', 'read', 'pending', 'failed')
    .required()
    .default('sent')
    .description('Message delivery status'),

  readAt: Joi.string()
    .isoDate()
    .optional()
    .description('When the message was read (ISO timestamp)')
    .allow(null)
    .default(null),
});




// Input schema for markMessagesAsRead options
export const markMessagesAsReadOptionsSchema = Joi.object({
  recipientId: Joi.string().required().messages({
    'any.required': 'recipientId is required',
    'string.base': 'recipientId must be a string',
  }),
  senderId: Joi.string().required().allow(null).messages({
    'string.base': 'the senderId must be a string or null',
  }),
  messageIds: Joi.array().items(Joi.string()).optional().allow(null).messages({
    'array.base': 'message_ids must be an array of strings',
    'string.base': 'each message_id must be a string',
  }),
});

// Output schema for markMessagesAsRead result
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
});