
export const withTimeout = (promise, timeoutError = 'Request timed out', timeoutMs = 10000) => {
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      const timeoutId = setTimeout(() => {
        clearTimeout(timeoutId); // Clear the timeout to avoid memory leaks
        reject(new Error(timeoutError));
      }, timeoutMs);
    }),
  ]).catch(error => {
    console.error('Error in withTimeout:', error.message);
    throw error; // Rethrow the error after logging
  });
};

// mapper from usermanager to final client
export const mapMessage = msg => ({
  id: msg.messageId,
  senderId: msg.sender.userId,
  senderName: msg.sender.userName,
  recipientId: msg.recipientId,
  content: msg.content,
  status: msg.status,
  type: msg.type,
  direction: msg.direction,
  createdAt: msg.createdAt,
  updatedAt: msg.updatedAt,
  readAt: msg.readAt,
});



// Prevent predictable timeout exceptions from crashing the app
export const catchTimeoutExceptions = (reason, promise) => {
  console.error('Unhandled Rejection at:', promise, 'reason:', reason);

  // Exit the process only for unexpected or critical errors
  if (!['Request timed out', 'Invalid data'].includes(reason.message)) {
    console.error('Critical error detected. Exiting process...');
    process.exit(1);
  } else {
    console.warn('Predictable error detected. Continuing execution...');
  }
};


