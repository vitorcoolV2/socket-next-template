#!/bin/bash

set -e

echo "🚀 Setting up contained test database..."

# Load test environment variables
if [ -f .env.test ]; then
    export $(grep -v '^#' .env.test | xargs)
else
    echo "❌ .env.test file not found"
    exit 1
fi

if [ -z "$DATABASE_URL" ]; then
    echo "❌ DATABASE_URL not found in .env.test"
    exit 1
fi

# Extract components from DATABASE_URL
DB_HOST=$(echo $DATABASE_URL | sed -n 's/.*@\([^:]*\):.*/\1/p')
DB_PORT=$(echo $DATABASE_URL | sed -n 's/.*:\([0-9]*\)\/.*/\1/p')
DB_USER=$(echo $DATABASE_URL | sed -n 's/.*\/\/\([^:]*\):.*/\1/p')
DB_PASS=$(echo $DATABASE_URL | sed -n 's/.*:\([^@]*\)@.*/\1/p')
ORIGINAL_DB=$(echo $DATABASE_URL | sed -n 's/.*\/\([^?]*\).*/\1/p')

# Create unique test database name
TEST_DB_NAME="${ORIGINAL_DB}"
#_test_$(date +%s)"

echo "Creating isolated test database: $TEST_DB_NAME"

# Drop if exist 
sudo -u postgres psql -c "DROP DATABASE IF EXISTS $TEST_DB_NAME;"

# Create new test database as postgres user
sudo -u postgres psql -c "CREATE DATABASE $TEST_DB_NAME;"

# Grant permissions on the NEW test database
sudo -u postgres psql -d $TEST_DB_NAME -c "
ALTER SCHEMA public OWNER TO $DB_USER;
GRANT ALL ON SCHEMA public TO $DB_USER;
GRANT CREATE ON SCHEMA public TO $DB_USER;
GRANT USAGE ON SCHEMA public TO $DB_USER;
ALTER DEFAULT PRIVILEGES FOR USER $DB_USER IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;
"

# Create new DATABASE_URL for the test database
TEST_DATABASE_URL=$(echo $DATABASE_URL | sed "s|/${ORIGINAL_DB}|/${TEST_DB_NAME}|")

echo "✅ Test database created: $TEST_DB_NAME"
echo "🔗 Test DATABASE_URL: $TEST_DATABASE_URL"

# Verify permissions on the NEW database
psql $TEST_DATABASE_URL -c "
SELECT has_schema_privilege('$DB_USER', 'public', 'CREATE') as can_create;
CREATE TABLE IF NOT EXISTS test_perms_verify (id SERIAL PRIMARY KEY, note TEXT);
INSERT INTO test_perms_verify (note) VALUES ('Contained test database working!');
SELECT * FROM test_perms_verify;
DROP TABLE test_perms_verify;
"

# Write test database info to a file for cleanup
echo $TEST_DB_NAME > /tmp/test_db_name.txt
echo $TEST_DATABASE_URL > /tmp/test_db_url.txt

echo "🎉 Contained test database setup completed!"
echo "📝 Use this in your tests: DATABASE_URL=$TEST_DATABASE_URL"