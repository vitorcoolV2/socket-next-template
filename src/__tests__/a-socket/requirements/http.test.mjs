// http.test.mjs
import http from 'http';

describe('HTTP Server Tests', () => {
  let server;

  beforeEach(() => {
    server = http.createServer((req, res) => {
      res.writeHead(200, { 'Content-Type': 'text/plain' });
      res.end('Hello, World!');
    });
  });

  afterEach(() => {
    if (server) {
      server.close();
    }
  });

  test('should start and stop an HTTP server', (done) => {
    jest.setTimeout(20000); // Increase timeout to 20 seconds

    server.listen(3001, () => {
      expect(server.listening).toBe(true);

      server.close(() => {
        expect(server.listening).toBe(false);
        done();
      });
    });
  }, 20000); // Set timeout explicitly
});

