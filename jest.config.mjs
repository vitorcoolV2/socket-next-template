// jest.config.mjs

/** @type {import('ts-jest').JestConfigWithTsJest} */
export default {
  preset: 'ts-jest/presets/default-esm',
  //testEnvironment: 'node',


  // Only include .ts and .tsx - .mjs is automatically treated as ESM
  extensionsToTreatAsEsm: ['.ts', '.tsx'],

  // Simplified transform configuration
  transform: {
    '^.+\\.(ts|tsx)$': [
      'ts-jest',
      {
        useESM: true,
      }
    ],
    '^.+\\.(js|jsx|mjs)$': 'babel-jest',
  },

  // Transform ignore patterns for ESM packages
  transformIgnorePatterns: [
    '/node_modules/',
    '/node_modules/(?!jose|jwks-rsa|engine.io-client|ws|pg)/',
  ],

  moduleNameMapper: {
    '^(\\.{1,2}/.*)\\.js$': '$1',
    // Update to use .js extension for mocks
    // All CommonJS mocks
    '^jose$': '<rootDir>/__mocks__/jose/index.js',
    '^jwks-rsa$': '<rootDir>/__mocks__/jwks-rsa/index.js',
    '^socket.io$': '<rootDir>/__mocks__/socket.io.js',
    '^http$': '<rootDir>/__mocks__/http.js',
    '^https$': '<rootDir>/__mocks__/http.js', // Reuse http mock
    '^express$': '<rootDir>/__mocks__/express.js',
    '^ws$': '<rootDir>/__mocks__/ws.js',
    // '^net$': '<rootDir>/__mocks__/net.mjs', // <-- DELETE THIS LINE
    // '^net$': '<rootDir>/__mocks__/net.js', // <-- DELETE THIS LINE
    // '^pg$': '<rootDir>/__mocks__/pg.mjs', // Commented out pg mock
  },



  // Add to handle cleanup issues
  detectOpenHandles: true,
  forceExit: true,

  collectCoverage: false,

  testMatch: [
    '**/__tests__/**/*.?(m)[jt]s?(x)',
    '**/?(*.)+(spec|test).?(m)[jt]s?(x)',
    '**/__tests__/**/*(*.)@(test|spec).mjs',

  ],


  setupFilesAfterEnv: ['<rootDir>/jest.setup.mjs'],
  //globalTeardown: '<rootDir>/jest.teardown.mjs',
};