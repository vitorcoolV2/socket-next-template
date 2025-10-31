import { jest, describe, expect, test } from '@jest/globals';
import { testMiddleware } from 'a-socket/middleware-auth.mjs';

describe('Test Middleware', () => {
  let mockSocket;

  beforeEach(() => {
    // Mock socket object
    mockSocket = {
      id: 'socket-123',
      handshake: {
        auth: {}, // No token required for testMiddleware
      },
      emit: jest.fn(),
    };
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  test('should attach user info to socket and emit user_authenticated event', async () => {
    const next = jest.fn();

    // Invoke middleware
    await testMiddleware(mockSocket, next);

    // Verify authentication succeeded
    expect(next).toHaveBeenCalledWith();

    // Verify user info is attached to the socket
    expect(mockSocket.user).toBeDefined();
    expect(mockSocket.user.userId).toBe('test-user');
    expect(mockSocket.user.userName).toBe('Test name');

    // Verify client notification
    expect(mockSocket.emit).toHaveBeenCalledWith('user_authenticated', {
      state: 'authenticated',
      success: true,
      userId: 'test-user',
      userName: 'Test name',
    });
  });
});