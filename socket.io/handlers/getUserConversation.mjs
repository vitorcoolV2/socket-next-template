import { users } from 'a-socket/db.mjs';
import { mapMessage } from 'a-socket/utils.mjs';

export const getUserConversationHandler = async (socket, options) => {
  try {
    const conversationData = await users.getUserConversation(socket.id, options);

    socket.emit('userConversation', {
      success: true,
      data: {
        messages: conversationData.messages.map(mapMessage),
        total: conversationData.total,
        hasMore: conversationData.hasMore,
        context: conversationData.context || null,
      },
      options: options, // Echo back the options for client reference
    });

    console.log(
      `Sent ${conversationData.messages.length} messages to user ${socket.id} for conversation with ${options.otherPartyId}`
    );
  } catch (error) {
    console.error('Error in getUserConversation:', error);
    socket.emit('userConversation', {
      success: false,
      error: error.message || 'Failed to fetch conversation',
      options: options,
    });
  }
};