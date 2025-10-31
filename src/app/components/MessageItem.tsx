import React from 'react';
import { format } from 'date-fns';
import { Message } from '../context/SocketContext';




interface MessageItemProps {
  message: Message;
  index: number;
}

export const MessageItem = React.memo(({ message, index }: MessageItemProps) => {
  // Determine if the message is sent by the current user
  const isSentByCurrentUser = message.direction === 'outgoing' || message.senderId === 'currentUser';
  const displayName = isSentByCurrentUser ? 'You' : message.senderName || 'Unknown User';
  const content = message.content || '[No content]';
  const createdAt = message.createdAt
    ? format(new Date(message.createdAt), 'hh:mm a') // Format createdAt with date-fns
    : 'Unknown time';

  // Tailwind classes for alignment and styling
  const containerClass = isSentByCurrentUser
    ? 'flex justify-end' // Align outgoing messages to the right
    : 'flex justify-start'; // Align incoming messages to the left

  const messageClass = isSentByCurrentUser
    ? 'bg-green-200 text-green-800 text-right rounded-lg p-3 max-w-[70%] shadow-md' // Outgoing: dark green text on light green
    : 'bg-gray-200 text-gray-900 text-left rounded-lg p-3 max-w-[70%] shadow-md'; // Incoming: dark gray text on light gray

  return (
    <div className={`${containerClass} mb-4`}>
      <div className={messageClass}>
        {/* Message Content */}
        <div className="message-content">
          <strong className="text-sm font-medium">{displayName}:</strong>
          <span className="block mt-1 text-base">{content}</span>
        </div>

        {/* Message Meta (createdAt and Status) */}
        <div className="message-meta flex items-center text-xs mt-1">
          <small className="text-gray-800">{createdAt}</small>
          {message.status === 'sending' && (
            <small className="text-blue-500 ml-2">Sending...</small>
          )}
          {message.status === 'read' && (
            <small className="text-green-800 ml-2">Read</small>
          )}
        </div>
      </div>
    </div>
  );
});