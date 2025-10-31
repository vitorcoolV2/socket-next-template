// jest.config.mjs

import fs from 'fs';
import path from 'path';

// Load the root package.json
const rootPackageJsonPath = path.resolve('./package.json');
const rootPackageJson = JSON.parse(fs.readFileSync(rootPackageJsonPath, 'utf-8'));

// Extract dependencies with the `a-*` prefix and type `file:`
const localDependencies = Object.entries(rootPackageJson.dependencies || {})
  .filter(([name]) => name.startsWith('a-') && rootPackageJson.dependencies[name].startsWith('file:'))
  .map(([name, filePath]) => ({
    name,
    path: filePath.replace('file:', ''), // Remove the `file:` prefix
  }));

// Generate moduleNameMapper dynamically
const moduleNameMapper = localDependencies.reduce((mapper, { name, path }) => {
  mapper[`^${name}(.*)$`] = `<rootDir>/${path}$1`;
  return mapper;
}, {});


/** @type {import('ts-jest').JestConfigWithTsJest} */
const jestConfig = {
  roots: [
    '<rootDir>/src/__tests__', // Default test directory
  ],
  preset: 'ts-jest/presets/default-esm',
  moduleNameMapper,
  testEnvironment: 'node',


  testPathIgnorePatterns: [
    "/node_modules/",
    "~$", // Ends with ~
    "^~"  // Starts with ~
  ],

  // Only include .ts and .tsx - .mjs is automatically treated as ESM
  extensionsToTreatAsEsm: ['.ts', '.tsx',],

  // Simplified transform configuration
  transform: {
    '^.+\\.(ts|tsx)$': [
      'ts-jest',
      {
        useESM: true,
      }
    ],
    //'^.+\\.(js|jsx|mjs)$': 'babel-jest',
    '^.+\\.mjs$': ['babel-jest', { presets: ['@babel/preset-env'] }],
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

  },



  // Add to handle cleanup issues
  detectOpenHandles: true,
  forceExit: true,

  collectCoverage: false,

  testMatch: [
    '**/?(*.)+(spec|test).?(m)[jt]s?(x)',
    '**/__tests__/**/*(*.)@(test|spec).mjs',
  ],


  setupFilesAfterEnv: ['<rootDir>/jest.setup.mjs'],
  //globalTeardown: '<rootDir>/jest.teardown.mjs',
};

export default jestConfig;