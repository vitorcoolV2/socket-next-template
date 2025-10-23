// components/Chat.tsx
import { useEffect, useState } from 'react';
import { useSocket } from '../context/SocketContext';
import Input from './Input';

interface ChatProps {
  recipientId: string; // The ID of the recipient
}

const Chat = ({ recipientId }: ChatProps) => {
  const { socket, isAuthenticated } = useSocket();
  const [messages, setMessages] = useState<any[]>([]);

  useEffect(() => {
    if (!socket) return;

    // Listen for incoming messages
    const handleIncomingMessage = (message: any) => {
      if (message.recipientId === recipientId || message.sender.userId === recipientId) {
        console.log('handleMessage', message)
        setMessages((prevMessages) => [...prevMessages, message]);
      }
    };

    socket.on('receiveMessage', handleIncomingMessage);

    // Cleanup listeners on unmount
    return () => {
      socket.off('receiveMessage', handleIncomingMessage);
    };
  }, [socket, recipientId]);

  const handleSendMessage = (message: string) => {
    if (!message.trim()) return;

    // Add the sent message to the UI immediately
    setMessages((prevMessages) => [
      ...prevMessages,
      { senderId: 'currentUser', recipientId, content: message },
    ]);

    // Emit the message to the server
    socket?.emit('sendMessage', { recipientId, content: message });
    console.log('user:',)
  };

  return (
    <div>
      <h1>Chat with {recipientId}</h1>
      <p>Status: {isAuthenticated ? 'Connected' : 'Disconnected'}</p>
      <ul>
        {messages.map((msg, index) => (
          <li key={index}>
            <strong>{msg.senderId === 'currentUser' ? 'You' : msg.senderId}:</strong>{' '}
            {msg.content}
          </li>
        ))}
      </ul>

      {/* Input Component */}
      <Input recipientId={recipientId} onSendMessage={handleSendMessage} />
    </div>
  );
};

export default Chat;