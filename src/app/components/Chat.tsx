import React, { useState } from 'react';
import ActiveUsersList from './ActiveUsersList';
import PrivateChat from './PrivateChat';
import { useSocketContext } from './SocketContext';

const Chat = () => {
  const { activeUsers, me } = useSocketContext();
  const [selectedUser, setSelectedUser] = useState<string | null>(null);

  const handleUserSelect = (userId: string) => {
    setSelectedUser(userId);
  };

  return (
    <div className="flex h-screen bg-gray-900 text-white">
      {/* Active Users Sidebar */}
      <ActiveUsersList
        activeUsers={activeUsers}
        selectedUser={selectedUser}
        handleUserSelect={handleUserSelect}
        me={me}
      />

      {/* Private Chat - All logic moved inside */}
      <div className="flex h-screen flex-col flex-grow">
        <PrivateChat
          me={me}
          selectedUser={selectedUser}
        />
      </div>
    </div>
  );
};

export default Chat;