import React, { useState, useMemo, useRef, useCallback, useEffect } from 'react';
import { useSocketContext } from './SocketContext';
import { PrivateMessage, MessageCache } from '../utils/types';
import { getCurrentMessages } from '../utils/chatUtils';
import ChatInput from './ChatInput';

interface PrivateChatProps {
    me: {
        userId: string;
        userName: string;
    } | null;
    selectedUser: string | null;
}

const PrivateChat: React.FC<PrivateChatProps> = ({ me, selectedUser }) => {
    const [loadingHistory, setLoadingHistory] = useState(false);
    const [errorMessage, setErrorMessage] = useState('');
    const [lastMessageCount, setLastMessageCount] = useState(0);

    const messagesEndRef = useRef<HTMLDivElement>(null);
    const messageCacheRef = useRef<MessageCache>({});

    const {
        getMessageHistory,
        markMessagesAsRead,
        privateConversations,
        sendPrivateMessage,
        addPrivateMessage,
        socket,
    } = useSocketContext();

    // Initialize cache for a user if it doesn't exist
    const initializeCache = useCallback((userId: string) => {
        if (!messageCacheRef.current[userId]) {
            messageCacheRef.current[userId] = {
                messages: [],
                offset: 0,
                hasMore: true,
                lastLoaded: 0,
            };
        }
    }, []);

    // Function to load user messages
    const loadUserMessages = useCallback(
        async (userId: string, isInitialLoad: boolean) => {
            try {
                console.log('🔍 Fetching message history for user:', userId);

                if (!userId || userId === 'undefined') {
                    console.error('❌ Invalid userId provided to loadUserMessages:', userId);
                    return;
                }

                const cache = messageCacheRef.current[userId];
                if (!cache.hasMore && !isInitialLoad) {
                    console.log('⏹️ No more messages to fetch for user:', userId);
                    return;
                }

                setLoadingHistory(true);

                const options = {
                    userId,
                    limit: 20,
                    offset: cache.offset,
                    type: 'private',
                };
                console.log('⚙️ Request options:', options);

                const response = await getMessageHistory(options);
                if (!response) {
                    throw new Error('Invalid response from server');
                }

                const { messages } = response;
                const total = response.total || 0;
                const hasMore = messages.length === 20;

                console.log('📥 Server response:', {
                    userId,
                    totalMessagesFetched: messages.length,
                    totalAvailable: total,
                    hasMore,
                });

                // Deduplicate messages
                const seenMessageIds = new Set(cache.messages.map(msg => msg.messageId));
                const uniqueMessages = messages.filter((msg): msg is PrivateMessage => {
                    const isDuplicate = seenMessageIds.has(msg.messageId);
                    if (isDuplicate) {
                        console.warn('⚠️ Duplicate message detected:', msg.messageId);
                    }
                    return !isDuplicate;
                });

                console.log('🧹 Deduplicated messages:', uniqueMessages);

                // Add unique messages using addPrivateMessage
                uniqueMessages.forEach((message: PrivateMessage) => {
                    console.log('📤 Adding message via addPrivateMessage:', {
                        userId,
                        messageId: message.messageId,
                        content: message.content,
                    });
                    addPrivateMessage(userId, message, 'loadUserMessages');
                });

                // Update cache with loaded messages
                messageCacheRef.current[userId] = {
                    ...cache,
                    messages: [...cache.messages, ...uniqueMessages],
                    offset: cache.offset + uniqueMessages.length,
                    hasMore,
                    lastLoaded: Date.now(),
                };

                console.log('📦 Updated cache for user:', userId, messageCacheRef.current[userId]);

                setLoadingHistory(false);
            } catch (error) {
                console.error(`❌ Failed to load messages for user ${userId}:`, error);
                setLoadingHistory(false);
                setErrorMessage('Failed to load messages');
                throw error;
            }
        },
        [getMessageHistory, addPrivateMessage]
    );

    // Get current messages with deduplication
    const currentMessages = useMemo(() => {
        const messages = getCurrentMessages(selectedUser, privateConversations, messageCacheRef);

        const seenMessageIds = new Set<string>();
        const uniqueMessages: PrivateMessage[] = [];

        for (const message of messages) {
            if (!seenMessageIds.has(message.messageId)) {
                seenMessageIds.add(message.messageId);
                uniqueMessages.push(message);
            } else {
                console.warn('Duplicate message detected during deduplication:', message.messageId);
            }
        }

        console.log('Final unique messages:', uniqueMessages);
        return uniqueMessages;
    }, [selectedUser, privateConversations]);

    // Handle user selection and loading messages
    // In PrivateChat.tsx, update the useEffect that calls markMessagesAsRead
    useEffect(() => {
        if (!selectedUser || !socket || socket.disconnected) return;

        console.log(`Selected user changed: ${selectedUser}`);
        initializeCache(selectedUser);

        const cache = messageCacheRef.current[selectedUser];
        if (cache.messages.length === 0) {
            console.log(`Loading initial messages for user: ${selectedUser}`);
            loadUserMessages(selectedUser, true).catch(error => {
                console.error('Failed to load user messages:', error);
            });
        }

        setErrorMessage('');
        setLastMessageCount(currentMessages.length);

        // Only mark messages as read if socket is connected
        const messages = messageCacheRef.current[selectedUser]?.messages || [];
        const unreadMessageIds = messages
            .filter((msg): msg is PrivateMessage =>
                'readAt' in msg && !msg.readAt && 'recipientId' in msg && msg.recipientId === me?.userId
            )
            .map((msg) => msg.messageId);

        if (unreadMessageIds.length > 0 && socket.connected) {
            markMessagesAsRead(unreadMessageIds).catch(error => {
                console.error('Failed to mark messages as read:', error);
            });
        }
    }, [selectedUser, initializeCache, loadUserMessages, currentMessages.length, me?.userId, markMessagesAsRead, socket]);
    // Smart auto-scroll for new messages
    useEffect(() => {
        if (!selectedUser) return;

        const currentMessageCount = currentMessages.length;
        const newMessagesAdded = currentMessageCount > lastMessageCount;

        if (newMessagesAdded) {
            messagesEndRef.current?.scrollIntoView({
                behavior: 'smooth',
            });
        }

        setLastMessageCount(currentMessageCount);
    }, [currentMessages, selectedUser, lastMessageCount]);

    // Handle sending message via ChatInput
    const handleSendMessage = useCallback(async (content: string) => {
        if (!selectedUser) return;

        try {
            await sendPrivateMessage(selectedUser, content);
        } catch (error) {
            console.error('Failed to send message:', error);
            setErrorMessage('Failed to send message');
        }
    }, [selectedUser, sendPrivateMessage]);

    useEffect(() => {
        if (!selectedUser) return;

        initializeCache(selectedUser);

        // Clear cache for other users
        Object.keys(messageCacheRef.current).forEach(userId => {
            if (userId !== selectedUser) {
                messageCacheRef.current[userId] = {
                    messages: [],
                    offset: 0,
                    hasMore: true,
                    lastLoaded: 0,
                };
            }
        });

        loadUserMessages(selectedUser, true).catch(error => {
            console.error('Failed to load user messages:', error);
        });
    }, [selectedUser, loadUserMessages, initializeCache]);

    // No user selected state
    if (!selectedUser) {
        return (
            <div className="flex flex-col flex-grow items-center justify-center bg-gray-800 p-4">
                <div className="text-center text-gray-400">
                    <h3 className="text-xl font-semibold mb-2">Select a user to start chatting</h3>
                    <p>Choose someone from the online users list to begin a conversation</p>
                </div>
            </div>
        );
    }

    return (
        <div className="flex flex-col flex-grow bg-gray-800 overflow-hidden">
            {/* Chat Header */}
            <div className="bg-gray-700 px-4 py-3 border-b border-gray-600">
                <h2 className="text-lg font-semibold text-white">
                    Chat with {selectedUser}
                </h2>
            </div>

            {/* Error Message */}
            {errorMessage && (
                <div className="bg-red-500 text-white px-4 py-2 text-sm">
                    {errorMessage}
                </div>
            )}

            {/* Messages Container */}
            <div className="flex-grow p-4 space-y-3">
                {/* Loading indicator for history */}
                {loadingHistory && (
                    <div className="flex justify-center py-2">
                        <div className="text-gray-400 text-sm">Loading more messages...</div>
                    </div>
                )}

                {/* Messages */}
                {currentMessages.map((message, index) => (
                    <div
                        key={`${message.messageId}-${message.timestamp}-${index}`}
                        className={`flex ${message.sender.userId === me?.userId ? 'justify-end' : 'justify-start'}`}
                    >
                        <div
                            className={`max-w-xs lg:max-w-md px-4 py-2 rounded-lg ${message.sender.userId === me?.userId
                                ? 'bg-blue-600 text-white'
                                : 'bg-gray-600 text-white'
                                }`}
                        >
                            {message.sender.userId !== me?.userId && (
                                <div className="text-xs text-gray-300 mb-1">
                                    {message.sender.userName}
                                </div>
                            )}
                            <div className="break-words">{message.content}</div>
                            <div
                                className={`text-xs mt-1 ${message.sender.userId === me?.userId
                                    ? 'text-blue-200'
                                    : 'text-gray-400'
                                    }`}
                            >
                                {new Date(message.timestamp).toLocaleTimeString()}
                            </div>
                        </div>
                    </div>
                ))}
                <div ref={messagesEndRef} />
            </div>

            {/* Chat Input Component */}
            <ChatInput
                selectedUser={selectedUser}
                onSendMessage={handleSendMessage}
            />
        </div>
    );
};

export default PrivateChat;