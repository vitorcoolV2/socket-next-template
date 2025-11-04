
import { users as __users } from 'a-socket/db.mjs';


export const trackMessageDelivery = async (msg, recipientId, deliveryTimeout) => {
  try {
    const __io = __users.getIO();
    const recipientSockets = await __users.getUserSockets(recipientId);

    const messageToAck = { ...msg, direction: 'incoming', status: 'delivered' };

    if (!recipientSockets?.length) {
      // No sockets available - mark as pending
      return 'pending';
    }

    const deliveryPromises = recipientSockets.map(async (sock) => {
      return new Promise((resolve) => {
        let timeoutId = setTimeout(() => {
          console.warn('Delivery timeout for socket:', sock.socketId);
          resolve({
            success: false,
            socketId: sock.socketId,
            cause: 'timeout'
          });
        }, deliveryTimeout);

        // Emit to recipient
        const ioTimeout = Math.min(deliveryTimeout - 50, 50);
        __io
          .timeout(ioTimeout)
          .to(sock.socketId)
          .emit(
            'update_message_status',
            messageToAck,
            (err, responses) => {
              clearTimeout(timeoutId);
              if (err) {
                resolve({
                  success: false,
                  socketId: sock.socketId,
                  cause: 'emit_error'
                });
                return;
              }

              const ack = Array.isArray(responses) ? responses[0] : responses;
              const isSuccess = ack?.success === true && ack?.message === 'received';

              resolve({
                success: isSuccess,
                socketId: sock.socketId,
                cause: isSuccess ? 'delivered' : 'invalid_ack'
              });
            }
          );
      });
    });

    // Wait for all delivery attempts
    const results = await Promise.allSettled(deliveryPromises);
    const successfulDeliveries = results.filter(
      result => result.status === 'fulfilled' && result.value.success === true
    );

    // Update final status
    const finalStatus = successfulDeliveries.length > 0 ? 'delivered' : 'pending';
    return finalStatus;

  } catch (error) {
    console.error('Error in delivery tracking:', error.message);
    // Fallback to pending status
    return 'pending';
  }
};