'use client';

import { useEffect } from 'react';
import { useUser, useAuth } from '@clerk/nextjs';
import Chat from './components/Chat';
import { SocketProvider } from './components/SocketContext';

export default function ChatWrapper() {
  const { isLoaded, isSignedIn, user } = useUser();
  const { getToken } = useAuth();

  const logState = (message: string, data?: object) => {
    if (process.env.NODE_ENV === 'development') {
      console.log(message, data);
    }
  };

  useEffect(() => {
    let intervalId: NodeJS.Timeout;

    const checkToken = async () => {
      try {
        const token = await getToken({ template: 'socket-auth' });
        if (!token) {
          console.error('❌ Authentication token is missing.');
        } else {
          logState('✅ Successfully fetched authentication token.');
        }
      } catch (error) {
        console.error('❌ Failed to fetch authentication token:', error);
      }
    };

    if (isLoaded && isSignedIn) {
      checkToken();
      intervalId = setInterval(checkToken, 15 * 60 * 1000); // Refresh every 15 minutes
    }

    return () => clearInterval(intervalId); // Cleanup interval on unmount
  }, [isLoaded, isSignedIn, getToken]);

  useEffect(() => {
    if (process.env.NODE_ENV === 'development' && isLoaded) {
      logState('ChatWrapper: Clerk state', {
        isLoaded,
        isSignedIn,
        user: {
          id: user?.id || 'Not signed in',
          userName: user?.username || user?.firstName || 'Guest',
          primaryEmailAddress: user?.primaryEmailAddress?.emailAddress || 'No email',
        },
      });
    }

    if (isLoaded && isSignedIn && !user?.id) {
      console.error('❌ User ID is undefined despite being signed in.');
    }
  }, [isLoaded, isSignedIn, user]);

  return (
    <SocketProvider>
      <Chat />
    </SocketProvider>
  );
}