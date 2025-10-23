// context/SocketContext.tsx
import { createContext, useContext, useEffect, useState } from 'react';
import { io, Socket } from 'socket.io-client';
import { useUser, useAuth } from '@clerk/nextjs';

export interface User {
  userId: string;
  userName: string;
  state: 'disconnected' | 'connected' | 'authenticated' | 'offline';
}

export interface AuthUser extends User {
  success: boolean,
}

// Define the default value for the context
const SocketContext = createContext<{
  socket: Socket | null;
  isConnected: boolean;
  isAuthenticated: boolean;
  socketUser: User | null;
}>({
  socket: null, // Default socket value
  isConnected: false, // Default connection status
  isAuthenticated: false,
  socketUser: null,
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
  const { user, isLoaded, isSignedIn } = useUser(); // clerk usefulls  
  const [socketUser, setSocketUser] = useState<User | null>(null); // Fix: Use array destructuring
  const { getToken } = useAuth();

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
          auth: {
            token, // Pass the token for authentication            
          },
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
          setSocketUser(authUser); // Update the authenticated user
          setIsAuthenticated(true);
        });

        newSocket.on('disconnect', () => {
          console.log('Disconnected from Socket.IO server');
          setIsAuthenticated(false);
          setSocketUser(null);
          setIsConnected(false);

        });

        newSocket.on('connect_error', (error) => {
          console.error('Connection error:', error.message);
        });
      } catch (error) {
        console.error('Failed to initialize socket:', error.message);
      }
    };

    // Initialize the socket connection
    // Initialize the socket connection only if the user is signed in and data is loaded
    if (isLoaded && isSignedIn && user) {
      initializeSocket();
    }

    // Cleanup on unmount
    return () => {
      if (newSocket) {
        newSocket.disconnect();
        setIsConnected(false);
      }
    };
  }, [isLoaded, isSignedIn, getToken, user?.id]); // Re-run effect if user signs in/out or user ID changes

  // Provide the socket and connection status to the context
  return (
    <SocketContext.Provider value={{ socket, isConnected, isAuthenticated, socketUser }}>
      {children}
    </SocketContext.Provider>
  );
};