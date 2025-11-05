import { jest, describe, expect, test } from '@jest/globals';
import { passportMiddleware } from 'a-socket/middleware-auth.mjs'; // Corrected import

const validTokenUserId = 'test-user-123';
const validToken = MOCK_TOKENS.validUser;

const expiredToken = MOCK_TOKENS.expiredUser;



// Define the mock function outside jest.mock()
const mockVerifyToken = jest.fn();

// Mock the module with the mock function
jest.mock('a-socket/jwt-passport/index.mjs', () => ({
  verifyToken: mockVerifyToken,
}));

describe('Passport Middleware', () => {
  let mockSocket;

  beforeEach(() => {
    // Mock Socket.IO instance


    // Mock socket object
    mockSocket = {
      id: validTokenUserId,
      handshake: {
        auth: { token: validToken },
      },
      emit: jest.fn(),
    };
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  test('should authenticate user and attach user info to socket', async () => {
    const next = jest.fn();

    // Mock token validation (success case)

    // Invoke middleware
    await passportMiddleware(mockSocket, next);

    // Verify authentication succeeded
    expect(next).toHaveBeenCalledWith();

    // Verify user info is attached to the socket
    expect(mockSocket.user).toBeDefined();
    expect(mockSocket.user.userId).toBe('test-user-123');
    expect(mockSocket.user.userName).toBe('Test User');

    // Verify client notification
    expect(mockSocket.emit).toHaveBeenCalledWith('user_authenticated', {
      state: 'authenticated',
      success: true,
      userId: 'test-user-123',
      userName: 'Test User',
    });
  });

  test('should fail authentication with invalid token', async () => {
    mockSocket = {
      id: "expired-User",
      handshake: {
        auth: { token: expiredToken },
      },
      emit: jest.fn(),
    };
    const next = jest.fn();


    // Invoke middleware
    await passportMiddleware(mockSocket, next);

    // Verify authentication failed
    expect(next).toHaveBeenCalledWith(expect.any(Error));
    expect(next.mock.calls[0][0].message).toContain('Authentication failed: Token expired');
  });
});