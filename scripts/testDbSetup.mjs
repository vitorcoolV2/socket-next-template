import { Pool } from 'pg';
import dotenv from 'dotenv';

dotenv.config();

export class TestDatabase {
    constructor() {
        if (!process.env.DATABASE_URL) {
            throw new Error('DATABASE_URL is required in environment variables');
        }

        // Parse the DATABASE_URL
        const dbtest_url = new URL(process.env.DATABASE_URL);
        this.testDbName = dbtest_url.pathname.substring(1); // Remove leading slash


        // Create connection to default 'postgres' database to create test DB
        const adminConfig = {
            host: dbtest_url.hostname,
            port: dbtest_url.port || 5432,
            database: 'postgres', // Connect to default DB first
            user: dbtest_url.username,
            password: dbtest_url.password,
            ssl: dbtest_url.searchParams.get('sslmode') === 'require' ? { rejectUnauthorized: false } : false,
        };

        this.adminPool = new Pool(adminConfig);
    }

    async initialize() {
        try {
            // Create test database
            await this.adminPool.query(`CREATE DATABASE IF NOT EXISTS ${this.testDbName}`);
            console.log(`Created test database: ${this.testDbName}`);
        } catch (error) {
            // Database might already exist or other issue
            console.log('Note:', error.message);
        } finally {
            await this.adminPool.end();
        }

        // Create connection pool for the test database
        const testDbUrl = process.env.DATABASE_URL.replace(
            /(\/)([^/?]+)(\?|$)/,
            `$1${this.testDbName}$3`
        );

        this.testPool = new Pool({
            connectionString: testDbUrl,
            connectionTimeoutMillis: 5000,
            idleTimeoutMillis: 30000,
            max: 5,
        });

        return this.testDbName;
    }

    async cleanup() {
        try {
            // Close test database connections
            if (this.testPool) {
                await this.testPool.end();
            }

            // Reconnect to default database to drop test database
            const originalUrl = new URL(process.env.DATABASE_URL);
            const adminPool = new Pool({
                host: originalUrl.hostname,
                port: originalUrl.port || 5432,
                database: 'postgres',
                user: originalUrl.username,
                password: originalUrl.password,
                ssl: originalUrl.searchParams.get('sslmode') === 'require' ? { rejectUnauthorized: false } : false,
            });

            // Terminate existing connections to test database
            await adminPool.query(`
        SELECT pg_terminate_backend(pid) 
        FROM pg_stat_activity 
        WHERE datname = $1 AND pid <> pg_backend_pid()
      `, [this.testDbName]);

            // Drop test database
            //       await adminPool.query(`DROP DATABASE IF EXISTS ${this.testDbName}`);
            await adminPool.end();

            console.log(`Cleaned up test database: ${this.testDbName}`);
        } catch (error) {
            console.warn('Cleanup warning:', error.message);
        }
    }

    getPool() {
        return this.testPool;
    }

    getTestDbName() {
        return this.testDbName;
    }

    getTestConnectionString() {
        return process.env.DATABASE_URL.replace(
            /(\/)([^/?]+)(\?|$)/,
            `$1${this.testDbName}$3`
        );
    }
}