import { users } from 'a-socket/db.mjs';

export const getUsersListHandler = async (socket, options) => {
  try {
    const userList = await users.getUsersList(socket.id, options);

    socket.emit('usersList', {
      success: true,
      data: (userList || []).map((u) => ({
        userId: u.userId,
        userName: u.userName,
        state: u.state,
      })),
    });
  } catch (error) {
    console.error('Error in getUsersList:', error);
    socket.emit('usersList', {
      success: false,
      error: error.message || 'Failed to fetch users list',
    });
  }
};