// src/app/utils/types.ts

export type ConnectionStatus = 'disconnected' | 'connecting' | 'connected' | 'authenticated';

export interface AuthenticationMessage {
  success: boolean,
  userId: string,
  userName: string,
  sessionId: string;
  state?: ConnectionStatus;
  error?: { message: string; code?: string } | string;
}

export interface Sender {
  userId: string; // Unique identifier for the user
  userName: string; // Display name or username of the user
}

/**
 * Interface for active users.
 */
export interface ActiveUser extends Sender {
  sessionId?: string; // Optional session ID for tracking user sessions
  connectedAt?: string; // Timestamp when the user connected (optional)
  lastActivity?: string; // Timestamp of the user's last activity (optional)
}
export interface User extends Sender {
  state: ConnectionStatus;
  sesionId?: string;
  socketId?: string;
}


export interface GetHistoryOptions {
  userId: string;
  limit: number;
  offset: number;
  type?: string;
  otherId?: string;
}
export interface GetMessageHistoryParams {
  limit: number;
  offset: number;
  since?: number;
  until?: number;
  type: 'private' | 'public';
  userId: string;
}

export interface GetMessageHistoryResponse {
  messages: (PublicMessage | PrivateMessage)[];
  total?: number; // Make total optional
  hasMore?: boolean; // Make hasMore optional
  pagination?: {
    hasMore: boolean;
  };
}

// Define types for message cache and getUserConversation
export interface MessageCache {
  [userId: string]: {
    messages: (PublicMessage | PrivateMessage)[];
    offset: number;
    hasMore: boolean;
    lastLoaded: number;
  };
}

/**
 * Interface for public messages.
 */
export interface PublicMessage {
  messageId: string;
  sender: {
    userId: string;
    userName: string;
  };
  content: string;
  timestamp: string;
  type: 'public';
}

/**
 * Interface for private messages.
 */
export interface PrivateMessage {
  messageId: string;
  sender: {
    userId: string;
    userName: string;
  };
  recipientId: string;
  content: string;
  timestamp: string;
  isPrivate: boolean;
  type: 'private';
  direction?: 'incoming' | 'outgoing';
  status: 'sent' | 'delivered' | 'read' | 'pending' | 'failed';
  readAt?: string;
}

export interface SocketResponse {
  success: boolean; // Indicates whether the operation was successful
  status: 'success' | 'error' | 'exception';
  event: string;
  timestamp: string;
  data?: unknown;
  message?: string;
  error?: {
    message: string; // Error message
    code?: string; // Optional error code
    details?: Record<string, unknown>; // Additional error details (optional)
  } | string;
}

/**
 * Interface for typing indicator data.
 */
export interface TypingIndicatorData {
  sender: string; // ID of the user who is typing
  senderName: string; // Name of the user who is typing
  isTyping: boolean; // Whether the user is currently typing
  recipientId?: string; // Optional ID of the recipient (for private chats)
  timestamp: string; // Timestamp of the typing event
}