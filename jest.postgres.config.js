module.exports = {
  testEnvironment: 'node',
  extensionsToTreatAsEsm: ['.mjs'],
  transform: {},
  testMatch: ['**/__tests__/*postgres*.test.mjs'],
  automock: false, // Disable automocking for these tests
  resetMocks: false,
  restoreMocks: false,
};