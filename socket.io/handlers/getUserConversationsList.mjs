import { users } from 'a-socket/db.mjs';

export const getUserConversationsListHandler = async (socket, options) => {
  try {
    const conversationsList = await users.getUserConversationsList(socket.id, options);

    socket.emit('userConversationsList', {
      success: true,
      data: (conversationsList || []).map((u) => ({
        userId: u.userId,
        userName: u.userName,
        otherPartyId: u.otherPartyId,
        otherPartyName: u.otherPartyName,
        startedAt: u.startedAt,
        lastMessageAt: u.lastMessageAt,
        incoming: u.incoming,
        outgoing: u.outgoing,
      })),
    });
  } catch (error) {
    console.error('Error in getUserConversationsList:', error);
    socket.emit('getUserConversationsList', {
      success: false,
      error: error.message || 'Failed to fetch conversations list',
    });
  }
};