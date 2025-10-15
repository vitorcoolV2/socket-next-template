import React from 'react';
import { useSocketContext } from './SocketContext';
import { getUserPreviewMessage } from '../utils/chatUtils';
import ConnectionStatusIndicator from './ConnectionStatusIndicator';
import { ActiveUser } from '../utils/types';

//const debug = true;

interface ActiveUsersListProps {
    activeUsers: ActiveUser[];
    selectedUser: string | null;
    handleUserSelect: (userId: string) => void; // Triggered when a user is clicked
    me: ActiveUser | null;
}

const ActiveUsersList: React.FC<ActiveUsersListProps> = ({
    activeUsers,
    selectedUser,
    handleUserSelect,
    me,
}) => {
    const { socket, privateConversations } = useSocketContext();
    const messageCacheRef = React.useRef({});

    return (
        <>
            {me !== null ? (
                <div className="w-80 bg-gray-800 border-r border-gray-700 sticky top-0 h-screen overflow-y-auto flex-shrink-0">
                    {/* Sticky Header */}
                    <div className="p-4 border-b border-gray-700 sticky top-0 bg-gray-800 z-10">
                        <div className="flex items-center justify-between mb-2">
                            <h2 className="text-lg font-bold text-white">Online Users</h2>
                            <ConnectionStatusIndicator />
                        </div>
                        <p className="text-sm text-gray-400">
                            {activeUsers.length} user{activeUsers.length !== 1 ? 's' : ''} online
                        </p>
                    </div>

                    {/* Scrollable Users List */}
                    <div className="p-3">
                        {activeUsers.length > 0 ? (
                            activeUsers.map((user) => {
                                const previewMessage = getUserPreviewMessage(
                                    user.userId,
                                    privateConversations,
                                    socket?.id,
                                    messageCacheRef
                                );
                                const unreadCount =
                                    privateConversations[user.userId]?.filter(
                                        (msg) => !msg.readAt && msg.recipientId === me.userId
                                    ).length || 0;
                                const isMe = user.userId === me.userId;

                                return (
                                    <div
                                        key={user.userId}
                                        className={`p-3 rounded-lg cursor-pointer transition-all duration-200 mb-2 ${selectedUser === user.userId
                                                ? 'bg-blue-600 text-white shadow-lg'
                                                : 'bg-gray-700 hover:bg-gray-600 text-gray-200'
                                            } ${isMe ? 'border-l-4 border-green-500' : ''}`}
                                        onClick={() => handleUserSelect(user.userId)}
                                    >
                                        <div className="flex justify-between items-start">
                                            <div className="flex items-center space-x-2 flex-1 min-w-0">
                                                {/* Online Indicator */}
                                                <div className="w-2 h-2 bg-green-500 rounded-full flex-shrink-0"></div>

                                                <div className="flex-1 min-w-0">
                                                    <div className="font-medium truncate text-sm">
                                                        {user.userName || user.userId}
                                                        {isMe && ' (You)'}
                                                    </div>
                                                </div>
                                            </div>

                                            {/* Unread Count Badge */}
                                            {unreadCount > 0 && (
                                                <span className="bg-red-500 text-white text-xs rounded-full px-2 py-1 min-w-[20px] text-center flex-shrink-0 ml-2">
                                                    {unreadCount}
                                                </span>
                                            )}
                                        </div>

                                        {/* Preview Message */}
                                        {previewMessage && (
                                            <div className="text-xs mt-2 truncate break-words max-w-full">
                                                <strong className={selectedUser === user.userId ? 'text-blue-100' : 'text-gray-400'}>
                                                    {previewMessage.sender?.userId === me.userId
                                                        ? 'You: '
                                                        : ''}
                                                </strong>
                                                <span className={selectedUser === user.userId ? 'text-blue-100' : 'text-gray-400'}>
                                                    {previewMessage.content}
                                                </span>
                                            </div>
                                        )}
                                    </div>
                                );
                            })
                        ) : (
                            <div className="text-center py-8">
                                <p className="text-gray-400">No active users</p>
                                <p className="text-gray-500 text-sm mt-1">Users will appear here when they come online</p>
                            </div>
                        )}
                    </div>
                </div>
            ) : (
                <div className="w-80 bg-gray-800 border-r border-gray-700 sticky top-0 h-screen flex items-center justify-center">
                    <p className="text-gray-500">Loading...</p>
                </div>
            )}
        </>
    );
};

export default ActiveUsersList;