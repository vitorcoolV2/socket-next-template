
import { PersistenceInterface } from './PersistenceInterface.mjs'


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

export class MemoryPersistence extends PersistenceInterface {
  constructor() {
    super();
    this.users = new Map(); // Tracks users (userId -> user data)
    this.messages = new Map(); // Tracks messages (userId -> array of messages)
    console.log('✅ Using in-memory persistence (development mode)');
  }



  /**
   * Retrieve a user by their userId.
   */
  async getUser(userId) {
    if (!userId || typeof userId !== 'string') {
      throw new Error('Invalid userId provided');
    }
    return this.users.get(userId) || null;
  }


  /**
 * Add or update a user in the persistence layer.
 */
  async storeUser(user) {
    if (!user || !user.userId) {
      throw new Error('Invalid user data provided');
    }
    const existingUser = this.users.get(user.userId);
    if (existingUser) {
      // Update existing user
      this.users.set(user.userId, { ...existingUser, ...user, lastActivity: new Date() });
    } else {
      // Add new user
      this.users.set(user.userId, { ...user, lastActivity: new Date() });
    }
  }


  /**
   * Store a message in the persistence layer.
   */
  /**
   * Store a message in the persistence layer.
   */
  async storeMessage(userId, message) {
    if (!userId || typeof userId !== 'string') {
      throw new Error('Invalid userId provided');
    }
    if (!message || typeof message !== 'object') {
      throw new Error('Invalid message provided');
    }
    if (debug) {
      console.log(`Persisting message for userId: ${userId}`, message);
    }

    // Ensure metadata is serializable (if applicable)
    const sanitizedMetadata = sanitizeObject(message.metadata || {});


    // Normalize the message object
    const normalizedMessage = {
      messageId: message.messageId,
      direction: message.direction,
      sender: {
        userId: message?.sender.userId,
        userName: message?.sender.userName || 'Anonymous',
      },
      recipientId: message.recipientId,
      type: message.type,
      content: message.content,
      status: message.status,
      timestamp: message.timestamp,
      readAt: message.readAt,
      meta: JSON.stringify({ // Fixed syntax here
        ...sanitizedMetadata,
      }),
    };

    // Initialize the user's message array if necessary
    if (!this.messages.has(userId)) {
      this.messages.set(userId, []);
    }

    const userMessages = this.messages.get(userId);

    // Check if the message already exists
    const existingMessageIndex = userMessages.findIndex(
      m => m.messageId === normalizedMessage.messageId && m.direction === normalizedMessage.direction
    );

    if (existingMessageIndex !== -1) {
      // Update the existing message
      userMessages[existingMessageIndex] = normalizedMessage;
    } else {
      // Add the new message
      userMessages.push(normalizedMessage);
    }

    // Log the operation
    if (debug) {
      console.log(`Upserted message ${normalizedMessage.messageId} for user ${userId} in memory persistence`);
    }

    return normalizedMessage;
  }


  /**
   * Retrieve messages for a user based on filters.
   */
  async getMessages(userId, options = {}) {
    if (!userId || typeof userId !== 'string') {
      throw new Error('Invalid userId provided');
    }

    if (debug) {
      console.log(`Fetching messages for userId: ${userId} with options:`, options);
    }

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
      status = null,
      direction = null,
      unreadOnly = false,
      otherPartyId = null,
    } = validOps;

    // Determine the recipientId for the query
    const recipientId = type === 'public' ? PUBLIC_MESSAGE_USER_ID : userId;

    // Fetch user messages from persistence
    const userMessages = this.messages.get(recipientId) || [];

    // Apply filters
    let filteredMessages = userMessages.filter(msg => {
      if (status && msg.status !== status) return false;
      if (unreadOnly && msg.readAt) return false;
      if (direction && msg.direction !== direction) return false;
      if (type && msg.type !== type) return false;
      if (since && new Date(msg.timestamp) < new Date(since)) return false;
      if (until && new Date(msg.timestamp) > new Date(until)) return false;
      if (type !== 'public' && otherPartyId && (
        msg.recipientId !== otherPartyId &&
        msg.sender.senderId !== otherPartyId
      )) return false;
      return true;
    });



    // Sort by timestamp (newest first)
    filteredMessages.sort((a, b) => {
      const timeDiff = new Date(b.timestamp) - new Date(a.timestamp);
      if (timeDiff !== 0) return timeDiff; // Primary sort by timestamp
      // Secondary sort by direction (optional)
      if (a.direction === 'incoming' && b.direction === 'outgoing') return -1;
      if (a.direction === 'outgoing' && b.direction === 'incoming') return 1;
      return 0;
    });

    // Calculate total count and pagination
    const total = filteredMessages.length;
    const paginatedMessages = filteredMessages.slice(offset, offset + limit);

    // Determine if there are more messages
    const hasMore = total > offset + limit;

    // Debugging logs
    if (debug) {
      console.log(`Fetched ${userMessages.length} messages for userId: ${recipientId}`);
      console.log(`Filtered ${filteredMessages.length} messages after applying options`);
    }

