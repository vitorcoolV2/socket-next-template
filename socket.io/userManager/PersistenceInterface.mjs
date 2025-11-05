/* eslint-disable @typescript-eslint/no-unused-vars */

/**
 * Abstract base class for persistence layers.
 * Defines the required methods for user management and messaging.
 */
export class PersistenceInterface {
  constructor() {
    if (new.target === PersistenceInterface) {
      throw new Error("PersistenceInterface is an abstract class and cannot be instantiated directly.");
    }
  }

  /**
   * Initialize the database or storage system.
   * @returns {Promise<void>}
   */
  async initializeDatabase() {
    throw new Error("Method 'initializeDatabase()' must be implemented.");
  }

  /**
   * Ensure the database or storage system is initialized before performing operations.
   * @returns {Promise<void>}
   */
  async ensureInitialized() {
    throw new Error("Method 'ensureInitialized()' must be implemented.");
  }

  /**
   * Store a user in the persistence layer.
   * @param {Object} user - The user object to store.
   * @returns {Promise<Object>} - The stored user object.
   */
  async storeUser(user) {
    throw new Error("Method 'storeUser()' must be implemented.");
  }

  /**
   * Store a message in the persistence layer.
   * @param {string} userId - The ID of the user associated with the message.
   * @param {Object} message - The message object to store.
   * @returns {Promise<Object>} - The stored message object.
   */
  async storeMessage(userId, message) {
    throw new Error("Method 'storeMessage()' must be implemented.");
  }

  /**
   * Mark messages as read for a user.
   * @param {string} userId - The ID of the user.
   * @param {Object} options - Options containing message IDs.
   * @returns {Promise<Object>} - The result of marking messages as read.
   */
  async markMessagesAsRead(userId, options) {
    throw new Error("Method 'markMessagesAsRead()' must be implemented.");
  }

  /**
   * Mark messages as delivered for a user.
   * @param {string} userId - The ID of the user.
   * @param {Object} options - Options containing message IDs.
   * @returns {Promise<Object>} - The result of marking messages as delivered.
   */
  async markMessagesAsDelivered(userId, options) {
    throw new Error("Method 'markMessagesAsDelivered()' must be implemented.");
  }

  /**
   * Retrieve active users from the persistence layer.
   * @returns {Promise<Array>} - An array of active user objects.
   */
  async getActiveUsers() {
    throw new Error("Method 'getActiveUsers()' must be implemented.");
  }

  /**
   * Retrieve users based on specified options.
   * @param {Object} options - Query options.
   * @returns {Promise<Array>} - An array of user objects.
   */
  async getUsers(options = {}) {
    throw new Error("Method 'getUsers()' must be implemented.");
  }

  /**
   * Retrieve a list of conversations for a user.
   * @param {Object} options - Query options.
   * @returns {Promise<Array>} - An array of conversation objects.
   */
  async getUserConversationsList(options = {}) {
    throw new Error("Method 'getUserConversationsList()' must be implemented.");
  }

  /**
   * Retrieve messages for a user based on specified options.
   * @param {string} userId - The ID of the user.
   * @param {Object} options - Query options.
   * @returns {Promise<Object>} - Paginated result of message objects.
   */
  async getMessages(userId, options = {}) {
    throw new Error("Method 'getMessages()' must be implemented.");
  }

  /**
   * Perform cleanup of inactive user sessions.
   * @param {number} inactiveTime - Time in milliseconds after which a session is considered inactive.
   * @returns {Promise<number>} - The number of sessions cleaned up.
   */
  async cleanupInactiveUserSessions(inactiveTime = 30 * 60 * 1000) {
    throw new Error("Method 'cleanupInactiveUserSessions()' must be implemented.");
  }

  /**
   * Perform cleanup of old messages.
   * @param {number} maxAge - Maximum age in milliseconds for messages to retain.
   * @returns {Promise<number>} - The number of messages cleaned up.
   */
  async cleanupOldMessages(maxAge = 365 * 24 * 60 * 60 * 1000) {
    throw new Error("Method 'cleanupOldMessages()' must be implemented.");
  }

  /**
   * Update the status of a message.
   * @param {string} userId - The ID of the user.
   * @param {string} messageId - The ID of the message.
   * @param {string} status - The new status to set.
   * @param {Array<string>} fromStatus - The current statuses to update from.
   * @returns {Promise<Array>} - Updated message objects.
   */
  async updateMessageStatus(userId, messageId, status, fromStatus = []) {
    throw new Error("Method 'updateMessageStatus()' must be implemented.");
  }

  /**
   * Perform a health check on the persistence layer.
   * @returns {Promise<Object>} - Health check result.
   */
  async healthCheck() {
    throw new Error("Method 'healthCheck()' must be implemented.");
  }

  /**
   * Close the connection to the persistence layer.
   * @returns {Promise<void>}
   */
  async close() {
    throw new Error("Method 'close()' must be implemented.");
  }
}