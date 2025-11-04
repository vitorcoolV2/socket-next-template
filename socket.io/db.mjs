
import { userManager } from 'a-socket/userManager/index.mjs';
import {
  USER_MANAGER_PERSIST,
  MAX_TOTAL_CONNECTIONS
} from './config.mjs';



// Initialize user manager first to avoid circular dependencies
export const users = userManager({
  io: null, // Will be set after io initialization
  defaultStorage: USER_MANAGER_PERSIST || 'memory',
  maxTotalConnections: parseInt(MAX_TOTAL_CONNECTIONS, 10) || 1000,
});

