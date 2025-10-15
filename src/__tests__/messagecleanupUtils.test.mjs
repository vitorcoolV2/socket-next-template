import { cleanupOldMessages } from '../../socket.io/userManager/messageCleanupUtils.mjs';

describe('Message Cleanup Utility', () => {
  let userMessages;

  beforeEach(() => {
    // Mock userMessages Map
    userMessages = new Map();

    // Add some messages for testing
    userMessages.set('user-123', [
      {
        messageId: 'recent-msg',
        content: 'Recent message',
        timestamp: new Date().toISOString(),
      },
      {
        messageId: 'old-msg',
        content: 'Old message',
        timestamp: new Date(Date.now() - 8 * 24 * 60 * 60 * 1000).toISOString(), // 8 days ago
      },
    ]);
  });

  test('should clean up old messages', () => {
    // Perform cleanup with a 7-day threshold
    const cleanedCount = cleanupOldMessages(userMessages, false, 7 * 24 * 60 * 60 * 1000);

    expect(cleanedCount).toBe(1); // One old message should be removed

    // Verify that only the recent message remains
    const remainingMessages = userMessages.get('user-123');
    expect(remainingMessages.length).toBe(1);
    expect(remainingMessages[0].messageId).toBe('recent-msg');
  });

  test('should not remove any messages if all are recent', () => {
    // Perform cleanup with a 10-day threshold
    const cleanedCount = cleanupOldMessages(userMessages, false, 10 * 24 * 60 * 60 * 1000);

    expect(cleanedCount).toBe(0); // No messages should be removed

    // Verify that both messages remain
    const remainingMessages = userMessages.get('user-123');
    expect(remainingMessages.length).toBe(2);
  });
});