    // Return the structured response
    return {
      messages: paginatedMessages,
      total,
      hasMore,
    };
  }


  async updateMessageStatus(userId, messageIds, status) {
    if (!this.messages.has(userId)) {
      console.warn(`No messages found for userId: ${userId}`);
      return [];
    }

    const userMessages = this.messages.get(userId);
    const updatedMessageIds = [];

    userMessages.forEach(msg => {
      if (Array.isArray(messageIds) && messageIds.includes(msg.messageId)) {
        msg.status = status; // Update the status
        updatedMessageIds.push(msg.messageId); // Track updated messages
      }
    });

    if (debug) {
      console.log(
        `Updated status to "${status}" for messages: ${updatedMessageIds.join(', ')} for userId: ${userId}`
      );
    }

    return updatedMessageIds;
  }

  async markMessagesAsRead(userId, options) {

    const { direction = 'incoming', messageIds = null } = options;
    // Step 1: Validate inputs
    if (!userId || typeof userId !== 'string') {
      throw new Error('Invalid userId provided');
    }
    if (messageIds !== null && (!Array.isArray(messageIds) || !messageIds.every(id => typeof id === 'string'))) {
      throw new Error('Invalid messageIds provided');
    }
    if (direction && !['incoming', 'outgoing'].includes(direction)) {
      throw new Error('Invalid direction provided. Must be "incoming" or "outgoing".');
    }

    // Step 2: Retrieve messages for the user
    const userMessages = this.messages.get(userId);
    if (!userMessages || userMessages.length === 0) {
      console.warn(`No messages found for userId: ${userId}`);
      return { marked: 0, total: messageIds?.length || 0 }; // No messages to update
    }

    // Step 3: Update the readAt field for matching messages
    let markedCount = 0;
    userMessages.forEach(msg => {
      const matchesMessageIds = Array.isArray(messageIds) && messageIds.includes(msg.messageId);
      const matchesDirection = direction && msg.direction === direction;

      // A message is includable if:
      // - messageIds is provided and the messageId matches, OR
      // - messageIds is NOT provided and the direction matches
      const includable = matchesMessageIds || (!messageIds && matchesDirection);

      if (includable) {
        msg.readAt = new Date().toISOString(); // Use consistent ISO 8601 date formatting
        markedCount++;
      }
    });

    // Step 4: Log and return the result
    if (debug) {
      console.log(
        `Marked ${markedCount} messages as read for user ${userId}`,
        `Matching message IDs: ${messageIds ? messageIds.join(', ') : 'all'}`,
        `Direction: ${direction || 'any'}`
      );
    }

    return {
      marked: markedCount,
      total: messageIds?.length || 0,
    };
  }

  /**
   * Cleanup inactive users from the persistence layer.
   */
  async cleanupInactiveUserSessions(inactiveTime = 30 * 60 * 1000) {
    const cutoff = Date.now() - inactiveTime;
    let cleaned = 0;

    for (const [userId, user] of this.users.entries()) {
      if (user.lastActivity < cutoff) {
        this.users.delete(userId);
        cleaned++;
      }
    }

    return cleaned;
  }

  /**
   * Cleanup old messages from the persistence layer.
   */
  async cleanupOldMessages(maxAge = 7 * 24 * 60 * 60 * 1000) {
    const cutoff = Date.now() - maxAge;
    let cleaned = 0;

    for (const [userId, messages] of this.messages.entries()) {
      const originalLength = messages.length;
      this.messages.set(
        userId,
        messages.filter(msg => new Date(msg.timestamp) >= cutoff)
      );
      cleaned += originalLength - this.messages.get(userId).length;
    }

    return cleaned;
  }

  async getUnreadMessages(userId, options = {}) {
    const { conversationPartnerId, direction, messageIds } = options;

    // Step 1: Validate inputs
    if (!userId || typeof userId !== 'string') {
      throw new Error('Invalid userId provided');
    }
    if (direction && !['incoming', 'outgoing'].includes(direction)) {
      throw new Error('Invalid direction provided. Must be "incoming" or "outgoing".');
    }
    if (messageIds && (!Array.isArray(messageIds) || !messageIds.every(id => typeof id === 'string'))) {
      throw new Error('Invalid messageIds provided');
    }

    // Step 2: Check if the user has messages
    if (!this.messages.has(userId)) {
      return [];
    }

    // Step 3: Retrieve user messages
    const userMessages = this.messages.get(userId);

    // Step 4: Apply filters
    return userMessages.filter(msg => {
      const matchesConversation = !conversationPartnerId || msg.sender.userId === conversationPartnerId;
      const matchesDirection = !direction || msg.direction === direction;
      const matchesMessageIds = !messageIds || messageIds.includes(msg.messageId);
      const isUnread = !msg.readAt; // Ensure the message is unread

      // Combine all conditions
      return isUnread && matchesConversation && matchesDirection && matchesMessageIds;
    });
  }


}