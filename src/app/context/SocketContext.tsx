// context/SocketContext.tsx
import { createContext, useContext, useEffect, useState, useCallback } from 'react';
import { io, Socket } from 'socket.io-client';
import { useUser, useAuth } from '@clerk/nextjs';

export interface User {
  userId: string;
  userName: string;
  state?: string;
}

export interface AuthUser extends User {
  success: boolean;
  state: 'disconnected' | 'connected' | 'authenticated' | 'offline';
}



export interface ConversationMetrics {
  startedAt: string | null;
  lastMessageAt: string | null;
  sent: number;
  pending: number;
  delivered: number;
  unread: number;
  read: number;
};

// extend user to
export interface UserConversation extends User {
  otherPartyId: string;
  otherPartyName: string;
  startedAt?: string | null;
  lastMessageAt?: string | null;
  types?: string[] | null;
}
export interface UserConversationMetrics extends UserConversation {
  incoming: ConversationMetrics | null;
  outgoing: ConversationMetrics | null;
}

export interface userConversationsResponse {
  data: UserConversationMetrics[];
  total: number;
  hasMore: boolean;
  context?: any;
}


export interface Message {
  id?: string;
  senderId: string;
  senderName: string;
  recipientId: string;
  content: string;
  timestamp: Date;
  status?: string;
  type?: 'private' | 'public';
  direction?: 'incoming' | 'outgoing';
}

export interface ConversationResponse {
  data: Message[];
  total: number;
  hasMore: boolean;
  context?: any;
}

export interface GetUserConversationOptions {
  // Pagination
  limit?: number;
  offset?: number;
  // data interval
  since?: Date | null;
  until?: Date | null;
  messageIds?: string[];
  type: 'private' | 'public';
  // message user Ids
  userId: string | null;
  otherPartyId: string | null;

  //  status?: string | null;  
  //  recipientId?: string | null;
  //  direction?: 'incoming' | 'outgoing' | null;
  //  unreadOnly?: boolean;
}

// In SocketContext.tsx - update the interface
export interface UserConversationEvent {
  success: boolean;
  data?: ConversationResponse;
  error?: string;
  options?: GetUserConversationOptions; // Add this to match server
}

export interface getUserConversationResponse {
  success: boolean;
  data: Message[],
}

// Define the default value for the context
const SocketContext = createContext<{
  socket: Socket | null;
  isConnected: boolean;
  isAuthenticated: boolean;
  socketUser: User | null;
  conversations: UserConversationMetrics[];
  getUserConversationsList: (options?: GetUserConversationsListOptions) => Promise<ConversationListResponse>;
  getUserConversation: (options: GetUserConversationOptions) => Promise<ConversationResponse>;
  connect: () => void;
  disconnect: () => void;
}>({
  socket: null,
  isConnected: false,
  isAuthenticated: false,
  socketUser: null,
  conversations: [],
  getUserConversationsList: () => { },
  getUserConversation: async () => {
    throw new Error('Socket not initialized');
  },
  connect: () => { },
  disconnect: () => { },
});

// Custom hook to use the socket context
export const useSocket = () => {
  return useContext(SocketContext);
};

// Provider component to wrap the app with the socket instance
export const SocketProvider = ({ children }: { children: React.ReactNode }) => {
  const [socket, setSocket] = useState<Socket | null>(null);
  const [isConnected, setIsConnected] = useState(false);
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const { user, isLoaded, isSignedIn } = useUser();
  const [socketUser, setSocketUser] = useState<User | null>(null);
  const [conversations, setConversations] = useState<UserConversationMetrics[]>([]);
  const { getToken } = useAuth();

  // Function to get user conversations list
  const getUserConversationsList = useCallback((options?: any) => {
    if (socket && isAuthenticated) {
      socket.emit('getUserConversationsList', options);
    }
  }, [socket, isAuthenticated]);

  // Function to get specific conversation messages
  // In SocketContext.tsx - getUserConversation function
  // Function to get specific conversation messages with complete protocol
  const getUserConversation = useCallback(async (options: GetUserConversationOptions): Promise<ConversationResponse> => {
    if (!socket || !isAuthenticated) {
      throw new Error('Socket not connected or user not authenticated');
    }

    return new Promise((resolve, reject) => {
      // Set up timeout
      const timeout = setTimeout(() => {
        reject(new Error('Request timeout'));
        socket.off('userConversation', handleResponse);
      }, 10000);

      const handleResponse = (event: UserConversationEvent) => {
        clearTimeout(timeout);
        socket.off('userConversation', handleResponse);

        // Optional: Verify this response is for our request (if you want strict matching)
        // if (event.options && JSON.stringify(event.options) !== JSON.stringify(options)) {
        //   return; // This response is for a different request
        // }

        if (event.success && event.data) {
          resolve(event.data);
        } else {
          reject(new Error(event.error || 'Failed to fetch conversation'));
        }
      };

      // Listen for the response
      socket.on('userConversation', handleResponse);

      // Emit the request
      socket.emit('getUserConversation', options);
    });
  }, [socket, isAuthenticated]);

  const connect = () => {
    if (socket && !socket.connected) {
      socket.connect();
    }
  };

  const disconnect = () => {
    if (socket) {
      socket.disconnect();
    }
  };

  useEffect(() => {
    let newSocket: Socket | null = null;

    // Function to initialize the socket connection
    const initializeSocket = async () => {
      if (!isLoaded || !isSignedIn || !user) {
        console.log('User not signed in or data not loaded yet.');
        return;
      }

      try {
        // Fetch the authentication token from Clerk
        const token = await getToken({ template: 'socket-auth' });

        // Validate the environment variable
        const socketUrl = process.env.NEXT_PUBLIC_SOCKET_URL || 'http://localhost:3001';
        if (!socketUrl) {
          throw new Error('NEXT_PUBLIC_SOCKET_URL is not defined');
        }

        // Initialize the Socket.IO client
        newSocket = io(socketUrl, {
          autoConnect: true,
          transports: ['websocket'],
          reconnectionAttempts: 5,
          reconnectionDelay: 1000,
          auth: { token },
        });

        // Set the socket instance
        setSocket(newSocket);

        // Handle connection events
        newSocket.on('connect', () => {
          console.log('Connected to Socket.IO server');
          setIsConnected(true);
        });

        newSocket.on('user_authenticated', (authUser: AuthUser) => {
          console.log('User authenticated:', authUser);
          setSocketUser(authUser);
          setIsAuthenticated(true);
        });

        // Listen for user conversations list
        newSocket.on('userConversations', (conversationsData: UserConversationMetrics[]) => {
          console.log('Received conversations:', conversationsData);
          setConversations(conversationsData);
        });

        // Note: userConversation events are handled in the getUserConversation function

        newSocket.on('disconnect', () => {
          console.log('Disconnected from Socket.IO server');
          setIsAuthenticated(false);
          setSocketUser(null);
          setIsConnected(false);
          setConversations([]);
        });

        newSocket.on('connect_error', (error) => {
          console.error('Connection error:', error.message);
        });
      } catch (error) {
        console.error('Failed to initialize socket:', error);
      }
    };

    if (isLoaded && isSignedIn && user) {
      initializeSocket();
    }

    return () => {
      if (newSocket) {
        newSocket.disconnect();
        setIsConnected(false);
      }
    };
  }, [isLoaded, isSignedIn, getToken, user?.id]);

  return (
    <SocketContext.Provider value={{
      socket,
      isConnected,
      isAuthenticated,
      socketUser,
      conversations,
      getUserConversationsList,
      getUserConversation,
      connect,
      disconnect
    }}>
      {children}
    </SocketContext.Provider>
  );
};