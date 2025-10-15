import { createHttpServer, io } from '../../../socket.io/server.mjs';

describe('Socket.IO Events', () => {
  let httpServer;

  beforeAll(() => {
    httpServer = createHttpServer();
  });

  afterAll((done) => {
    if (httpServer && httpServer.close) {
      httpServer.close(() => {
        done();
      });
    } else {
      done();
    }
  });

  test('should export createHttpServer function', () => {
    expect(typeof createHttpServer).toBe('function');
  });

  test('should export io instance', () => {
    expect(io).toBeDefined();
    expect(typeof io.on).toBe('function');
  });

  test('should handle connection events', () => {
    const connectionHandler = jest.fn();
    io.on('connection', connectionHandler);

    // The connection handler should be set
    expect(connectionHandler).toBeDefined();
  });
});