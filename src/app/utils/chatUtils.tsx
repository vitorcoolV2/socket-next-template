import { PublicMessage, PrivateMessage, MessageCache, Sender } from './types';

const debug = false;

export const getCurrentMessages = (
  selectedUser: string | null,
  privateConversations: { [userId: string]: PrivateMessage[] },
  messageCacheRef: React.RefObject<MessageCache>,
): PrivateMessage[] => {
  if (!selectedUser) return [];

  // Get messages from privateConversations or cache
  const cachedMessages = messageCacheRef.current[selectedUser]?.messages || [];
  const conversationMessages = privateConversations[selectedUser] || [];

  // Combine messages
  const allMessages = [...cachedMessages, ...conversationMessages];

  // Filter out non-private messages with proper type guard
  const privateMessages = allMessages.filter((msg): msg is PrivateMessage =>
    'recipientId' in msg && 'isPrivate' in msg
  );

  // Sort messages chronologically
  return privateMessages.sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime());
};


export const getUserPreviewMessage = (
  userId: string,
  privateConversations: Record<string, (PublicMessage | PrivateMessage)[]>,
  socketId: string | undefined,
  messageCacheRef: React.RefObject<MessageCache>
): PublicMessage | PrivateMessage | undefined => {
  // Retrieve cached and real-time messages
  const cache = messageCacheRef.current?.[userId];
  const realTimeMessages = privateConversations[userId] || [];

  if (debug) console.log('Cache Messages:', cache?.messages);
  if (debug) console.log('Real-Time Messages:', realTimeMessages);

  // Combine and sort messages
  const allMessages = [...(cache?.messages || []), ...realTimeMessages]
    .filter((msg) => msg.timestamp) // Ensure messages have a valid timestamp
    .sort((a, b) => {
      const dateA = new Date(a.timestamp || 0).getTime();
      const dateB = new Date(b.timestamp || 0).getTime();
      return dateA - dateB;
    });

  if (debug) console.log('All Messages:', allMessages);

  // Return the first message, or undefined if none exist
  return allMessages.length > 0 ? allMessages[0] : undefined;
};

/**
 * Helper function to generate a unique ID for messages.
 */
export const generateUniqueId = (): string => {
  return Math.random().toString(36).substr(2, 9);
};

export const createPrivateMessage = (
  recipientId: string,
  content: string,
  sender: Sender,
): PrivateMessage => ({
  isPrivate: true,
  messageId: generateUniqueId(),
  type: 'private',
  timestamp: new Date().toISOString(),
  content,
  sender,
  recipientId,
});

export const createPublicMessage = (content: string, sender: Sender): PublicMessage => ({
  messageId: generateUniqueId(),
  type: 'public',
  timestamp: new Date().toISOString(),
  content,
  sender,
});


export const isPrivateMessage = (msg: PrivateMessage | PublicMessage): msg is PrivateMessage => {
  return (msg as PrivateMessage).recipientId !== undefined &&
    (msg as PrivateMessage).isPrivate !== undefined;
};