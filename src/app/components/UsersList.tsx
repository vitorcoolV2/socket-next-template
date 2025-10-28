import React, { useState, useMemo } from 'react';
import { useSocket, AuthUser, UserRenderData } from '../context/SocketContext';
import { ConnectionStatusIndicator } from './ConnectionStatusIndicator';

interface UserListProps {
    setRecipient: (userId: string) => void;
}

const UserList = ({ setRecipient }: UserListProps) => {
    const { isConnected, isAuthenticated, socketUser, conversationsList } = useSocket();
    const [selectedUserId, setSelectedUserId] = useState<string | null>(null);

    // Priority mapping for user states
    const statePriority: Record<"disconnected" | "connected" | "authenticated" | "offline", number> = useMemo(
        () => ({
            disconnected: 4,
            connected: 3,
            authenticated: 1,
            offline: 2,
        }),
        []
    );

    // Sort users based on their state priority
    // Sort users based on their state priority
    const sortedUsers = useMemo(() => {
        const rawData = conversationsList?.data || [];

        // Deduplicate users by userId
        const uniqueUsers = rawData.reduce((acc, user) => {
            if (!acc.find(u => u.userId === user.userId)) {
                acc.push(user);
            }
            return acc;
        }, [] as any[]);

        return uniqueUsers
            .map((user): UserRenderData => ({
                ...user,
                startedAt: user.startedAt ? new Date(user.startedAt).toISOString() : '',
                lastMessageAt: user.lastMessageAt ? new Date(user.lastMessageAt).toISOString() : '',
                types: user.types || [],
            }))
            .sort((a, b) => {
                const stateA = a.state as keyof typeof statePriority;
                const stateB = b.state as keyof typeof statePriority;

                return (statePriority[stateA] || Infinity) - (statePriority[stateB] || Infinity);
            });
    }, [conversationsList, statePriority]);

    const handleUserClick = (userId: string) => {
        setSelectedUserId(userId);
        setRecipient(userId);
    };

    // Enhanced badge component with better colors
    const StateBadge = ({ state }: { state: string }) => {
        const stateConfig = {
            authenticated: {
                bg: 'bg-gradient-to-r from-green-100 to-emerald-100 dark:from-green-900 dark:to-emerald-900',
                text: 'text-green-800 dark:text-green-200',
                border: 'border border-green-200 dark:border-green-700',
                icon: '🟢'
            },
            connected: {
                bg: 'bg-gradient-to-r from-blue-100 to-cyan-100 dark:from-blue-900 dark:to-cyan-900',
                text: 'text-blue-800 dark:text-blue-200',
                border: 'border border-blue-200 dark:border-blue-700',
                icon: '🔵'
            },
            offline: {
                bg: 'bg-gradient-to-r from-gray-100 to-slate-100 dark:from-gray-700 dark:to-slate-700',
                text: 'text-gray-600 dark:text-gray-300',
                border: 'border border-gray-200 dark:border-gray-600',
                icon: '⚫'
            },
            disconnected: {
                bg: 'bg-gradient-to-r from-red-100 to-pink-100 dark:from-red-900 dark:to-pink-900',
                text: 'text-red-800 dark:text-red-200',
                border: 'border border-red-200 dark:border-red-700',
                icon: '🔴'
            }
        };

        const config = stateConfig[state as keyof typeof stateConfig] || stateConfig.offline;

        return (
            <span
                className={`inline-flex items-center gap-1 px-2 py-1 rounded-full text-xs font-medium ${config.bg} ${config.text} ${config.border} shadow-sm`}
            >
                {config.icon} {state}
            </span>
        );
    };

    // Enhanced message stats component
    const MessageStats = ({ incoming, outgoing }: { incoming: any; outgoing: any }) => {
        if (incoming.unread === 0 && incoming.sent === 0 && outgoing.sent === 0) {
            return null;
        }

        return (
            <div className="flex items-center gap-2">
                {incoming.unread > 0 && (
                    <div className="flex items-center gap-1 bg-red-500 text-white px-2 py-1 rounded-full text-xs font-bold shadow-sm">
                        <span>✉️</span>
                        <span>{incoming.unread}</span>
                    </div>
                )}
                {incoming.sent > 0 && (
                    <div className="flex items-center gap-1 bg-blue-500 text-white px-2 py-1 rounded-full text-xs shadow-sm" title={`${incoming.sent} received messages`}>
                        <span>📥</span>
                        <span>{incoming.sent}</span>
                    </div>
                )}
                {outgoing.sent > 0 && (
                    <div className="flex items-center gap-1 bg-green-500 text-white px-2 py-1 rounded-full text-xs shadow-sm" title={`${outgoing.sent} sent messages`}>
                        <span>📤</span>
                        <span>{outgoing.sent}</span>
                    </div>
                )}
            </div>
        );
    };

    // Memoized rendering of individual user items with enhanced design
    const RenderUser = React.memo(({ user }: { user: UserRenderData }) => {
        const incoming = user.incoming || { sent: 0, pending: 0, delivered: 0, unread: 0, read: 0 };
        const outgoing = user.outgoing || { sent: 0, pending: 0, delivered: 0, unread: 0, read: 0 };
        const isSelfConversation = user.userId === socketUser?.userId;

        // Color schemes for different user states
        const getBackgroundColors = () => {
            if (isSelfConversation) {
                return user.userId === selectedUserId
                    ? 'bg-gradient-to-r from-purple-100 to-indigo-100 dark:from-purple-900 dark:to-indigo-900 border-l-4 border-purple-500'
                    : 'hover:bg-gradient-to-r from-purple-50 to-indigo-50 dark:hover:from-purple-800 dark:hover:to-indigo-800';
            }

            const baseColors = {
                authenticated: user.userId === selectedUserId
                    ? 'bg-gradient-to-r from-green-50 to-emerald-50 dark:from-green-800 dark:to-emerald-800 border-l-4 border-green-500'
                    : 'hover:bg-gradient-to-r from-green-50 to-emerald-50 dark:hover:from-green-800 dark:hover:to-emerald-800',
                connected: user.userId === selectedUserId
                    ? 'bg-gradient-to-r from-blue-50 to-cyan-50 dark:from-blue-800 dark:to-cyan-800 border-l-4 border-blue-500'
                    : 'hover:bg-gradient-to-r from-blue-50 to-cyan-50 dark:hover:from-blue-800 dark:hover:to-cyan-800',
                offline: user.userId === selectedUserId
                    ? 'bg-gradient-to-r from-gray-50 to-slate-50 dark:from-gray-700 dark:to-slate-700 border-l-4 border-gray-500'
                    : 'hover:bg-gradient-to-r from-gray-50 to-slate-50 dark:hover:from-gray-700 dark:hover:to-slate-700',
                disconnected: user.userId === selectedUserId
                    ? 'bg-gradient-to-r from-red-50 to-pink-50 dark:from-red-800 dark:to-pink-800 border-l-4 border-red-500'
                    : 'hover:bg-gradient-to-r from-red-50 to-pink-50 dark:hover:from-red-800 dark:hover:to-pink-800'
            };

            return baseColors[user.state as keyof typeof baseColors] || baseColors.offline;
        };

        return (
            <li
                key={user.userId}
                className={`cursor-pointer p-3 rounded-lg transition-all duration-200 shadow-sm hover:shadow-md ${getBackgroundColors()} group`}
                onClick={() => handleUserClick(user.userId)}
            >
                <div className="flex justify-between items-start">
                    <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 mb-2">
                            <div className="w-2 h-2 rounded-full bg-current opacity-70"></div>
                            <strong className={`font-semibold truncate ${isSelfConversation ? 'text-purple-700 dark:text-purple-300' : 'text-gray-800 dark:text-gray-200'}`}>
                                {user.userName}
                                {isSelfConversation && (
                                    <span className="ml-1 text-xs text-purple-500 dark:text-purple-400">(You)</span>
                                )}
                            </strong>
                        </div>

                        <div className="flex items-center gap-2">
                            <StateBadge state={user.state} />

                            {user.types && user.types.length > 0 && (
                                <div className="flex flex-wrap gap-1">
                                    {user.types.slice(0, 2).map((type, index) => (
                                        <span
                                            key={index}
                                            className="inline-block px-1.5 py-0.5 rounded text-xs bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200 border border-yellow-200 dark:border-yellow-700"
                                        >
                                            {type}
                                        </span>
                                    ))}
                                    {user.types.length > 2 && (
                                        <span className="inline-block px-1.5 py-0.5 rounded text-xs bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-300">
                                            +{user.types.length - 2}
                                        </span>
                                    )}
                                </div>
                            )}
                        </div>
                    </div>

                    <div className="flex-shrink-0 ml-2">
                        <MessageStats incoming={incoming} outgoing={outgoing} />
                    </div>
                </div>

                {/* Last activity time if available */}
                {user.lastMessageAt && (
                    <div className="mt-2 text-xs text-gray-500 dark:text-gray-400">
                        Last: {new Date(user.lastMessageAt).toLocaleDateString()}
                    </div>
                )}
            </li>
        );
    });

    RenderUser.displayName = 'RenderUser';

    return (
        <div className="border-r border-gray-200 dark:border-gray-700 p-4 w-80 bg-gradient-to-b from-white to-gray-50 dark:from-gray-800 dark:to-gray-900 h-full overflow-y-auto">
            <div className="mb-6">
                <h3 className="text-xl font-bold text-gray-800 dark:text-gray-200 mb-2 flex items-center gap-2">
                    👥 User List
                    <ConnectionStatusIndicator />
                </h3>
                <p className="text-sm text-gray-600 dark:text-gray-400">
                    {sortedUsers.length} user{sortedUsers.length !== 1 ? 's' : ''} online
                </p>
            </div>

            {!isConnected ? (
                <div className="text-center py-8">
                    <div className="text-4xl mb-2">🔌</div>
                    <p className="text-gray-500 dark:text-gray-400 font-medium">User offline</p>
                    <p className="text-sm text-gray-400 dark:text-gray-500 mt-1">Waiting for connection...</p>
                </div>
            ) : !isAuthenticated ? (
                <div className="text-center py-8">
                    <div className="text-4xl mb-2">⏳</div>
                    <p className="text-gray-500 dark:text-gray-400 font-medium">Connecting to server</p>
                    <p className="text-sm text-gray-400 dark:text-gray-500 mt-1">Authenticating...</p>
                </div>
            ) : !conversationsList?.data || conversationsList.data.length === 0 ? (
                <div className="text-center py-8">
                    <div className="text-4xl mb-2">👀</div>
                    <p className="text-gray-500 dark:text-gray-400 font-medium">No users found</p>
                    <p className="text-sm text-gray-400 dark:text-gray-500 mt-1">Users will appear here when available</p>
                </div>
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