// context/SocketContext.tsx
import { createContext, useContext, useEffect, useState, useCallback } from 'react';
import { io, Socket } from 'socket.io-client';
import { useUser, useAuth } from '@clerk/nextjs';

export interface User {
  userId: string;
  userName: string;
  state: 'disconnected' | 'connected' | 'authenticated' | 'offline';
}

export interface AuthUser extends User {
  success: boolean;
}

export interface ConversationMetrics {
  startedAt: string;
  lastMessageAt: string;
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
  startedAt: string;
  lastMessageAt: string;
  types?: string[] | null;
}
export interface UserConversationMetrics extends UserConversation {
  incoming: ConversationMetrics;
  outgoing: ConversationMetrics;
}

export interface UserRenderData extends User, UserConversationMetrics {
  startedAt: string;
  lastMessageAt: string;
  types: string[];
};

export type MessageStatus = 'sent' | 'pending' | 'delivered' | 'read';

export interface Message {
  id?: string;
  senderId: string;
  senderName: string;
  recipientId: string;
  content: string;
  status?: MessageStatus;
  type?: 'private' | 'public';
  direction?: 'incoming' | 'outgoing';
  createdAt?: Date;
  updatedAt?: Date;
  readdAt?: Date;
}

export interface GetUserConversationResponse {
  data: Message[];
  total: number;
  hasMore: boolean;
  context?: unknown;
}

export interface FetchGetUserConversationOptions {
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
}

// In SocketContext.tsx - update the interface
export interface UserConversationEvent {
  success: boolean;
  data?: GetUserConversationResponse;// ['data'];
  error?: string;
  options?: FetchGetUserConversationOptions; // Add this to match server
}


export interface getUserConversationResponse {
  success: boolean;
  data: Message[],
}

interface ContextData {
  [key: string]: string | number | boolean; // Adjust based on your needs
}

// conversations list
export interface UserConversationsListResponse {
  data: UserConversationMetrics[];
  total: number;
  hasMore: boolean;
  context?: ContextData;
}

export interface FetchGetUserConversationsListOptions {
  limit?: number;
  offset?: number;
  since?: Date | null;
  until?: Date | null;
  userId?: string | null;
  otherPartyId?: string | null;
  type?: 'private' | 'public';
  sortBy?: 'lastMessageAt' | 'startedAt';
  sortOrder?: 'asc' | 'desc';
}

export interface UserConversationsListResponse {
  data: UserConversationMetrics[];
  total: number;
  hasMore: boolean;
  context?: ContextData;
}

// In SocketContext.tsx - update the interface
export interface UserConversationsListEvent {
  success: boolean;
  data?: GetUserConversationResponse; //['data'];
  error?: string;
  options?: FetchGetUserConversationsListOptions; // Add this to match server
}

export interface FetchGetUsersListOptions {
  limit?: number;
  offset?: number;
  since?: Date | null;
  until?: Date | null;
  type?: 'private' | 'public';
}

export interface getUsersListResponse {
  data: UserRenderData[];
}

export interface UsersListEvent {
  success: boolean;
  data?: getUsersListResponse
  error?: string;
  options?: FetchGetUsersListOptions;
}

// Define the default value for the context
const SocketContext = createContext<{
  socket: Socket | null;
  isConnected: boolean;
  isAuthenticated: boolean;
  socketUser: User | null;
  conversationsList: UserConversationMetrics[];
  getUsersList: (options?: FetchGetUsersListOptions) => Promise<UserRenderData[]>;
  getUserConversationsList: (options?: FetchGetUserConversationsListOptions) => Promise<void>;
  getUserConversation: (options: FetchGetUserConversationOptions) => Promise<GetUserConversationResponse>;
  connect: () => void;
  disconnect: () => void;
}>({
  socket: null,
  isConnected: false,
  isAuthenticated: false,
  socketUser: null,
  conversationsList: [],
  getUsersList: async () => {
    throw new Error('Socket not initialized'); // Default implementation throws an error
  },
  getUserConversationsList: async () => {
    throw new Error('Socket not initialized'); // Default implementation throws an error
  },
  getUserConversation: async () => {
    throw new Error('Socket not initialized'); // Default implementation throws an error
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

  const [isLoading, setIsLoading] = useState(true);
  const { user, isLoaded, isSignedIn } = useUser();
  const [socketUser, setSocketUser] = useState<User | null>(null);
  const [usersState, setUsersState] = useState<User[]>([]);
  const [conversationsList, setConversationsList] = useState<UserRenderData[]>([]);
  const { getToken } = useAuth();

  // Function to get user conversations list
  const getUserConversationsList = useCallback(async (options?: FetchGetUserConversationsListOptions): Promise<void> => {
    if (!socket || !isAuthenticated) {
      throw new Error('Socket not connected or user not authenticated');
    }
    socket.emit('getUserConversationsList', options);

  }, [socket, isAuthenticated]);

  // Function to get specific conversation messages
  // In SocketContext.tsx - getUserConversation function
  // Function to get specific conversation messages with complete protocol
  const getUsersList = useCallback(async (options?: FetchGetUsersListOptions): Promise<UserRenderData[]> => {
    if (!socket || !isAuthenticated) {
      throw new Error('Socket not connected or user not authenticated');
    }

    return new Promise((resolve, reject) => {
      // Set up timeout for the request
      const timeout = setTimeout(() => {
        reject(new Error('Request timeout'));
        socket.off('usersList', handleResponse); // Clean up the listener
      }, 10000); // 10 seconds timeout

      // Define the response handler
      const handleResponse = (event: UsersListEvent) => {
        clearTimeout(timeout); // Clear the timeout
        socket.off('usersList', handleResponse); // Remove the listener
        if (event.success && event.data) {
          setUsersState(event.data);
          resolve(event.data); // Resolve with the fetched users
        } else {
          reject(new Error(event.error || 'Failed to fetch users list'));
        }
      };

      // Listen for the server's response
      socket.on('usersList', handleResponse);

      // Emit the request to the server
      socket.emit('getUsersList', options);
    });
  }, [socket, isAuthenticated, usersState]);

  // Function to get specific conversation messages
  // In SocketContext.tsx - getUserConversation function
  // Function to get specific conversation messages with complete protocol
  const getUserConversation = useCallback(async (options: FetchGetUserConversationOptions): Promise<GetUserConversationResponse> => {
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
    if (isLoaded && isAuthenticated) {
      getUsersList()
      getUserConversationsList({ limit: 50, offset: 0 });
    }
  }, [isLoaded, isAuthenticated]);

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
          setSocketUser(authUser);
          setIsAuthenticated(true);
          setIsLoading(false);

        });

        // Listen for user conversations list
        newSocket.on('userConversationsList', (conversationsData: UserRenderData[]) => {
          console.log('Received conversations:', conversationsData);
          setConversationsList(conversationsData);
        });

        // Note: userConversation events are handled in the getUserConversation function

        newSocket.on('disconnect', () => {
          console.log('Disconnected from Socket.IO server');
          setIsAuthenticated(false);
          setSocketUser(null);
          setIsConnected(false);
          setConversationsList([]);
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
  }, [isLoaded, isSignedIn, getToken, user, user?.id]);

  return (
    <SocketContext.Provider value={{
      socket,
      isConnected,
      isAuthenticated,
      socketUser,
      conversationsList,
      getUsersList,
      getUserConversationsList,
      getUserConversation,
      connect,
      disconnect
    }}>
      {children}
    </SocketContext.Provider>
  );
};