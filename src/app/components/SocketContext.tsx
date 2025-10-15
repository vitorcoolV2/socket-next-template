'use client';

import { createContext, useContext, useEffect, useState, useCallback, useRef } from 'react';
import io, { Socket } from 'socket.io-client';
import { useUser, useAuth } from '@clerk/nextjs';
import debounce from 'debounce';
import {
  PrivateMessage,
  ActiveUser,
  TypingIndicatorData,
  SocketResponse,
  AuthenticationMessage,
  GetHistoryOptions,
  GetMessageHistoryResponse
} from '../utils/types';
import { createPrivateMessage } from '../utils/chatUtils';

// Context Type Definition
interface SocketContextValue {
  socket: Socket | null;
  isAuthenticated: boolean;
  me: ActiveUser | null;
  connectionStatus: 'disconnected' | 'connecting' | 'connected' | 'authenticated';
  activeUsers: ActiveUser[];
  privateConversations: { [userId: string]: PrivateMessage[] };
  typingIndicators: { [userId: string]: boolean };
  pendingMessages: PrivateMessage[];

  sendPrivateMessage: (recipientId: string, content: string) => Promise<void>;
  getMessageHistory: (options: GetHistoryOptions) => Promise<GetMessageHistoryResponse>;
  addPrivateMessage: (userId: string, message: PrivateMessage, source?: string) => void;
  markMessagesAsRead: (messageIds: string[]) => Promise<{ marked: number }>;
  setTypingIndicator: (isTyping: boolean, recipientId?: string) => void;
  getActiveUsers: () => Promise<ActiveUser[]>;
  connectSocket: () => void;
  disconnectSocket: () => void;
  setPrivateConversations: React.Dispatch<
    React.SetStateAction<{ [userId: string]: PrivateMessage[] }>
  >;
}

// Create the Context
const SocketContext = createContext<SocketContextValue | null>(null);

// Custom Hook to Use the Context
export const useSocketContext = () => {
  const context = useContext(SocketContext);
  if (!context) throw new Error('useSocketContext must be used within a SocketProvider');
  return context;
};

// Define proper types for socket events
interface MessageData {
  content: string;
  replyTo?: string;
}

interface PrivateMessageData {
  recipientId: string;
  content: string;
}

interface MarkMessagesReadData {
  messageIds: string[];
}

interface TypingIndicatorDataEvent {
  isTyping: boolean;
  recipientId: string;
}

type SocketEventData =
  | MessageData
  | PrivateMessageData
  | MarkMessagesReadData
  | TypingIndicatorDataEvent
  | GetHistoryOptions
  | Record<string, never>;

