// src/app/chat/ChatWrapper.tsx
'use client';

import React, { useState } from 'react';
import { SocketProvider } from '../context/SocketContext';
import { ChatProvider } from '../context/ChatContext';
import Chat from './Chat';
import UserList from './UsersList';

export default function ChatWrapper() {
  const [recipientId, setRecipientId] = useState<string | null>(null);

  return (
    <SocketProvider>
      <ChatProvider>
        <div style={{ display: 'flex', height: '100vh' }}>
          {/* User List */}
          <UserList setRecipient={(userId) => setRecipientId(userId)} />

          {/* Chat Area */}
          <div style={{ flex: 1, padding: '1rem' }}>
            {recipientId ? (
              <Chat recipientId={recipientId} />
            ) : (
              <p>Select a user to start chatting.</p>
            )}
          </div>
        </div>
      </ChatProvider>
    </SocketProvider>
  );
}