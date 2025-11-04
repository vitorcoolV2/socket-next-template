
import {
  DEFAULT_REQUEST_TIMEOUT,
  getSafeTimeouts,
} from 'a-socket/config.mjs';

import { mapMessage } from 'a-socket/utils.mjs';
import { users as __users } from 'a-socket/db.mjs';

import { trackMessageDelivery } from './messageDelivery.mjs';

export const sendMessageHandler = async (socket, { recipientId, content, clientTimeout }) => {
  try {
    const __io = __users.getIO();
    const effectiveTimeout = clientTimeout || DEFAULT_REQUEST_TIMEOUT;
    const { handlerTimeout, deliveryTimeout } = getSafeTimeouts(effectiveTimeout);

    // Input validation
    if (!recipientId || !content) {
      throw new Error('Recipient ID and content are required.');
    }

    // Persist message
    const sentMessage = await __users.sendMessage(socket.id, recipientId, content);
    if (!sentMessage) throw new Error('Failed to persist the message.');
    const msg = mapMessage(sentMessage);


    const recipientSockets = await __users.getUserSockets(recipientId);
    // Immediate notification to sender
    const notifyStatus = (msg, status, both = false) => {
      msg.status = status;
      __io.to(socket.id).emit('update_message_status', {
        ...msg,
        direction: 'outgoing',
        status
      });
      if (both) recipientSockets?.forEach(sock => {
        __io.to(sock.socketId).emit('update_message_status', {
          ...msg,
          direction: 'incoming',
          status,
        });
      });
    };

    // Start async delivery tracking (don't wait for it)
    const finalStatus = await trackMessageDelivery(msg, recipientId, deliveryTimeout);

    // persist message status
    console.log('final status:', finalStatus);
    let finalMessage;
    try {
      finalMessage = mapMessage(await __users.updateMessageStatus(socket.id, msg.id, finalStatus));
      notifyStatus(finalMessage, finalStatus);
    } catch (error) {
      finalMessage = msg;
      notifyStatus(finalMessage, finalStatus, true);
    }

    return finalMessage;

  } catch (error) {
    console.error('Error sending message:', error.message);

    return {
      success: false,
      error: error.message,
      timestamp: new Date().toISOString()
    };
  }
};