// Provider Component
export const SocketProvider = ({ children }: { children: React.ReactNode }) => {
  const [socket, setSocket] = useState<Socket | null>(null);
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [me, setMe] = useState<ActiveUser | null>(null);
  const [connectionStatus, setConnectionStatus] = useState<'disconnected' | 'connecting' | 'connected' | 'authenticated'>('disconnected');
  const [activeUsers, setActiveUsers] = useState<ActiveUser[]>([]);
  const [privateConversations, setPrivateConversations] = useState<{ [userId: string]: PrivateMessage[] }>({});
  const [typingIndicators, setTypingIndicators] = useState<{ [userId: string]: boolean }>({});
  const [pendingMessages] = useState<PrivateMessage[]>([]);

  const debug = true;
  const { user, isLoaded, isSignedIn } = useUser();
  const [initialized, setInitialized] = useState(false);
  const { getToken } = useAuth();
  const [addedMessages, setAddedMessages] = useState<Set<string>>(new Set());

  const SOCKET_URL = process.env.NEXT_PUBLIC_SOCKET_URL || 'http://localhost:3001';

  // Use refs for values that don't need to trigger re-renders
  const privateConversationsRef = useRef(privateConversations);
  const socketRef = useRef(socket);
  const isAuthenticatedRef = useRef(isAuthenticated);

  // Track currently loading users to prevent duplicates
  const loadingUsersRef = useRef<Set<string>>(new Set());

  // Keep refs in sync with state
  useEffect(() => {
    privateConversationsRef.current = privateConversations;
    socketRef.current = socket;
    isAuthenticatedRef.current = isAuthenticated;
  }, [privateConversations, socket, isAuthenticated]);

  // Utility Function: Emit Event with Callback - FIXED: Removed 'any' type
  const emitWithCallback = useCallback(<T,>(
    event: string,
    data: SocketEventData,
    timeout = 10000
  ): Promise<T> => {
    return new Promise((resolve, reject) => {
      if (!socketRef.current || !socketRef.current.connected) {
        reject(new Error('Socket not connected'));
        return;
      }

      const timer = setTimeout(() => {
        reject(new Error(`Socket event ${event} timed out after ${timeout}ms`));
      }, timeout);

      socketRef.current.emit(event, data, (response: SocketResponse) => {
        clearTimeout(timer);

        if (response.success) {
          resolve(response.data as T);
        } else {
          const errorMessage = typeof response.error === 'string'
            ? response.error
            : response.error?.message || `Socket event ${event} failed`;

          reject(new Error(errorMessage));
        }
      });
    });
  }, []);

  const addPrivateMessage = useCallback(
    (userId: string, message: PrivateMessage, source?: string) => {
      // Validate userId
      if (!userId || userId === 'undefined') {
        console.error(`❌ Invalid userId provided from ${source}:`, userId, 'Skipping message:', message);
        return;
      }

      // Enhanced deduplication: Check both global set AND current conversations
      if (addedMessages.has(message.messageId)) {
        console.warn(`⚠️ Duplicate message skipped (global dedup) from ${source}:`, {
          userId,
          messageId: message.messageId,
          content: message.content,
        });
        return;
      }

      // Update the state of private conversations
      setPrivateConversations((prev) => {
        const conversation = prev[userId] || [];
        const seenMessageIds = new Set(conversation.map((msg) => msg.messageId));

        if (seenMessageIds.has(message.messageId)) {
          console.warn(`⚠️ Duplicate message skipped (local conversation) from ${source}:`, {
            userId,
            messageId: message.messageId,
            content: message.content,
          });
          return prev;
        }

        // Add to the global set
        setAddedMessages((prevSet) => {
          const newSet = new Set(prevSet);
          newSet.add(message.messageId);
          return newSet;
        });

        console.log(`✅ Adding message from ${source}:`, {
          userId,
          messageId: message.messageId,
          content: message.content,
        });

        return {
          ...prev,
          [userId]: [...conversation, message],
        };
      });

      // Persist to localStorage using ref to avoid dependency on state
      const currentConversations = privateConversationsRef.current;
      const updatedConversations = {
        ...currentConversations,
        [userId]: [...(currentConversations[userId] || []), message],
      };
      try {
        localStorage.setItem('privateConversations', JSON.stringify(updatedConversations));
      } catch (error) {
        console.error(`❌ Failed to persist to localStorage from ${source}:`, error);
      }
    },
    [addedMessages]
  );

  // Ensure the user is fully loaded before initializing the socket
  useEffect(() => {
    if (!isLoaded) return;

    console.log('✅ User state fully loaded:', {
      isLoaded,
      isSignedIn,
      userId: user?.id,
    });

    // Initialize the socket and state only after the user is fully loaded
    setInitialized(true);
  }, [isLoaded, isSignedIn, user]);

  // Handle Typing Indicator Events
  useEffect(() => {
    if (!socket) return;

    const handleTypingIndicator = (response: SocketResponse) => {
      if (response.success) {
        const data = response.data as TypingIndicatorData;

        // Update typing indicators for the sender
        setTypingIndicators((prev) => ({
          ...prev,
          [data.sender]: data.isTyping,
        }));
      }
    };

    socket.on('typingIndicator', handleTypingIndicator);

    return () => {
      socket.off('typingIndicator', handleTypingIndicator);
    };
  }, [socket]);

  // Initialize the Socket Connection
  useEffect(() => {
    if (!isLoaded || !isSignedIn || !user?.id) return;

    const initializeSocket = async () => {
      try {
        const token = await getToken({ template: 'socket-auth' });
        if (!token) throw new Error('Authentication token is missing.');

        const socketInstance = io(SOCKET_URL, {
          transports: ['websocket', 'polling'],
          reconnection: true,
          reconnectionAttempts: 5,
          reconnectionDelay: 2000,
          auth: { token },
        });

        setSocket(socketInstance);
        setConnectionStatus('connecting');

        // Handle Connection Events
        socketInstance.on('connect', () => {
          if (debug) console.log('✅ Socket connected:', socketInstance.id);
          setConnectionStatus('connected');
        });

        socketInstance.on('disconnect', (reason) => {
          if (debug) console.log('❌ Socket disconnected. Reason:', reason);
          setIsAuthenticated(false);
          setConnectionStatus('disconnected');
          setActiveUsers([]);
        });

        socketInstance.on('authenticated', (response: AuthenticationMessage) => {
          if (response.success) {
            if (debug) console.log('✅ Authentication successful:', response);

            setIsAuthenticated(true);
            setMe({
              userId: response.userId,
              userName: response.userName,
              sessionId: response.sessionId,
            });

            setConnectionStatus('authenticated');
          } else {
            console.error('❌ Authentication failed:', response.error);
          }
        });

        socketInstance.on('activeUsers', (response: SocketResponse) => {
          if (response.success && Array.isArray(response.data)) {
            setActiveUsers(response.data as ActiveUser[]);
          }
        });

        socketInstance.on('private_message', (response: SocketResponse) => {
          if (!response.success) {
            console.error('❌ Failed to process private_message event:', response.error);
            return;
          }

          const message = response.data as PrivateMessage;

          // Validate sender's userId
          if (!message.sender?.userId || message.sender.userId === 'undefined') {
            console.error('❌ Invalid sender userId in private_message event:', message);
            return;
          }

          // FIX: Skip messages that are older than 2 seconds (likely historical duplicates)
          const messageAge = Date.now() - new Date(message.timestamp).getTime();
          const isLikelyHistorical = messageAge > 2000; // 2 seconds threshold

          if (isLikelyHistorical) {
            console.log('⏸️ Skipping likely historical message from socket:', {
              userId: message.sender.userId,
              messageId: message.messageId,
              content: message.content,
              age: `${messageAge}ms`,
            });
            return;
          }

          // Use addPrivateMessage to ensure deduplication
          addPrivateMessage(message.sender.userId, message, 'private_message');
        });

        return () => {
          socketInstance.disconnect();
          setSocket(null);
          setIsAuthenticated(false);
          setConnectionStatus('disconnected');
        };
      } catch (error) {
        console.error('Failed to initialize socket:', error);
      }
    };

    initializeSocket();
  }, [isLoaded, isSignedIn, user, getToken, SOCKET_URL, debug, addPrivateMessage]);

  // Persist conversations to localStorage
  useEffect(() => {
    const cleanedConversations = Object.fromEntries(
      Object.entries(privateConversations).map(([userId, messages]) => {
        const seenMessageIds = new Set<string>();
        const uniqueMessages = messages.filter((msg: PrivateMessage) => {
          const messageId = msg.messageId;
          return !seenMessageIds.has(messageId) && seenMessageIds.add(messageId);
        });

        console.log('🧹 Removed duplicates before saving to localStorage:', {
          userId,
          duplicatesRemoved: messages.length - uniqueMessages.length,
        });

        return [userId, uniqueMessages];
      })
    );

    try {
      localStorage.setItem('privateConversations', JSON.stringify(cleanedConversations));
    } catch (error) {
      console.error('❌ Failed to persist conversations to localStorage:', error);
    }
  }, [privateConversations]);

  // Fetch Message History - Updated to track loading state
  const getMessageHistory = useCallback(
    async (options: GetHistoryOptions) => {
      const { userId } = options;

      // Mark this user as currently loading
      loadingUsersRef.current.add(userId);

      try {
        const response = await emitWithCallback<GetMessageHistoryResponse>(
          'getMessageHistory',
          options
        );
        return response;
      } catch (error) {
        console.error('Error fetching message history:', error);
        throw error;
      } finally {
        // Remove from loading set when done
        loadingUsersRef.current.delete(userId);
      }
    },
    [emitWithCallback]
  );

  // Create a ref for `me`
  const meRef = useRef<ActiveUser | null>(null);
  useEffect(() => {
    meRef.current = me;
  }, [me]);

  const sendPrivateMessage = useCallback(
    (recipientId: string, content: string): Promise<void> => {
      const meId = meRef.current?.userId;
      if (!user?.id) {
        return Promise.reject(new Error("unexpected error - no user id defined"));
      }

      if (!recipientId) {
        console.error('❌ Invalid recipientId provided to sendPrivateMessage:', recipientId);
        return Promise.reject(new Error("Invalid recipientId"));
      }

      // Check socket connection
      if (!socketRef.current || !socketRef.current.connected) {
        const error = new Error('Socket not connected');
        console.error('❌ Socket not connected when trying to send message:', {
          recipientId,
          content,
          socketConnected: socketRef.current?.connected,
        });
        return Promise.reject(error);
      }

      const outgoingMessage = createPrivateMessage(recipientId, content, {
        userId: user.id,
        userName: user?.username || 'Guest',
      });

      console.log('📤 Sending private message:', {
        recipientId,
        messageId: outgoingMessage.messageId,
        content: outgoingMessage.content,
        socketConnected: socketRef.current.connected,
        socketId: socketRef.current.id,
      });

      // Add message optimistically to local state immediately
      addPrivateMessage(recipientId, { ...outgoingMessage, status: 'sending' }, 'sendPrivateMessage_optimistic');

      return emitWithCallback<void>('private_message', { recipientId, content }, 15000) // 15 second timeout
        .then(() => {
          console.log('✅ Private message sent successfully');
          // Optionally update status to 'sent' if you want to track delivery
        })
        .catch((error) => {
          console.error('❌ Failed to send private message:', {
            recipientId,
            messageId: outgoingMessage.messageId,
            content: outgoingMessage.content,
            error: error.message,
            errorStack: error.stack,
            socketConnected: socketRef.current?.connected,
            socketId: socketRef.current?.id,
          });

          // Update message status to failed
          addPrivateMessage(recipientId, { ...outgoingMessage, status: 'failed' }, 'sendPrivateMessage_failed');

          throw error;
        });
    },
    [emitWithCallback, user, addPrivateMessage]
  );

  // Load conversations from localStorage on mount
  useEffect(() => {
    try {
      const savedConversations = localStorage.getItem('privateConversations');
      if (savedConversations) {
        const parsedConversations = JSON.parse(savedConversations) as { [userId: string]: PrivateMessage[] };

        // Remove invalid userIds and deduplicate messages
        const cleanedConversations = Object.fromEntries(
          Object.entries(parsedConversations).map(([userId, messages]) => {
            const seenMessageIds = new Set<string>();
            const uniqueMessages = messages.filter((msg: PrivateMessage) => {
              const messageId = msg.messageId;
              return !seenMessageIds.has(messageId) && seenMessageIds.add(messageId);
            });

            console.log('🧹 Removed duplicates from localStorage for user:', {
              userId,
              duplicatesRemoved: messages.length - uniqueMessages.length,
            });

            return [userId, uniqueMessages];
          })
        );

        localStorage.setItem('privateConversations', JSON.stringify(cleanedConversations));
        setPrivateConversations(cleanedConversations);
      }
    } catch (error) {
      console.error('❌ Failed to clean up localStorage:', error);
    }
  }, []);

  const markMessagesAsRead = useCallback(
    (messageIds: string[]) => emitWithCallback<{ marked: number }>('markMessagesRead', { messageIds }),
    [emitWithCallback]
  );

  // FIXED: Properly handle debounce dependency
  const setTypingIndicator = useCallback(
    (isTyping: boolean, recipientId?: string) => {
      if (!recipientId || !isAuthenticatedRef.current) return;

      // Create debounced function inline to avoid dependency issues
      const debouncedEmit = debounce(() => {
        socketRef.current?.emit('typingIndicator', { isTyping, recipientId });
      }, 300);

      debouncedEmit();
    },
    [] // No dependencies needed since we use refs
  );

  const getActiveUsers = useCallback(() =>
    emitWithCallback<ActiveUser[]>('getActiveUsers', {}),
    [emitWithCallback]
  );

  // Manual Connection Control
  const connectSocket = useCallback(() => {
    if (!socket || socket.connected) return;
    socket.connect();
    setConnectionStatus('connecting');
  }, [socket]);

  const disconnectSocket = useCallback(() => {
    if (!socket || socket.disconnected) return;
    socket.disconnect();
    setConnectionStatus('disconnected');
  }, [socket]);

  // Provide Context Value
  const contextValue: SocketContextValue = {
    socket,
    isAuthenticated,
    me,
    connectionStatus,
    activeUsers,
    privateConversations,
    typingIndicators,
    pendingMessages,
    sendPrivateMessage,
    addPrivateMessage,
    getMessageHistory,
    markMessagesAsRead,
    setTypingIndicator,
    getActiveUsers,
    connectSocket,
    disconnectSocket,
    setPrivateConversations,
  };

  if (!isLoaded || !initialized) {
    return (
      <div className="flex justify-center items-center h-screen">
        Loading...
      </div>
    );
  }

  return <SocketContext.Provider value={contextValue}>{children}</SocketContext.Provider>;
};