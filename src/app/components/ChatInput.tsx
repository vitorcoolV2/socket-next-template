import React, { useState, useRef } from 'react';

interface ChatInputProps {
  selectedUser: string | null;
  onSendMessage: (content: string) => void;
}

const ChatInput: React.FC<ChatInputProps> = ({ selectedUser, onSendMessage }) => {
  const [message, setMessage] = useState('');
  const isTypingRef = useRef(false);
  const typingTimeoutRef = useRef<NodeJS.Timeout | null>(null);

  // Handle input changes
  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const newMessage = e.target.value;
    setMessage(newMessage);

    const hasContent = newMessage.trim().length > 0;

    // Start typing indicator if content exists and not already typing
    if (hasContent && !isTypingRef.current) {
      isTypingRef.current = true;
    }

    // Clear existing timeout
    if (typingTimeoutRef.current) {
      clearTimeout(typingTimeoutRef.current);
    }

    // Set timeout to stop typing indicator
    if (hasContent) {
      typingTimeoutRef.current = setTimeout(() => {
        isTypingRef.current = false;
      }, 1000);
    } else {
      // No content, stop typing immediately
      isTypingRef.current = false;
    }
  };

  // Handle sending a message
  const handleSend = () => {
    if (!message.trim() || !selectedUser) return;

    // Call the onSendMessage prop with the message content
    onSendMessage(message.trim());

    // Reset the input field and stop typing indicator
    setMessage('');
    isTypingRef.current = false;

    if (typingTimeoutRef.current) {
      clearTimeout(typingTimeoutRef.current);
    }
  };

  // Handle key press (Enter key sends the message)
  const handleKeyPress = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  // Handle blur event
  const handleBlur = () => {
    // Stop typing when input loses focus
    if (isTypingRef.current) {
      isTypingRef.current = false;
    }
  };

  return (
    <div className="bg-gray-700 p-4 border-t border-gray-600 flex-shrink-0">
      <div className="flex space-x-2">
        <input
          type="text"
          value={message}
          onChange={handleInputChange}
          onKeyUp={handleKeyPress}
          onBlur={handleBlur}
          placeholder={selectedUser ? "Type a message..." : "Select a user to chat"}
          className="flex-grow px-3 py-2 bg-gray-600 text-white rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
          disabled={!selectedUser}
        />
        <button
          onClick={handleSend}
          disabled={!message.trim() || !selectedUser}
          className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          Send
        </button>
      </div>
    </div>
  );
};

export default ChatInput;