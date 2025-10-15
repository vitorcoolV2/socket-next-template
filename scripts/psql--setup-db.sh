#!/bin/bash

set -e

echo "🚀 Setting up operational database..."

# Load operational environment variables
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo "❌ .env file not found"
    exit 1
fi

if [ -z "$DATABASE_URL" ]; then
    echo "❌ DATABASE_URL not found in .env"
    exit 1
fi

echo "Using DATABASE_URL from .env"

# Extract components from DATABASE_URL
DB_USER=$(echo $DATABASE_URL | sed -n 's/.*:\/\/\([^:]*\):.*/\1/p')
DB_NAME=$(echo $DATABASE_URL | sed -n 's/.*\/\([^?]*\).*/\1/p')

echo "Configuring database: $DB_NAME for user: $DB_USER"

# Grant permissions as superuser
sudo -u postgres psql -d $DB_NAME -c "
-- Ensure user can connect
GRANT CONNECT ON DATABASE $DB_NAME TO $DB_USER;

-- Grant schema permissions
GRANT USAGE ON SCHEMA public TO $DB_USER;
GRANT CREATE ON SCHEMA public TO $DB_USER;

-- Set default privileges for tables and sequences
ALTER DEFAULT PRIVILEGES FOR USER $DB_USER IN SCHEMA public 
GRANT ALL ON TABLES TO $DB_USER;

ALTER DEFAULT PRIVILEGES FOR USER $DB_USER IN SCHEMA public 
GRANT ALL ON SEQUENCES TO $DB_USER;

-- Grant permissions on existing tables (if any)
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DB_USER;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_USER;
"

echo "✅ Operational database permissions granted!"

# Verify permissions using operational DATABASE_URL
echo "🔍 Verifying operational database permissions..."
psql $DATABASE_URL -c "
-- Test connectivity and basic permissions
SELECT 'Operational database connected successfully' as status;

-- Check permissions
SELECT 
    has_schema_privilege('$DB_USER', 'public', 'CREATE') as can_create_tables,
    has_schema_privilege('$DB_USER', 'public', 'USAGE') as can_use_schema,
    has_database_privilege('$DB_USER', '$DB_NAME', 'CONNECT') as can_connect;

-- Test table operations (create temporary table)
CREATE TABLE IF NOT EXISTS operational_test (id SERIAL PRIMARY KEY, note TEXT, created_at TIMESTAMP DEFAULT NOW());
INSERT INTO operational_test (note) VALUES ('Operational database permissions working!');
SELECT * FROM operational_test;
DROP TABLE operational_test;

-- Show current table counts (if tables exist)
SELECT 'Current operational data:' as info;
SELECT 
    COUNT(*) as table_count 
FROM information_schema.tables 
WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
"

echo "🎉 Operational database setup completed successfully!"