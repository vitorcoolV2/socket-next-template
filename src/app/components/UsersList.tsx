import React, { useEffect, useState, useMemo } from 'react';
import { useSocket, AuthUser, ConversationMetrics, UserConversationMetrics, UserConversationEvent } from '../context/SocketContext';
import { ConnectionStatusIndicator } from './ConnectionStatusIndicator';

interface UserListProps {
    setRecipient: (userId: string) => void;
}

const UserList = ({ setRecipient }: UserListProps) => {
    const { socket, isConnected, isAuthenticated, socketUser } = useSocket();
    const [users, setUsers] = useState<UserConversationMetrics[]>([]);
    const [selectedUserId, setSelectedUserId] = useState<string | null>(null);

    // Priority mapping for user states
    const statePriority: Record<AuthUser['state'], number> = useMemo(
        () => ({
            authenticated: 1,
            offline: 2,
            connected: 3,
            disconnected: 4,
        }),
        []
    );

    // Sort users based on their state priority
    const sortedUsers = useMemo(() => {
        return [...users].sort((a, b) => statePriority[a.state] - statePriority[b.state]);
    }, [users, statePriority]);

    useEffect(() => {
        if (!socket || !isConnected || !isAuthenticated) return;

        console.log('Requesting users list...');
        socket.emit('getUsers', { states: ['authenticated', 'offline'], limit: 50, offset: 0 });
        setTimeout(() => {
            socket.emit('getUserConversationsList', { limit: 50, offset: 0 });
        }, 250);

        const handleUsersList = (fetchedUsers: UserConversationMetrics[]) => {
            console.log('Received users list:', fetchedUsers);
            setUsers(fetchedUsers);
        };

        const handleUserStateUpdate = (updatedUser: AuthUser) => {
            console.log('Received user state update:', updatedUser);
            setUsers((prevUsers) =>
                prevUsers.map((user) =>
                    user.userId === updatedUser.userId ? { ...user, state: updatedUser.state } : user
                )
            );
        };

        const handleUsersConversations = (response: UserConversationEvent) => {
            console.log('Received user conversation metrics:', response);
            if (!response?.success || !Array.isArray(response.data)) {
                console.error('Invalid conversations data received:', response);
                return;
            }

            const conversations: UserConversationMetrics[] = response.data;
            if (conversations.length === 0) return;

            setUsers((prevUsers) =>
                prevUsers.map((prevUser) => {
                    // Find the relevant conversation for the socket user
                    const theSenderUser = conversations.find((c) => c.userId === socketUser?.userId);
                    const theOtherPartyUser = conversations.find((c) => c.otherPartyId === prevUser.userId);

                    if (!theSenderUser || !theOtherPartyUser) return prevUser;

                    // Update the user's conversation metrics
                    return {
                        ...prevUser,
                        incoming: theOtherPartyUser.incoming,
                        outgoing: theOtherPartyUser.outgoing,
                        startedAt: theOtherPartyUser.startedAt,
                        lastMessageAt: theOtherPartyUser.lastMessageAt,
                    };
                })
            );
        };

        const handleNewMessageCount = (msg: { sender: { userId: string }; recipientId: string; status: string }) => {
            console.log('Received new message:', msg);

            if (!socketUser) return;

            setUsers((prevUsers) =>
                prevUsers.map((user) => {
                    const isSender = user.userId === msg.sender.userId;
                    const isRecipient = user.userId === msg.recipientId;

                    if (!isSender && !isRecipient) return user;

                    // Update unread message count for the relevant user
                    return isRecipient
                        ? {
                            ...user,
                            incoming: {
                                ...(user.incoming || {}),
                                sent: (user.incoming?.sent || 0) + (msg.status === 'sent' ? 1 : 0),
                                pending: (user.incoming?.pending || 0) + (msg.status === 'pending' ? 1 : 0),
                            },
                        }
                        : user;
                })
            );
        };

        socket.on('usersList', handleUsersList);
        socket.on('userStateUpdate', handleUserStateUpdate);
        socket.on('userConversations', handleUsersConversations);
        socket.on('receivedMessage', handleNewMessageCount);

        return () => {
            socket.off('usersList', handleUsersList);
            socket.off('userStateUpdate', handleUserStateUpdate);
            socket.off('userConversations', handleUsersConversations);
            socket.off('receivedMessage', handleNewMessageCount);
        };
    }, [socket, isConnected, isAuthenticated, socketUser]);

    const handleUserClick = (userId: string) => {
        setSelectedUserId(userId);
        setRecipient(userId);
    };

    // Memoized rendering of individual user items
    // Memoized rendering of individual user items
    const RenderUser = React.memo(({ user }: { user: AuthUser & Partial<UserConversationMetrics> }) => {
        const incoming: ConversationMetrics | undefined = user.incoming;
        const outgoing: ConversationMetrics | undefined = user.outgoing;
        const isSocketUser = user.userId === socketUser?.userId;
        const isSelfConversation = user.userId === socketUser?.userId;

        // For self-conversations: only show incoming stats
        if (isSelfConversation) {
            return (
                <li
                    key={user.userId}
                    className={`cursor-pointer p-2 rounded transition-colors ${user.userId === selectedUserId
                        ? 'bg-blue-100 dark:bg-blue-900'
                        : 'hover:bg-gray-50 dark:hover:bg-gray-700'
                        }`}
                    onClick={() => handleUserClick(user.userId)}
                >
                    <div className="flex justify-between items-center">
                        <div>
                            <strong className="font-medium dark:text-gray-200">{user.userName} (Me)</strong> - {' '}
                            <span
                                className={`text-xs px-1.5 py-0.5 rounded-full ${user.state === 'authenticated'
                                    ? 'bg-green-200 text-green-800 dark:bg-green-800 dark:text-green-200'
                                    : 'bg-gray-200 text-gray-600 dark:bg-gray-600 dark:text-gray-300'
                                    }`}
                            >
                                {user.state}
                            </span>
                        </div>
                        <div className="flex flex-col items-end">
                            {/* Self-conversation: only show incoming stats */}
                            {incoming && (
                                <div className="flex gap-1 text-xs">
                                    {incoming.unread > 0 && (
                                        <span title={`${incoming.unread} unread notes`} className="text-red-500 font-bold">
                                            ✉️{incoming.unread}
                                        </span>
                                    )}
                                    {incoming.sent > 0 && (
                                        <span title={`${incoming.sent} total notes`} className="text-gray-500">
                                            {incoming.sent} notes
                                        </span>
                                    )}
                                </div>
                            )}
                        </div>
                    </div>
                </li>
            );
        }

        // For regular conversations: show simple incoming stats
        const simpleStats = (
            <div className="flex flex-col items-end gap-1">
                {incoming && (
                    <div className="flex gap-1 text-xs">
                        {incoming.unread > 0 && (
                            <span title={`${incoming.unread} unread messages`} className="text-red-500 font-bold">
                                ✉️{incoming.unread}
                            </span>
                        )}
                        {incoming.sent > 0 && (
                            <span title={`${incoming.sent} received messages`} className="text-gray-500">
                                📥{incoming.sent}
                            </span>
                        )}
                    </div>
                )}
                {outgoing && outgoing.sent > 0 && (
                    <div className="text-xs text-gray-500" title={`${outgoing.sent} sent messages`}>
                        📤{outgoing.sent}
                    </div>
                )}
            </div>
        );

        return (
            <li
                key={user.userId}
                className={`cursor-pointer p-2 rounded transition-colors ${user.userId === selectedUserId
                    ? 'bg-blue-100 dark:bg-blue-900'
                    : 'hover:bg-gray-50 dark:hover:bg-gray-700'
                    }`}
                onClick={() => handleUserClick(user.userId)}
            >
                <div className="flex justify-between items-center">
                    <div>
                        <strong className="font-medium dark:text-gray-200">{user.userName}</strong> - {' '}
                        <span
                            className={`text-xs px-1.5 py-0.5 rounded-full ${user.state === 'authenticated'
                                ? 'bg-green-200 text-green-800 dark:bg-green-800 dark:text-green-200'
                                : 'bg-gray-200 text-gray-600 dark:bg-gray-600 dark:text-gray-300'
                                }`}
                        >
                            {user.state}
                        </span>
                    </div>
                    {simpleStats}
                </div>
            </li>
        );
    });

    return (
        <div className="border-r border-gray-300 p-4 w-64 bg-white dark:bg-gray-800">
            <h3 className="text-lg font-bold mb-4 dark:text-gray-200">
                User List <ConnectionStatusIndicator />
            </h3>

            {!isConnected ? (
                <p className="text-gray-500 dark:text-gray-400">User offline...</p>
            ) : !isAuthenticated ? (
                <p className="text-gray-500 dark:text-gray-400">Connecting to server...</p>
            ) : users.length === 0 ? (
                <p className="text-gray-500 dark:text-gray-400">Loading users...</p>
            ) : (
                <ul className="space-y-2">
                    {sortedUsers.map((user) => (
                        <RenderUser key={user.userId} user={user} />
                    ))}
                </ul>
            )}
        </div>
    );
};

export default UserList;