import { DEFAULT_REQUEST_TIMEOUT } from 'a-socket/config.mjs';
import { withTimeout } from './utils.mjs';
import { users as __users } from 'a-socket/db.mjs';

export const registerEventHandlers = (socket, handlers) => {
  Object.entries(handlers).forEach(([eventName, eventHandler, eventAck, timeout]) => {
    registerEventHandler(socket, { eventName, eventHandler, eventAck, timeout });
  });
};

/**
 * Registers a single event handler with customizable properties.
 *
 * @param {Socket} socket - The Socket.IO socket instance.
 * @param {Object} options - Event handler configuration.
 * @param {string} options.eventName - The name of the event.
 * @param {Function} options.eventHandler - The function to handle the event.
 * @param {boolean} [options.eventAck=false] - Whether the event requires acknowledgment.
 * @param {number} [options.timeout=10000] - Timeout duration in milliseconds.
 */
export const registerEventHandler = (socket, { eventName, eventHandler, eventAck = false, timeout = DEFAULT_REQUEST_TIMEOUT }) => {
  socket.on(eventName, createEventHandler(eventName, eventHandler, eventAck, timeout));
};

/**
 * Creates a wrapper for an event handler with validation, timeout, and acknowledgment support.
 *
 * @param {string} eventName - The name of the event.
 * @param {Function} eventHandler - The function to handle the event.
 * @param {boolean} eventAck - Whether the event requires acknowledgment.
 * @param {number} timeout - Timeout duration in milliseconds.
 * @returns {Function} - The wrapped event handler function.
 */
export function createEventHandler(eventName, eventHandler, eventAck = false, timeout = 10000) {
  return async function (data, callback) {
    // Step 1: Validate input data
    if (!data || typeof data !== 'object') {
      const errorResponse = {
        success: false,
        event: eventName,
        error: 'Invalid data'
      };
      respondOrFallback(callback, this, errorResponse);
      return;
    }

    try {
      // Step 2: Retrieve user information
      const user = await __users.getUserBySocketId(this.id);
      console.info('>>> ', [eventName], 'user:', [user?.state, user?.userId]);

      // Step 3: Execute the event handler with a timeout
      const result = await withTimeout(
        eventHandler(this, data, callback),
        'Request timed out',
        timeout
      );

      // Step 4: Handle successful response
      const successResponse = {
        success: true,
        event: eventName,
        result
      };

      // If acknowledgment is required, ensure the callback is called
      if (eventAck && typeof callback === 'function') {
        callback(successResponse);
      } else {
        respondOrFallback(callback, this, successResponse);
      }

      return result;
    } catch (error) {
      // Step 5: Log and handle errors
      console.error('>>> ', `[${eventName}]`, 'Error:', error.message);
      __users._incrementErrors();

      const errorResponse = {
        success: false,
        event: eventName,
        error: error.message
      };

      // If acknowledgment is required, ensure the callback is called
      if (eventAck && typeof callback === 'function') {
        callback(errorResponse);
      } else {
        respondOrFallback(callback, this, errorResponse);
      }

      // Step 6: Re-throw only unexpected or critical errors
      if (!['Request timed out', 'Invalid data'].includes(error.message)) {
        throw error;
      }
    }
  };
}

// Utility function to handle responses or fallbacks
export function respondOrFallback(callback, socket, response) {
  if (typeof callback === 'function') {
    callback(response);
  } else {
    socket.emit('response', response);
  }
}