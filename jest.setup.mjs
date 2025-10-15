// Import required modules
import '@testing-library/jest-dom'; // For DOM testing utilities
import { jest, describe, expect, test } from '@jest/globals'; // Or rely on global scope


const loadDotenv = async () => {
    const dotenv = await import('dotenv');
    dotenv.config({ path: '.env.test' });
};

await loadDotenv();

global.USER_MANAGER_PERSIST = process.env.USER_MANAGER_PERSIST || 'memory';

import {
    jwks,
    testTokens,
    passportData,
    testKeys
} from './scripts/gen-test-tokens.mjs'; // Ensure test tokens are generated


global.MOCK_JWKS = jwks;
global.MOCK_TOKENS = testTokens;
global.MOCK_PASSPORT = passportData;
global.MOCK_KEYS = testKeys;

import dotenv from 'dotenv';

// Load test environment variables
dotenv.config({ path: './.env.test' });

global.jest = jest;
global.describe = describe;
global.expect = expect;
global.test = test;

// Polyfill TextEncoder and TextDecoder
import textEncoding from 'text-encoding';
const { TextEncoder, TextDecoder } = textEncoding;

global.TextEncoder = TextEncoder;
global.TextDecoder = TextDecoder;

// Global mocks
/*
global.console = {
    ...console,
    log: jest.fn(),
    error: jest.fn(),
    warn: jest.fn(),
    info: jest.fn(),
    debug: jest.fn(),
};
*/
console.warn = jest.fn();
console.error = jest.fn();
console.log = jest.fn();
console.info = jest.fn();
console.debug = jest.fn();




// Global test timeout
jest.setTimeout(10000);

// Reset all mocks between tests
beforeEach(() => {
    jest.clearAllMocks();
});