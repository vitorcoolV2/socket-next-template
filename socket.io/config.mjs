import dotenv from 'dotenv';

// Load from test environment if available
dotenv.config({ path: process.env.NODE_ENV === 'test' ? './.env.test' : './.env' });

export const PASSPORT_PATH = process.env.PASSPORT_PATH || './passport.json';
export const debug = process.env.NODE_ENV !== 'production';

// http
export const allowedOrigins = [
    process.env.CLIENT_URL || 'http://localhost:3000',
    'http://localhost:3000',
    'http://127.0.0.1:3000',
];

// user manager instance create args
export const USER_MANAGER_PERSIST = process.env.USER_MANAGER_PERSIST;
export const MAX_TOTAL_CONNECTIONS = process.env.MAX_TOTAL_CONNECTIONS;

// public ID
export const PUBLIC_MESSAGE_USER_ID = 'EVERY_ONE_ONLINE';
export const PUBLIC_MESSAGE_EXPIRE_DAYS = 30;
export const PRIVATE_MESSAGE_DELIVER_EXPIRE_DAYS = 30;

// auth middleware
export const SOCKET_MIDDLEWARE = process.env.SOCKET_MIDDLEWARE;
// User session
export const INACTIVITY_THRESHOLD = process.env.INACTIVITY_THRESHOLD || 60 * 60 * 1000; // 1 hour (in milliseconds)
export const INACTIVITY_CHECK_INTERVAL = process.env.INACTIVITY_CHECK_INTERVAL || 60 * 1000; // 1 minute (in milliseconds)
// operations timeout defaults, custom timeout operations
// Timeout configurations with environment-specific defaults
export const DEFAULT_REQUEST_TIMEOUT = parseInt(process.env.DEFAULT_REQUEST_TIMEOUT) ||
    (process.env.NODE_ENV === 'test' ? 8000 : 15000);

export const MESSAGE_ACKNOWLEDGEMENT_TIMEOUT = parseInt(process.env.MESSAGE_ACKNOWLEDGEMENT_TIMEOUT) ||
    (process.env.NODE_ENV === 'test' ? 3000 : 10000);

// Safe timeout calculator to prevent negative values
export const getSafeTimeouts = (clientTimeout = DEFAULT_REQUEST_TIMEOUT) => {
    const MIN_TIMEOUT = 100; // Minimum 100ms for any timeout
    const MAX_TIMEOUT = 3000;
    const CLEANUP_BUFFER = 2000; // 2 seconds for cleanup

    const safeClientTimeout = Math.max(clientTimeout, MIN_TIMEOUT + CLEANUP_BUFFER);
    const deliveryTimeout = Math.min(
        MESSAGE_ACKNOWLEDGEMENT_TIMEOUT,
        Math.max(safeClientTimeout - CLEANUP_BUFFER, MIN_TIMEOUT)
    );

    return {
        handlerTimeout: Math.max(safeClientTimeout - 1000, MIN_TIMEOUT),
        deliveryTimeout: Math.min(deliveryTimeout, MAX_TIMEOUT),
    };
};