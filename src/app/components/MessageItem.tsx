import React from 'react';
import { format } from 'date-fns';
import { Message } from 'a-app/context/SocketContext';

interface MessageItemProps {
  message: Message;
  recipientName: string;
}

export const MessageItem = React.memo(({ message }: MessageItemProps) => {
  // Determine if the message is sent by the current user
  const isSentByCurrentUser = message.direction === 'outgoing' || message.senderId === 'currentUser';
  const displayName = isSentByCurrentUser ? 'You' : message.senderName || 'Unknown User';
  const content = message.content || '[No content]';
  const createdAt = message.createdAt
    ? format(new Date(message.createdAt), 'hh:mm a') // Format createdAt with date-fns
    : 'Unknown time';

  // Tailwind classes for alignment and styling
  const containerClass = isSentByCurrentUser
    ? 'flex justify-end'
    : 'flex justify-start';
  const messageClass = isSentByCurrentUser
    ? 'bg-green-200 text-green-800 rounded-lg p-3 max-w-[70%] shadow-md'
    : 'bg-gray-200 text-gray-900 rounded-lg p-3 max-w-[70%] shadow-md';

  return (
    <div className={`${containerClass} mb-4`}>
      <div className={messageClass}>
        {/* Message Content */}
        <div className="mb-1">
          <strong className="text-sm font-medium">{displayName}:</strong>
          <span className="block mt-1 text-base">{content}</span>
        </div>

        {/* Message Meta (createdAt and Status) */}
        <div className="flex items-center text-xs text-gray-800">
          <small>{createdAt}</small>
          {message.status && (
            <small className={`ml-2 ${getStatusColor(message.status)}`}>
              {getStatusText(message.status)}
            </small>
          )}
        </div>
      </div>
    </div>
  );
});

// Helper function to determine status text
const getStatusText = (status: string): string => {
  switch (status) {
    case 'sent':
      return 'Sending...';
    case 'read':
      return 'Read';
    case 'pending':
      return 'Pending';
    case 'delivered':
      return 'Delivered';
    case 'error':
      return 'Error';
    default:
      return '';
  }
};

// Helper function to determine status color
const getStatusColor = (status: string): string => {
  switch (status) {
    case 'sent':
      return 'text-blue-300';
    case 'pending':
      return 'text-blue-500';
    case 'read':
      return 'text-green-800';
    case 'delivered':
      return 'text-green-800';
    case 'error':
      return 'text-red-600';
    default:
      return '';
  }
};