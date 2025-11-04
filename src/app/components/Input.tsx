import { useState, useRef, useEffect } from 'react';
import { useSocket } from 'a-app/context/SocketContext';

interface InputProps {
    recipientId: string; // The ID of the recipient
    onSendMessage: (message: string) => void; // Callback to notify parent when a message is sent
    disableSystem?: boolean; // Flag to disable the entire system
    disableEvents?: boolean; // Flag to disable typing events only
}

const Input = ({ recipientId, onSendMessage, disableSystem = false, disableEvents = false }: InputProps) => {
    const { socket } = useSocket();
    const [input, setInput] = useState('');
    const [isTyping, setIsTyping] = useState(false); // Track user's typing state
    const [recipientTyping, setRecipientTyping] = useState(false); // Track recipient's typing state
    const timeoutRef = useRef<NodeJS.Timeout | null>(null);

    // Handle user's typing indicator logic
    const handleTypingIndicator = () => {
        if (disableSystem || disableEvents) return;

        if (timeoutRef.current) {
            clearTimeout(timeoutRef.current);
        }

        // Emit "typing" event immediately
        socket?.emit('typing', { recipientId });

        // Set typing state to true
        setIsTyping(true);

        // Set a timeout to emit "stopTyping" after 1 second of inactivity
        timeoutRef.current = setTimeout(() => {
            socket?.emit('stopTyping', { recipientId });
            setIsTyping(false); // Reset typing state
        }, 1000);
    };

    const handleSendMessage = () => {
        if (!input.trim() || disableSystem) return;

        // Notify parent component about the new message
        onSendMessage(input);

        // Clear the input field
        setInput('');

        // Emit stop-typing event after sending the message
        if (!disableEvents) {
            socket?.emit('stopTyping', { recipientId });
        }
        setIsTyping(false); // Reset typing state
    };

    // Listen for recipient's typing and stop-typing events
    useEffect(() => {
        if (!socket || disableSystem) return;

        const handleRecipientTyping = () => {
            setRecipientTyping(true);
        };

        const handleRecipientStopTyping = () => {
            setRecipientTyping(false);
        };

        socket.on('typing', handleRecipientTyping);
        socket.on('stopTyping', handleRecipientStopTyping);

        // Cleanup listeners on unmount
        return () => {
            socket.off('typing', handleRecipientTyping);
            socket.off('stopTyping', handleRecipientStopTyping);
        };
    }, [socket, disableSystem]);

    return (
        <div
            className="relative flex items-center space-x-2 p-2 border-t border-gray-300 dark:border-gray-700"
        >
            {/* Input Field */}
            <input
                type="text"
                value={input}
                onKeyDown={(e) => {
                    if (e.key === 'Enter') {
                        handleSendMessage(); // Send message if "Enter" is pressed
                    }
                }}
                onChange={(e) => {
                    setInput(e.target.value);
                    !disableSystem && handleTypingIndicator(); // Trigger typing indicator on input change
                }}
                placeholder="Type a message..."
                disabled={disableSystem} // Disable input field if the system is disabled
                className="flex-1 p-2 rounded border border-gray-300 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
            />

            {/* Send Button */}
            <button
                onClick={handleSendMessage}
                disabled={!socket || disableSystem} // Disable button if the system is disabled
                className="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600 transition-colors disabled:bg-gray-400 relative"
            >
                Send

                {/* Typing Indicator Dot */}
                {!disableSystem && isTyping && (
                    <div
                        className="absolute top-1 left-5 w-1 h-1 bg-pink-500 rounded-full"
                        style={{ width: '5px', height: '5px' }}
                    ></div>
                )}
                {/* Typing Indicator Dot */}
                {!disableSystem && recipientTyping && (
                    <div
                        className="absolute top-1 left-6 w-1 h-1 bg-blue-800 rounded-full"
                        style={{ width: '5px', height: '5px' }}
                    ></div>
                )}
            </button>
        </div>
    );
};

export default Input;