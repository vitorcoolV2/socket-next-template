// context/SocketContext.tsx
import { createContext, useContext, useEffect, useState, useCallback } from 'react';
import { io, Socket } from 'socket.io-client';
import { useUser, useAuth } from '@clerk/nextjs';
import { success } from 'zod';
import { bool, boolean, string } from 'joi';

export type UserState = 'disconnected' | 'connected' | 'authenticated' | 'offline';

// Define TypeScript interfaces
export interface User {
  userId: string;
  userName: string;
  state: UserState;
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
}


export interface MessageAck {
  success: boolean;
  message: string;
}

export type MessageType = 'private' | 'public';

export interface UserConversation extends User {
  otherPartyId: string;
  otherPartyName: string;
  startedAt: string;
  lastMessageAt: string;
  types: MessageType[];
}

export interface UserConversationMetrics extends UserConversation {
  incoming: ConversationMetrics;
  outgoing: ConversationMetrics;
}

export interface UserRenderData extends User, UserConversationMetrics {
  startedAt: string;
  lastMessageAt: string;
  types: MessageType[];
}

export type MessageStatus = 'sent' | 'pending' | 'delivered' | 'read';


export type MessageDirection = 'incoming' | 'outgoing';

export interface Message {
  id?: string;
  senderId: string;
  senderName: string;
  recipientId: string;
  content: string;
  status?: MessageStatus;
  type?: MessageType;
  direction?: MessageDirection;
  createdAt?: Date;
  updatedAt?: Date;
  readAt?: Date;
}

export interface UserConversationMessages {
  messages: Message[];
}

export interface GetUserConversationResponse extends UserConversationMessages {
  //  messages: Message[];
  total: number;
  hasMore: boolean;
  context?: unknown;
}

export interface FetchGetUserConversationOptions {
  limit?: number;
  offset?: number;
  since?: Date | null;
  until?: Date | null;
  messageIds?: string[];
  type: MessageType;
  userId: string | null;
  otherPartyId: string | null;
}

export interface BaseEvent {
  success: boolean;
  event: string;
  result: Message;
  error?: string;
}

export interface UserConversationMessageEvent extends BaseEvent { };

export interface FetchGetUserConversationsListOptions {
  limit?: number;
  offset?: number;
  since?: Date | null;
  until?: Date | null;
  userId?: string | null;
  otherPartyId?: string | null;
  type?: MessageType;
  sortBy?: 'lastMessageAt' | 'startedAt';
  sortOrder?: 'asc' | 'desc';
}

export interface UserConversationsListResponse {
  data: UserConversationMetrics[];
  total: number;
  hasMore: boolean;
  context?: unknown;
}

export interface UserConversationsListEvent {
  success: boolean;
  data?: UserConversationsListResponse;
  error?: string;
  options?: FetchGetUserConversationsListOptions;
}


export interface FetchGetUsersListOptions {
  limit?: number;
  offset?: number;
  since?: Date | null;
  until?: Date | null;
  state?: Array<'authenticated' | 'offline'>;
}

export interface GetUsersListResponse {
  data: UserRenderData[];  //UserConversationsListResponse;
}

export interface UsersListEvent {
  success: boolean;
  data?: GetUsersListResponse;
  error?: string;
  options?: FetchGetUsersListOptions;
}


// Create Context
interface SocketContextType {
  socket: Socket | null;
  isConnected: boolean;
  isAuthenticated: boolean;
  socketUser: User | null;
  conversationsList: UserRenderData[];  // context responsable for deliver final conversations List
  // do not need to expose getUsersList,getUserConversationsList. Keep commented 
  // getUsersList: (options?: FetchGetUsersListOptions) => Promise<GetUsersListResponse>;
  //getUserConversationsList: (options?: FetchGetUserConversationsListOptions) => Promise<UserConversationsListResponse>;
  getUserConversation: (options: FetchGetUserConversationOptions) => Promise<GetUserConversationResponse>;
  connect: () => void;
  disconnect: () => void;
}

