import { validateEventData, typingSchema } from './schemas.mjs';
import { responseTemplates } from './responseTemplates.mjs'; // Assuming you have a utility for response templates

/**
 * Handle the 'typingIndicator' event
 */
const handleTypingIndicator = (io, userManager) => {
    return (socket, data) => {
        try {
            // Validate the incoming data against the typingSchema
            const validatedData = validateEventData(data, typingSchema);
            const { isTyping, recipientId } = validatedData;

            // Get the sender's user data by their socketId
            const sender = userManager.getUserBySocketId(socket.id);
            if (!sender) {
                throw new Error('Sender not found');
            }

            // Prepare the typing event payload
            const typingEvent = {
                sender: sender.userId,
                senderName: sender.userName,
                isTyping,
                timestamp: new Date().toISOString(),
            };

            // Get the recipient's socket IDs
            const recipientSockets = userManager.getSocketIdsByUserId(recipientId);
            if (recipientSockets.length > 0) {
                // Emit the typingIndicator event to all recipient sockets
                recipientSockets.forEach((socketId) => {
                    io.to(socketId).emit('typingIndicator', responseTemplates.success('typingIndicator', typingEvent));
                });
            }

            console.log(`Typing indicator sent: ${typingEvent.isTyping ? 'is typing' : 'stopped typing'}`);
            return typingEvent;
        } catch (error) {
            console.error(`Error handling typingIndicator: ${error.message}`);
            socket.emit('typingIndicator', responseTemplates.error('typingIndicator', error.message));
            throw error;
        }
    };
};

export default handleTypingIndicator;