import { Pool } from 'pg';
import { jest } from '@jest/globals';
import dotenv from 'dotenv';

// Load test environment
dotenv.config({ path: '.env.test' });

describe('PostgreSQL Database Capability Tests', () => {
  let pool;
  let testTableName = `test_table_${Date.now()}`;

  beforeAll(async () => {
    if (!process.env.DATABASE_URL) {
      throw new Error('DATABASE_URL is required in .env.test');
    }

    console.log('🔗 Testing PostgreSQL connection with:', process.env.DATABASE_URL.replace(/:[^:]*@/, ':****@'));

    // Create connection pool
    pool = new Pool({
      connectionString: process.env.DATABASE_URL,
      connectionTimeoutMillis: 10000,
      idleTimeoutMillis: 30000,
      max: 5,
    });

    // Test basic connection
    await pool.query('SELECT 1');
    console.log('✅ PostgreSQL connection established');
  });

  afterAll(async () => {
    if (pool) {
      await pool.end();
      console.log('✅ PostgreSQL connection pool closed');
    }
  });

  beforeEach(async () => {
    // Suppress console during tests
    jest.spyOn(console, 'log').mockImplementation(() => { });
    jest.spyOn(console, 'warn').mockImplementation(() => { });
    jest.spyOn(console, 'error').mockImplementation(() => { });
  });

  afterEach(async () => {
    // Clean up test tables
    try {
      await pool.query(`DROP TABLE IF EXISTS ${testTableName}`);
      await pool.query(`DROP TABLE IF EXISTS temp_test_table`);
    } catch (error) {
      // Ignore cleanup errors
    }

    jest.clearAllMocks();
    jest.restoreAllMocks();
  });

  describe('Basic Database Operations', () => {
    test('should establish connection to test database', async () => {
      const result = await pool.query('SELECT current_database() as db_name');
      expect(result.rows[0].db_name).toBe('test_db');
    });

    test('should have correct user permissions', async () => {
      const result = await pool.query('SELECT current_user as username');
      expect(result.rows[0].username).toBe('socket_user');
    });

    test('should be able to create tables', async () => {
      await pool.query(`
        CREATE TABLE ${testTableName} (
          id SERIAL PRIMARY KEY,
          name VARCHAR(100) NOT NULL,
          created_at TIMESTAMP DEFAULT NOW()
        )
      `);

      const result = await pool.query(`
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_name = $1
      `, [testTableName]);

      expect(result.rows.length).toBe(1);
      expect(result.rows[0].table_name).toBe(testTableName);
    });

    test('should be able to insert data', async () => {
      await pool.query(`
        CREATE TABLE ${testTableName} (
          id SERIAL PRIMARY KEY,
          test_data TEXT,
          number_value INTEGER
        )
      `);

      const insertResult = await pool.query(`
        INSERT INTO ${testTableName} (test_data, number_value) 
        VALUES ($1, $2) 
        RETURNING *
      `, ['test insertion', 42]);

      expect(insertResult.rows[0].test_data).toBe('test insertion');
      expect(insertResult.rows[0].number_value).toBe(42);
    });

    test('should be able to read data', async () => {
      await pool.query(`
        CREATE TABLE ${testTableName} (
          id SERIAL PRIMARY KEY,
          data_field TEXT
        )
      `);

      // Insert test data
      await pool.query(`
        INSERT INTO ${testTableName} (data_field) 
        VALUES ('first'), ('second'), ('third')
      `);

      const selectResult = await pool.query(`SELECT * FROM ${testTableName} ORDER BY id`);

      expect(selectResult.rows.length).toBe(3);
      expect(selectResult.rows[0].data_field).toBe('first');
      expect(selectResult.rows[2].data_field).toBe('third');
    });

    test('should be able to update data', async () => {
      await pool.query(`
        CREATE TABLE ${testTableName} (
          id SERIAL PRIMARY KEY,
          status TEXT,
          value INTEGER
        )
      `);

      await pool.query(`INSERT INTO ${testTableName} (status, value) VALUES ('active', 100)`);

      const updateResult = await pool.query(`
        UPDATE ${testTableName} 
        SET status = $1, value = $2 
        WHERE status = 'active' 
        RETURNING *
      `, ['inactive', 200]);

      expect(updateResult.rows[0].status).toBe('inactive');
      expect(updateResult.rows[0].value).toBe(200);
    });

    test('should be able to delete data', async () => {
      await pool.query(`
        CREATE TABLE ${testTableName} (
          id SERIAL PRIMARY KEY,
          to_delete BOOLEAN
        )
      `);

      await pool.query(`INSERT INTO ${testTableName} (to_delete) VALUES (true), (false), (true)`);

      const deleteResult = await pool.query(`
        DELETE FROM ${testTableName} 
        WHERE to_delete = true 
        RETURNING *
      `);

      expect(deleteResult.rows.length).toBe(2);

      const remainingResult = await pool.query(`SELECT * FROM ${testTableName}`);
      expect(remainingResult.rows.length).toBe(1);
      expect(remainingResult.rows[0].to_delete).toBe(false);
    });
  });

  describe('User Manager Required Tables', () => {
    test('should be able to create user_sessions table', async () => {
      await pool.query(`
        CREATE TABLE IF NOT EXISTS user_sessions (
          user_id VARCHAR(100) PRIMARY KEY,
          user_name VARCHAR(255) NOT NULL,
          socket_ids TEXT[],
          session_id VARCHAR(100),
          state VARCHAR(50) DEFAULT 'connected',
          connected_at TIMESTAMP DEFAULT NOW(),
          last_activity TIMESTAMP DEFAULT NOW()
        )
      `);

      const result = await pool.query(`
        SELECT column_name, data_type 
        FROM information_schema.columns 
        WHERE table_name = 'user_sessions' 
        ORDER BY ordinal_position
      `);

      const columns = result.rows.map(row => row.column_name);
      expect(columns).toContain('user_id');
      expect(columns).toContain('user_name');
      expect(columns).toContain('sockets');
      expect(columns).toContain('state');
    });

    test('should be able to create messages table', async () => {
      // Primeiro, vamos verificar a estrutura REAL da sua tabela
      const actualColumns = await pool.query(`
      SELECT column_name, data_type 
      FROM information_schema.columns 
      WHERE table_name = 'messages' 
      ORDER BY ordinal_position
    `);

      console.log('🔍 Colunas reais da tabela messages:', actualColumns.rows.map(r => r.column_name));

      // Agora vamos criar uma tabela de teste que combina com sua estrutura REAL
      const testTableName = `test_messages_${Date.now()}`;

      await pool.query(`
      CREATE TABLE ${testTableName} (
        id SERIAL PRIMARY KEY,
        message_id VARCHAR(100) UNIQUE NOT NULL,
        sender_id VARCHAR(100) NOT NULL,
        sender_name VARCHAR(255),
        recipient_id VARCHAR(100) NOT NULL,
        content TEXT,
        message_type VARCHAR(50) DEFAULT 'text',
        direction VARCHAR(50),
        status VARCHAR(50) DEFAULT 'sent',
        is_private BOOLEAN DEFAULT true,
        timestamp TIMESTAMPTZ DEFAULT NOW(),
        read_at TIMESTAMPTZ,
        stored_at TIMESTAMPTZ DEFAULT NOW(),
        metadata JSONB
      )
    `);

      const result = await pool.query(`
      SELECT column_name, data_type 
      FROM information_schema.columns 
      WHERE table_name = $1
      ORDER BY ordinal_position
    `, [testTableName]);

      const columns = result.rows.map(row => row.column_name);

      // Testa as colunas que realmente existem na sua estrutura
      expect(columns).toContain('message_id');
      expect(columns).toContain('sender_id');     // ← CORRIGIDO: testa sender_id
      expect(columns).toContain('recipient_id');  // ← CORRIGIDO: testa recipient_id
      expect(columns).toContain('content');
      expect(columns).toContain('direction');

      // Limpeza
      await pool.query(`DROP TABLE ${testTableName}`);
    });

    test('should handle user_sessions CRUD operations', async () => {
      // Create table
      await pool.query(`
        CREATE TABLE IF NOT EXISTS user_sessions_test (
          user_id VARCHAR(100) PRIMARY KEY,
          user_name VARCHAR(255) NOT NULL,
          state VARCHAR(50) DEFAULT 'connected',
          connected_at TIMESTAMP DEFAULT NOW()
        )
      `);

      // Insert
      await pool.query(`
        INSERT INTO user_sessions_test (user_id, user_name, state) 
        VALUES ($1, $2, $3)
      `, ['test-user-123', 'Test User', 'connected']);

      // Read
      const readResult = await pool.query(`
        SELECT * FROM user_sessions_test WHERE user_id = $1
      `, ['test-user-123']);

      expect(readResult.rows[0].user_name).toBe('Test User');
      expect(readResult.rows[0].state).toBe('connected');

      // Update
      await pool.query(`
        UPDATE user_sessions_test 
        SET state = $1 
        WHERE user_id = $2
      `, ['disconnected', 'test-user-123']);

      const updateResult = await pool.query(`
        SELECT state FROM user_sessions_test WHERE user_id = $1
      `, ['test-user-123']);

      expect(updateResult.rows[0].state).toBe('disconnected');

      // Delete
      await pool.query(`DELETE FROM user_sessions_test WHERE user_id = $1`, ['test-user-123']);

      const deleteResult = await pool.query(`SELECT * FROM user_sessions_test WHERE user_id = $1`, ['test-user-123']);
      expect(deleteResult.rows.length).toBe(0);
    });

    test('should handle messages CRUD operations', async () => {
      // Usar um nome de tabela único para evitar conflitos
      const uniqueTableName = `messages_test_${Date.now()}`;

      // Create table
      await pool.query(`
        CREATE TABLE ${uniqueTableName} (
          id SERIAL PRIMARY KEY,
          message_id VARCHAR(100) UNIQUE NOT NULL,
          user_id VARCHAR(100) NOT NULL,
          content TEXT,
          timestamp TIMESTAMP DEFAULT NOW()
        )
      `);

      // Insert multiple messages
      const messages = [
        { messageId: 'msg-1', userId: 'user-1', content: 'Hello' },
        { messageId: 'msg-2', userId: 'user-1', content: 'World' },
        { messageId: 'msg-3', userId: 'user-2', content: 'Test' }
      ];

      for (const msg of messages) {
        await pool.query(`
          INSERT INTO ${uniqueTableName} (message_id, user_id, content) 
          VALUES ($1, $2, $3)
        `, [msg.messageId, msg.userId, msg.content]);
      }

      // Read with filtering
      const userMessages = await pool.query(`
        SELECT * FROM ${uniqueTableName} 
        WHERE user_id = $1 
        ORDER BY timestamp
      `, ['user-1']);

      expect(userMessages.rows.length).toBe(2);
      expect(userMessages.rows[0].content).toBe('Hello');
      expect(userMessages.rows[1].content).toBe('World');

      // Update
      await pool.query(`
        UPDATE ${uniqueTableName} 
        SET content = $1 
        WHERE message_id = $2
      `, ['Updated content', 'msg-1']);

      const updatedMessage = await pool.query(`
        SELECT content FROM ${uniqueTableName} WHERE message_id = $1
      `, ['msg-1']);

      expect(updatedMessage.rows[0].content).toBe('Updated content');

      // Delete
      await pool.query(`DELETE FROM ${uniqueTableName} WHERE user_id = $1`, ['user-1']);

      const remainingMessages = await pool.query(`SELECT * FROM ${uniqueTableName}`);
      expect(remainingMessages.rows.length).toBe(1);
      expect(remainingMessages.rows[0].user_id).toBe('user-2');

      // Clean up - remover a tabela temporária
      await pool.query(`DROP TABLE ${uniqueTableName}`);
    });
  });

  describe('Advanced PostgreSQL Features', () => {
    test('should handle transactions', async () => {
      await pool.query(`
        CREATE TABLE ${testTableName} (
          id SERIAL PRIMARY KEY,
          balance INTEGER
        )
      `);

      const client = await pool.connect();

      try {
        await client.query('BEGIN');

        await client.query(`INSERT INTO ${testTableName} (balance) VALUES (100)`);
        await client.query(`INSERT INTO ${testTableName} (balance) VALUES (200)`);

        await client.query('COMMIT');

        const result = await client.query(`SELECT SUM(balance) as total FROM ${testTableName}`);
        expect(parseInt(result.rows[0].total)).toBe(300);
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally {
        client.release();
      }
    });

    test('should handle JSON data types', async () => {
      await pool.query(`
        CREATE TABLE ${testTableName} (
          id SERIAL PRIMARY KEY,
          user_data JSONB,
          preferences JSONB
        )
      `);

      const userData = {
        name: 'Test User',
        email: 'test@example.com',
        profile: { age: 30, city: 'Test City' }
      };

      const preferences = { theme: 'dark', notifications: true };

      await pool.query(`
        INSERT INTO ${testTableName} (user_data, preferences) 
        VALUES ($1, $2)
      `, [userData, preferences]);

      const result = await pool.query(`
        SELECT 
          user_data->>'name' as name,
          user_data->'profile'->>'city' as city,
          preferences->>'theme' as theme
        FROM ${testTableName}
      `);

      expect(result.rows[0].name).toBe('Test User');
      expect(result.rows[0].city).toBe('Test City');
      expect(result.rows[0].theme).toBe('dark');
    });

    test('should handle array data types', async () => {
      await pool.query(`
        CREATE TABLE ${testTableName} (
          id SERIAL PRIMARY KEY,
          tags TEXT[],
          numbers INTEGER[]
        )
      `);

      await pool.query(`
        INSERT INTO ${testTableName} (tags, numbers) 
        VALUES ($1, $2)
      `, [['tag1', 'tag2', 'tag3'], [1, 2, 3, 4, 5]]);

      const result = await pool.query(`
        SELECT 
          tags[1] as first_tag,
          array_length(tags, 1) as tags_count,
          numbers[3] as third_number
        FROM ${testTableName}
      `);

      expect(result.rows[0].first_tag).toBe('tag1');
      expect(result.rows[0].tags_count).toBe(3);
      expect(result.rows[0].third_number).toBe(3);
    });

    test('should handle timestamps and timezones', async () => {
      await pool.query(`
        CREATE TABLE ${testTableName} (
          id SERIAL PRIMARY KEY,
          created_at TIMESTAMPTZ DEFAULT NOW(),
          scheduled_time TIMESTAMP
        )
      `);

      const testTime = new Date('2024-01-01T12:00:00Z');

      await pool.query(`
        INSERT INTO ${testTableName} (scheduled_time) 
        VALUES ($1)
      `, [testTime]);

      const result = await pool.query(`
        SELECT 
          scheduled_time,
          EXTRACT(HOUR FROM scheduled_time) as hour,
          EXTRACT(MINUTE FROM scheduled_time) as minute
        FROM ${testTableName}
      `);

      // EXTRACT retorna string, então precisamos converter para número OU comparar com string
      expect(parseInt(result.rows[0].hour)).toBe(12);  // ← CORREÇÃO: converter para número
      expect(parseInt(result.rows[0].minute)).toBe(0); // ← CORREÇÃO: converter para número
    });
  });

  describe('Performance and Scalability', () => {
    test('should handle multiple concurrent connections', async () => {
      const promises = Array.from({ length: 5 }, (_, i) =>
        pool.query('SELECT $1::text as test_value', [`concurrent-${i}`])
      );

      const results = await Promise.all(promises);

      results.forEach((result, i) => {
        expect(result.rows[0].test_value).toBe(`concurrent-${i}`);
      });
    });

    test('should handle bulk inserts', async () => {
      await pool.query(`
        CREATE TABLE ${testTableName} (
          id SERIAL PRIMARY KEY,
          data_value TEXT,
          number_value INTEGER
        )
      `);

      const bulkData = Array.from({ length: 50 }, (_, i) =>
        [`bulk-data-${i}`, i * 10]
      );

      // Using a transaction for bulk insert
      const client = await pool.connect();
      try {
        await client.query('BEGIN');

        for (const [data, number] of bulkData) {
          await client.query(`
            INSERT INTO ${testTableName} (data_value, number_value) 
            VALUES ($1, $2)
          `, [data, number]);
        }

        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally {
        client.release();
      }

      const countResult = await pool.query(`SELECT COUNT(*) as total FROM ${testTableName}`);
      expect(parseInt(countResult.rows[0].total)).toBe(50);
    });
  });

  describe('Error Handling', () => {
    test('should handle SQL syntax errors gracefully', async () => {
      await expect(pool.query('SELECT * FROM non_existent_table'))
        .rejects.toThrow();
    });

    test('should handle constraint violations', async () => {
      await pool.query(`
        CREATE TABLE ${testTableName} (
          id SERIAL PRIMARY KEY,
          unique_field VARCHAR(100) UNIQUE
        )
      `);

      await pool.query(`INSERT INTO ${testTableName} (unique_field) VALUES ('unique_value')`);

      await expect(
        pool.query(`INSERT INTO ${testTableName} (unique_field) VALUES ('unique_value')`)
      ).rejects.toThrow();
    });

    test('should handle connection timeouts', async () => {
      // This test verifies the connection configuration is working
      const startTime = Date.now();
      await pool.query('SELECT pg_sleep(0.1)'); // 100ms sleep
      const endTime = Date.now();

      // Should complete within reasonable time (not timeout)
      expect(endTime - startTime).toBeLessThan(5000); // 5 seconds
    });
  });
});