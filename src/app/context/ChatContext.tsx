// context/ChatContext.ts
import { createContext, useContext, useState, useEffect } from 'react';



// Define the shape of the context value
interface ChatContextType {
  messages: Message[];
  addMessage: (message: Message) => void;
  clearMessages: () => void;
  typingUsers: string[];
  addTypingUser: (userId: string) => void;
  removeTypingUser: (userId: string) => void;
}

// Default context value
const ChatContext = createContext<ChatContextType>({
  messages: [],
  addMessage: () => { },
  clearMessages: () => { },
  typingUsers: [],
  addTypingUser: () => { },
  removeTypingUser: () => { },
});

// Custom hook to use the chat context
export const useChat = () => {
  return useContext(ChatContext);
};

// Provider component to wrap the app with chat state
export const ChatProvider = ({ children }: { children: React.ReactNode }) => {
  const [messages, setMessages] = useState<Message[]>([]);
  const [typingUsers, setTypingUsers] = useState<string[]>([]);

  // Add a new message to the chat
  const addMessage = (message: Message) => {
    setMessages((prevMessages) => [...prevMessages, message]);
  };

  // Clear all messages
  const clearMessages = () => {
    setMessages([]);
  };

  // Add a user to the typing users list
  const addTypingUser = (userId: string) => {
    setTypingUsers((prevTypingUsers) =>
      prevTypingUsers.includes(userId) ? prevTypingUsers : [...prevTypingUsers, userId]
    );
  };

  // Remove a user from the typing users list
  const removeTypingUser = (userId: string) => {
    setTypingUsers((prevTypingUsers) =>
      prevTypingUsers.filter((id) => id !== userId)
    );
  };

  return (
    <ChatContext.Provider
      value={{
        messages,
        addMessage,
        clearMessages,
        typingUsers,
        addTypingUser,
        removeTypingUser,
      }}
    >
      {children}
    </ChatContext.Provider>
  );
};

// Define the structure of a message
interface Message {
  messageId: string;
  senderId: string;
  recipientId: string;
  content: string;
  timestamp: string;
  status: 'sent' | 'delivered' | 'read';
}