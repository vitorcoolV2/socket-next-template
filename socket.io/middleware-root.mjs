import { allowedOrigins } from './config.mjs';
import { users } from './db.mjs';

export const rootMiddleware = (req, res) => {
  if (!req || !res) {
    throw new Error('Invalid request or response object');
  }

  console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);

  // Handle CORS
  const origin = req.headers?.origin;
  if (origin && allowedOrigins.includes(origin)) {
    res.setHeader('Access-Control-Allow-Origin', origin);
  }

  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('Access-Control-Allow-Credentials', 'true');

  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }

  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(
      JSON.stringify({
        status: 'ok',
        message: 'Server is running',
        timestamp: new Date().toISOString(),
        metrics: users.getConnectionMetrics(),
      })
    );
    return;
  }

  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Not Found' }));
};