const SocketContext = createContext<SocketContextType>({
  socket: null,
  isConnected: false,
  isAuthenticated: false,
  socketUser: null,
  conversationsList: [],
  /*getUsersList: async () => {
    throw new Error('Socket not initialized');
  },
  getUserConversationsList: async () => {
    throw new Error('Socket not initialized');
  },*/
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
  const [isLoading, setIsLoading] = useState(true);
  const { user, isLoaded, isSignedIn } = useUser();
  const [socketUser, setSocketUser] = useState<User | null>(null);

  const [conversationsList, setConversationsList] = useState<UserRenderData[]>([]);
  const { getToken } = useAuth();

  // Utility function for handling socket responses
  const handleSocketResponseData = useCallback(<T,>(
    eventName: string,
    emitEvent: string,
    payload: unknown,
    timeoutMs = 10000,
  ): Promise<T> => {

    return new Promise((resolve, reject) => {
      if (!socket) {
        reject(new Error('Socket not connected'));
        return;
      }

      const timeout = setTimeout(() => {
        reject(new Error('Request timeout'));
        socket.off(eventName, handleResponse);
      }, timeoutMs);

      const handleResponse = (event: { success: boolean; data?: T; error?: string }) => {
        clearTimeout(timeout);
        socket.off(eventName, handleResponse);
        if (event.success && event.data !== undefined) {
          resolve(event.data);
        } else {
          reject(new Error(event.error || 'Failed to fetch data'));
        }
      };
      console.log('handleSocketResponseData', eventName, emitEvent, timeoutMs);
      socket.on(eventName, handleResponse);
      socket.emit(emitEvent, payload);
    });
  }, [socket]);


  // Function to get system users list
  const getUsersList = useCallback(
    async (options?: FetchGetUsersListOptions): Promise<GetUsersListResponse['data']> => {
      if (!socket || !isAuthenticated) {
        throw new Error('Socket not connected or user not authenticated');
      }
      try {
        const data = await handleSocketResponseData<GetUsersListResponse['data']>(
          'usersList',
          'getUsersList',
          options
        );
        return data;
      } catch (error) {
        console.error('Failed to get users list:', error);
        throw error;
      }
    },
    [socket, isAuthenticated, handleSocketResponseData]
  );

  const userRenderDataDefaults = (
    userId: string,
    userName: string,
    otherPartyId: string,
    otherPartyName: string,
    state: UserState = 'offline', // Default state is explicitly typed as UserState
    types: MessageType[] = ['private'] // Default type is 'private'
  ): UserRenderData => {
    // Validate and sanitize the types array
    const validatedTypes = (types || []).filter(
      (type): type is MessageType => ['private', 'public'].includes(type)
    );

    return {
      userId,
      userName,
      otherPartyId,
      otherPartyName,
      state, // Already correctly typed as UserState
      types: validatedTypes.length > 0 ? validatedTypes : ['private'], // Ensure at least one valid type
      startedAt: '',
      lastMessageAt: '',
      incoming: {
        startedAt: '',
        lastMessageAt: '',
        sent: 0,
        pending: 0,
        delivered: 0,
        unread: 0,
        read: 0,
      },
      outgoing: {
        startedAt: '',
        lastMessageAt: '',
        sent: 0,
        pending: 0,
        delivered: 0,
        unread: 0,
        read: 0,
      },
    };
  };

  const addAndMergeSystemUserState = (
    users: UserRenderData[], // Fetched users from getUsersList
    prevConv: UserRenderData[] // Previous conversations
  ): UserRenderData[] => {
    if (!socketUser) {
      return []; // Return an empty array if there's no logged-in user
    }

    // Step 1: Update existing conversations with user state
    const updatedConversations = prevConv.map((conversation) => {
      const matchingUser = users.find((user) => user.userId === conversation.otherPartyId);
      if (matchingUser) {
        return {
          ...conversation,
          state: matchingUser.state, // Update the state of the existing conversation
        };
      }
      return conversation; // No matching user, leave the conversation unchanged
    });

    // Step 2: Add new users as conversations
    const newConversations = users
      .filter((user) => !prevConv.some((conv) => conv.otherPartyId === user.userId))
      .map((user) => {
        return userRenderDataDefaults(
          socketUser?.userId || '',
          socketUser?.userName || '',
          user.userId,
          user.userName,
          user.state,
          ['private'],
        );
      });

    // Step 3: Combine updated and new conversations
    return [...updatedConversations, ...newConversations];
  };


  // Merge fetched users into conversations list
  const addAndMergeConversationsListStats = (
    conversations: UserConversationMetrics[], // Fetched conversations from getUserConversationsList
    prevConv: UserRenderData[] // Previous conversations
  ): UserRenderData[] => {
    if (!socketUser) {
      return []; // Return an empty array if there's no logged-in user
    }

    // Step 1: Update existing conversations with new metrics
    const updatedConversations = prevConv.map((conversation) => {
      const matchingConversation = conversations.find(
        (conv) => conv.otherPartyId === conversation.otherPartyId
      );
      if (matchingConversation) {
        return {
          ...conversation,
          startedAt: matchingConversation.startedAt || conversation.startedAt, // Update or retain existing value
          lastMessageAt: matchingConversation.lastMessageAt || conversation.lastMessageAt, // Update or retain existing value
          incoming: {
            ...conversation.incoming,
            ...matchingConversation.incoming, // Merge incoming metrics
          },
          outgoing: {
            ...conversation.outgoing,
            ...matchingConversation.outgoing, // Merge outgoing metrics
          },
          types: matchingConversation.types || conversation.types, // Update or retain types
          state: matchingConversation.state || conversation.state, // Update or retain state
        };
      }
      return conversation; // No matching conversation, leave it unchanged
    });

    // Step 2: Add new conversations from the fetched data
    const newConversations = conversations
      .filter((conv) => !socketUser?.userId && !prevConv.some((c) => c.otherPartyId === conv.otherPartyId))
      .map((conv) =>
        userRenderDataDefaults(
          socketUser?.userId || '', // Ensure non-null userId
          socketUser?.userName || '', // Ensure non-null userName
          conv.otherPartyId,
          conv.otherPartyName,
          conv.state || 'offline', // Default to 'offline' if state is undefined
          conv.types || ['private'] // Use fetched types or default to ['private']
        )
      );

    // Step 3: Combine updated and new conversations
    return [...updatedConversations, ...newConversations];
  };

  // Function to get user conversations list
  const getUserConversationsList = useCallback(
    async (options?: FetchGetUserConversationsListOptions): Promise<UserConversationsListResponse['data']> => {
      if (!socket || !isAuthenticated) {
        throw new Error('Socket not connected or user not authenticated');
      }
      try {
        const data = await handleSocketResponseData<UserConversationsListResponse['data']>(
          'userConversationsList',
          'getUserConversationsList',
          options
        );
        return data;
      } catch (error) {
        console.error('Failed to get user conversations list:', error);
        throw error;
      }
    },
    [socket, isAuthenticated, handleSocketResponseData]
  );

  // Function to get specific conversation messages
  const getUserConversation = useCallback(
    async (options: FetchGetUserConversationOptions): Promise<GetUserConversationResponse> => {
      if (!socket || !isAuthenticated) {
        throw new Error('Socket not connected or user not authenticated');
      }
      try {
        const resp = await handleSocketResponseData<GetUserConversationResponse>(
          'userConversation',
          'getUserConversation',
          options
        );
        return resp;
      } catch (error) {
        console.error('Failed to get user conversation:', error);
        throw error;
      }
    },
    [socket, isAuthenticated, handleSocketResponseData]
  );

  const connect = useCallback(() => {
    if (socket && !socket.connected) {
      socket.connect();
    }
  }, [socket]);

  const disconnect = useCallback(() => {
    if (socket) {
      socket.disconnect();
    }
  }, [socket]);

  // Load data when authenticated
  useEffect(() => {
    if (isLoaded && isAuthenticated) {
      Promise.all([
        getUsersList({ state: ['authenticated', 'offline'] }), // Fetch users
        getUserConversationsList({ limit: 50, offset: 0 }), // Fetch conversations
      ])
        .then(([usersData, conversationsData]) => {
          // Update the state using functional setState
          setConversationsList((prevConversationsList) => {
            // Step 1: Merge fetched users into the existing list
            const mergedUsers = addAndMergeSystemUserState(usersData, prevConversationsList);

            // Step 2: Merge fetched conversations into the updated list
            const finalConversations = addAndMergeConversationsListStats(
              conversationsData,
              mergedUsers
            );

            // Return the final merged list
            return finalConversations;
          });
        })
        .catch((error) => {
          console.error('Failed to fetch users or conversations:', error);
        });
    }
  }, [isLoaded, isAuthenticated, getUsersList, getUserConversationsList]);

  // ACK message received
  useEffect(() => {
    if (!isAuthenticated || !socket || !socketUser) return;

    const handleUpdateMessageStatus = (msg: Message, ack: Function) => {
      console.log('Received updateMessageStatus event:', msg);

      if (ack && msg && socketUser && msg.recipientId === socketUser.userId) {
        console.log('Invoking ack with:', { success: true, message: 'received' });
        ack({ success: true, message: 'received' });
      } else {

        console.warn('Acknowledgment callback or recipient ID mismatch:', { ack, msg, socketUser });
      }
    };

    socket.on('update_message_status', handleUpdateMessageStatus);

    return () => {
      socket.off('update_message_status', handleUpdateMessageStatus);
    };
  }, [socket, isAuthenticated, socketUser]);

  useEffect(() => {
    if (!socket) return;

    const handleUserStateUpdated = (updatedUser: UserConversation) => {
      console.log('User state updated:', updatedUser);

      // Update the local state to reflect the new user state
      setConversationsList((prevConversations) =>
        prevConversations.map((conv) =>
          conv.otherPartyId === updatedUser.userId
            ? { ...conv, state: updatedUser.state }
            : conv
        )
      );
    };

    // Listen for user state updates
    socket.on('user_state_updated', handleUserStateUpdated);

    // Cleanup listener on unmount
    return () => {
      socket.off('user_state_updated', handleUserStateUpdated);
    };
  }, [socket]);


  // Initialize socket connection
  useEffect(() => {
    let newSocket: Socket | null = null;
    let isMounted = true;

    const initializeSocket = async () => {
      if (!isLoaded || !isSignedIn || !user) {
        console.log('User not signed in or data not loaded yet.');
        return;
      }

      try {
        const token = await getToken({ template: 'socket-auth' });
        const socketUrl = process.env.NEXT_PUBLIC_SOCKET_URL || 'http://localhost:3001';

        if (!socketUrl) {
          throw new Error('NEXT_PUBLIC_SOCKET_URL is not defined');
        }

        newSocket = io(socketUrl, {
          autoConnect: true,
          transports: ['websocket'],
          reconnectionAttempts: 5,
          reconnectionDelay: 1000,
          auth: { token },
        });

        if (!isMounted) return;
        setSocket(newSocket);

        newSocket.on('connect', () => {
          console.log('Connected to Socket.IO server');
          setIsConnected(true);
        });

        newSocket.on('user_authenticated', (authUser: AuthUser) => {
          if (authUser.success && authUser.userId === user.id) {
            setSocketUser(authUser);
            setIsAuthenticated(true);
          }
          setIsLoading(false);
        });

        newSocket.on('disconnect', () => {
          console.log('Disconnected from Socket.IO server');
          setIsAuthenticated(false);
          setSocketUser(null);
          setIsConnected(false);
        });

        newSocket.on('connect_error', (error) => {
          console.error('Connection error:', error.message);
          setIsLoading(false);
        });




      } catch (error) {
        console.error('Failed to initialize socket:', error);
        if (isMounted) {
          setIsLoading(false);
        }
      }
    };

    if (isLoaded && isSignedIn && user) {
      initializeSocket();
    } else {
      setIsLoading(false);
    }

    return () => {
      isMounted = false;
      if (newSocket) {
        newSocket.disconnect();
      }
    };
  }, [isLoaded, isSignedIn, getToken, user]);

  const contextValue: SocketContextType = {
    socket,
    // connection
    isConnected,
    isAuthenticated,
    socketUser,
    conversationsList,
    // getUsersList,
    //  getUserConversationsList,
    getUserConversation,
    connect,
    disconnect,
  };

  return (
    <SocketContext.Provider value={contextValue}>
      {children}
    </SocketContext.Provider>
  );
};