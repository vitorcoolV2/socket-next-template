// components/Chat.tsx
import { useRef, useEffect, useState, useCallback } from 'react';
import {
  useSocket,
  type Message,
  type FetchGetUserConversationOptions,
  UserConversationMessageEvent,
  GetUserConversationResponse
} from '../context/SocketContext';
import Input from './Input';
import { MessageItem } from './MessageItem';

interface ChatProps {
  recipientId: string;
}

const Chat = ({ recipientId }: ChatProps) => {
  const { socket, isAuthenticated, getUserConversation, socketUser, conversationsList } = useSocket();
  const [messages, setMessages] = useState<Message[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState(false);
  const [offset, setOffset] = useState(0);
  const [recipientName, setRecipientName] = useState<string | null>('');
  const limit = 500;
  const messagesContainerRef = useRef<HTMLDivElement | null>(null);

  // Scroll to the bottom of the messages container
  // Scroll to the bottom of the messages container
  const scrollToBottom = () => {
    if (messagesContainerRef.current) {
      messagesContainerRef.current.scrollTop = messagesContainerRef.current.scrollHeight;
    }
  };
  /*
  const scrollToBottom2 = () => {
    if (messagesContainerRef.current) {
      const { scrollTop, scrollHeight, clientHeight } = messagesContainerRef.current;
      const isNearBottom = scrollHeight - scrollTop - clientHeight < 50; // 50px threshold
      if (isNearBottom) {
        messagesContainerRef.current.scrollTop = scrollHeight;
      }
    }
  };*/

  useEffect(() => {
    // Scroll to the bottom when new messages are added
    scrollToBottom();
  }, [messages]);

  // Load conversation messages
  const loadConversation = useCallback(async (loadMore = false) => {
    if (!isAuthenticated || !socketUser || !socketUser.userId || !conversationsList) return;

    const currentOffset = loadMore ? offset : 0;

    setLoading(true);
    setError(null);

    const userId = socketUser.userId;
    const recipient = conversationsList.find(u => u.otherPartyId === recipientId);
    setRecipientName(recipient?.otherPartyName || null);


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

      const data: GetUserConversationResponse = await getUserConversation(options);

      if (loadMore) {
        // Append messages when loading more
        setMessages(prev => [...prev, ...data.messages]);
      } else {
        // Replace messages for initial load
        setMessages(data.messages);
      }

      setHasMore(data.hasMore);
      setOffset(currentOffset + data.messages.length);

    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load messages');
      console.error('Error loading conversation:', err);
    } finally {
      setLoading(false);
    }
  }, [isAuthenticated, getUserConversation, conversationsList, recipientId, offset, limit, socketUser]);

  // Load initial messages
  useEffect(() => {
    setOffset(0);
    loadConversation(false);
  }, [recipientId, isAuthenticated, loadConversation]);


  const handleIncomingMessage = useCallback((message: Message) => {
    if (message.senderId === recipientId || message.recipientId === recipientId) {
      setMessages(prevMessages => {
        const exists = prevMessages.some(msg => msg.id === message.id);
        if (!exists) {
          return [...prevMessages, message];
        }
        return prevMessages;
      });
    }
  }, [recipientId]);

  // Listen for real-time messages
  useEffect(() => {
    if (!socket) return;
    socket.on('update_message_status', handleIncomingMessage);
    return () => {
      socket.off('update_message_status', handleIncomingMessage);
    };
  }, [socket, handleIncomingMessage]);

  const handleSendMessage = async (content: string) => {
    if (!content.trim() || !socket) return;

    try {
      // Emit the message to the server and wait for acknowledgement
      socket.emit('sendMessage', { recipientId, content },
        (ack: UserConversationMessageEvent) => {
          if (ack && ack.success &&
            ack.event === 'sendMessage' &&
            ack.success === true &&
            ack?.result
          ) {
            console.log('Message sent successfully with ack:', ack);
            /*       setMessages(prevMessages => {
                     // Check if the message already exists
                     const exists = prevMessages.some(msg => msg.id === ack.result.id);
                     if (!exists) {
                       //        return [...prevMessages, ack.result];
                     }
                     return prevMessages;
                   });*/
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
      return `${message.id}-${message.direction}`;
    }
    // For temp messages or messages without ID, create a composite key
    return `${message.id || `msg-${index}`}-${message.createdAt}`;
  };

  if (loading && messages.length === 0) {
    return (
      <div>
        <h1>Chat with {recipientName}</h1>
        <p>Loading messages...</p>
      </div>
    );
  }

  return (
    <div className="chat-container">
      <div className="chat-header">
        <h1>Chat with {recipientName}</h1>
        {/* <p>State: {isAuthenticated ? 'Connected' : 'Disconnected'}</p> */}
        {error && (
          <div className="error-message bg-red-100 border border-red-400 text-red-700 px-4 py-2 rounded relative">
            <span>Error: {error}</span>
            <button
              onClick={() => setError(null)}
              className="absolute top-0 right-0 px-2 py-1 text-sm font-semibold text-red-700 hover:text-red-900"
            >
              Dismiss
            </button>
          </div>
        )}
      </div>

      {/* Messages Area */}
      <div
        className="messages-area overflow-y-auto h-[400px]"
        ref={messagesContainerRef}
      >
        {hasMore && (
          <div className="load-more">
            <button
              onClick={handleLoadMore}
              disabled={loading || !hasMore}
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
                recipientName={recipientName || ''}
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