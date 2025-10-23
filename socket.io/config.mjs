import dotenv from 'dotenv';

// Load from test environment if available
dotenv.config({ path: process.env.NODE_ENV === 'test' ? './.env.test' : './.env' });

export const PASSPORT_PATH = process.env.PASSPORT_PATH || './passport.json';
export const debug = process.env.NODE_ENV !== 'production';
export const PUBLIC_MESSAGE_USER_ID = 'EVERY_ONE_ONLINE';
export const PUBLIC_MESSAGE_EXPIRE_DAYS = 30;
export const PRIVATE_MESSAGE_DELIVER_EXPIRE_DAYS = 30;
export const SOCKET_MIDDLEWARE = process.env.SOCKET_MIDDLEWARE || 'testMiddleware';
export const INACTIVITY_THRESHOLD = 60 * 60 * 1000; // 1 hour (in milliseconds)
export const INACTIVITY_CHECK_INTERVAL = 60 * 1000; // 1 minute (in milliseconds)
export const MESSAGE_ACKNOWLEDGEMENT_TIMEOUT = 10000; // 10 sec....time to up remote client && return ack('receive')