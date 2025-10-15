// messageCleanupUtils.mjs
export const cleanupOldMessages = (userMessages, debug = false, threshold = 7 * 24 * 60 * 60 * 1000) => {
    const now = Date.now();
    let cleaned = 0;

    userMessages.forEach((messages, userId) => {
        const filteredMessages = messages.filter(msg => now - new Date(msg.timestamp) <= threshold);
        if (filteredMessages.length < messages.length) {
            userMessages.set(userId, filteredMessages);
            cleaned += messages.length - filteredMessages.length;
        }
    });

    if (debug) console.log(`Cleaned up ${cleaned} old messages`);
    return cleaned;
};