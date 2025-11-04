
import { users as __users } from 'a-socket/db.mjs';    // Import the user manager

export const markMessagesAsReadHandler = async (socket, options) => {
  const __io = __users.getIO();
  const resp = await __users.markMessagesAsRead(socket.id, options);

  const emitSockets = await __users.getUserSockets(resp.recipientId);

  // If no sockets to emit to, mark it with pending and return
  if (!emitSockets || emitSockets.length === 0) {
    console.log(`No active sockets for recipient ${recipientId}, marking as pending`);
    // the will bewill notify pending bellow after trying to deliver to recipient and fail
    socket.emit('update', { ...msg, direction: 'outgoing' });
    return msg;
  } else {
    __io.to(socket.id).emit('update_message_status', { ...msg, direction: 'outgoing' });
    // notify without ack, recipient on pending message. will try bellow to formal deliver and acknolege
    emitSockets.forEach(sock => {
      __io.to(sock.socketId).emit('update_message_status', { ...msg, direction: 'incoming' })
    });
  }
};