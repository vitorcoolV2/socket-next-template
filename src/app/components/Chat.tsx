// components/Chat.tsx
import { useEffect, useState, useCallback } from 'react';
import { useSocket, type Message, type FetchGetUserConversationOptions } from '../context/SocketContext';
import Input from './Input';
import { MessageItem } from './MessageItem';

interface ChatProps {
  recipientId: string;
}

const Chat = ({ recipientId }: ChatProps) => {
  const { socket, isAuthenticated, getUserConversation, socketUser } = useSocket();
  const [messages, setMessages] = useState<Message[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState(false);
  const [offset, setOffset] = useState(0);
  const limit = 50;

  // Load conversation messages
  const loadConversation = useCallback(async (loadMore = false) => {
    if (!isAuthenticated || !socketUser || !socketUser.userId) return;

    const currentOffset = loadMore ? offset : 0;

    setLoading(true);
    setError(null);

    const userId = socketUser.userId || 'undefined';

    try {
      const options: FetchGetUserConversationOptions = {
        type: 'private',
        userId,
        otherPartyId: recipientId,
        limit: limit,
        offset: currentOffset,
        since: null,
        until: null,
        //unreadOnly: false
      };

      const response = await getUserConversation(options);

      if (loadMore) {
        // Append messages when loading more
        setMessages(prev => [...prev, ...response.messages]);
      } else {
        // Replace messages for initial load
        setMessages(response.messages);
      }

      setHasMore(response.hasMore);
      setOffset(currentOffset + response.messages.length);

    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load messages');
      console.error('Error loading conversation:', err);
    } finally {
      setLoading(false);
    }
  }, [isAuthenticated, getUserConversation, recipientId, offset, limit]);

  // Load initial messages
  useEffect(() => {
    setOffset(0);
    loadConversation(false);
  }, [recipientId, isAuthenticated]);

  // Listen for real-time messages
  useEffect(() => {
    if (!socket) return;

    const handleIncomingMessage = (message: Message) => {
      // Check if message belongs to this conversation
      if (message.senderId === recipientId || message.recipientId === recipientId) {
        console.log('Received real-time message:', message);
        setMessages(prevMessages => {
          // Avoid duplicates
          if (prevMessages.some(msg => msg.id === message.id)) {
            return prevMessages;
          }
          return [...prevMessages, message];
        });

        // Reload conversation to ensure we have the latest state
        // This handles message ordering and updates lastMessageAt
        loadConversation(false);
      }
    };

    socket.on('receivedMessage', handleIncomingMessage);

    // Cleanup listeners on unmount
    return () => {
      socket.off('receivedMessage', handleIncomingMessage);
    };
  }, [socket, recipientId, loadConversation]);

  const handleSendMessage = async (content: string) => {
    if (!content.trim() || !socket) return;

    try {
      // Emit the message to the server and wait for acknowledgement
      socket.emit('sendMessage', {
        recipientId,
        content: content
      }, (ack: any) => {
        if (ack && ack.success) {
          console.log('Message sent successfully with ack:', ack);
          // The real message will come via receivedMessage or we can reload
          // not optimistic message immediately
          setMessages(prevMessages => [...prevMessages, ack]);
          loadConversation(false);
        } else {
          // Handle send failure
          setError('Failed to send message');
        }
      });

    } catch (err) {
      console.error('Error sending message:', err);
      setError('Failed to send message');
    }
  };

  const handleLoadMore = () => {
    if (hasMore && !loading) {
      loadConversation(true);
    }
  };

  // Generate a unique key for each message
  const getMessageKey = (message: Message, index: number) => {
    // Use message.id if available and not a temp ID, otherwise fall back to index
    if (message.id && !message.id.startsWith('temp-')) {
      return message.id;
    }
    // For temp messages or messages without ID, create a composite key
    return `${message.id || `msg-${index}`}-${new Date(message.timestamp).getTime()}`;
  };

  if (loading && messages.length === 0) {
    return (
      <div>
        <h1>Chat with {recipientId}</h1>
        <p>Loading messages...</p>
      </div>
    );
  }

  return (
    <div className="chat-container">
      <div className="chat-header">
        <h1>Chat with {recipientId}</h1>
        <p>Status: {isAuthenticated ? 'Connected' : 'Disconnected'}</p>
        {error && (
          <div className="error-message" style={{ color: 'red' }}>
            Error: {error}
            <button onClick={() => setError(null)}>Dismiss</button>
          </div>
        )}
      </div>

      {/* Messages Area */}
      <div className="messages-area">
        {hasMore && (
          <div className="load-more">
            <button
              onClick={handleLoadMore}
              disabled={loading}
            >
              {loading ? 'Loading...' : 'Load older messages'}
            </button>
          </div>
        )}

        {messages.length === 0 ? (
          <div className="no-messages">
            <p>No messages yet. Start the conversation!</p>
          </div>
        ) : (
          <ul className="messages-list">
            {messages.map((message, index) => (
              <MessageItem
                key={getMessageKey(message, index)}
                message={message}
                index={index}
              />
            ))}
          </ul>
        )}

        {loading && messages.length > 0 && (
          <div className="loading-indicator">
            Loading more messages...
          </div>
        )}
      </div>

      {/* Input Component */}
      <Input
        recipientId={recipientId}
        onSendMessage={handleSendMessage}
        disableSystem={!isAuthenticated}
        disableEvents={loading}
      />
    </div>
  );
};

export default Chat;