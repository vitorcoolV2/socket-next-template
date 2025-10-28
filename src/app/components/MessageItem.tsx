// components/MessageItem.tsx
import { Message } from '../context/SocketContext';

interface MessageItemProps {
  message: Message;
  index: number;
}

export const MessageItem = ({ message, index }: MessageItemProps) => {
  const isSentByCurrentUser = message.direction === 'outgoing' || message.senderId === 'currentUser';
  const displayName = isSentByCurrentUser ? 'You' : message.senderName;
  const messageClass = `message ${isSentByCurrentUser ? 'sent' : 'received'}`;

  // Generate a unique key for the message
  const getMessageKey = () => {
    if (message.id && !message.id.startsWith('temp-')) {
      return message.id;
    }
    return `${message.id || `msg-${index}`}-${new Date(message.timestamp).getTime()}`;
  };

  return (
    <li
      key={getMessageKey()}
      className={messageClass}
    >
      <div className="message-content">
        <strong>{displayName}:</strong>
        <span>{message.content}</span>
      </div>
      <div className="message-meta">
        <small className="message-time">
          {new Date(message.timestamp).toLocaleTimeString()}
        </small>
        {message.status === 'sending' && (
          <small className="message-status">Sending...</small>
        )}
        {message.status === 'read' && (
          <small className="message-status">Read</small>
        )}
      </div>
    </li>
  );
};