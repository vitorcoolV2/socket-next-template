export class PersistenceInterface {
  async storeUser(user) {
    throw new Error('Method "storeUser" must be implemented');
  }

  async getUser(userId) {
    throw new Error('Method "getUser" must be implemented');
  }


  async storeMessage(userId, message) {
    throw new Error('Method "storeMessage" must be implemented');
  }

  async getMessages(userId, options = {}) {
    throw new Error('Method "getMessages" must be implemented');
  }

  async markMessagesAsRead(userId, messageIds) {
    throw new Error('Method "markMessagesAsRead" must be implemented');
  }

  async updateMessageStatus(userId, messageIds, status) {
    throw new Error('Method "setMessagesStatus" must be implemented');
  }

  async cleanupInactiveUserSessions(inactiveTime) {
    throw new Error('Method "cleanupInactiveUserSessions" must be implemented');
  }

  async cleanupOldMessages(maxAge) {
    throw new Error('Method "cleanupOldMessages" must be implemented');
  }
}