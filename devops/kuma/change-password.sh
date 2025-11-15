#!/bin/bash

# reset-current-password.sh
# Script to reset or create current password for Uptime Kuma

set -e  # Exit on any error

CURRENT_USER=$USER
echo "=== Uptime Kuma $CURRENT_USER Password Reset ==="

# Read new password securely
read -s -p "Enter new password for $CURRENT_USER user: " NEW_PASSWORD
echo
read -s -p "Confirm new password: " CONFIRM_PASSWORD
echo

# Verify passwords match
if [ "$NEW_PASSWORD" != "$CONFIRM_PASSWORD" ]; then
    echo "Error: Passwords do not match!"
    exit 1
fi

if [ -z "$NEW_PASSWORD" ]; then
    echo "Error: Password cannot be empty!"
    exit 1
fi

echo "Generating password hash..."

# Generate bcrypt hash
HASH=$(docker exec -u root uptime-kuma node -e "const bcrypt = require('bcryptjs'); console.log(bcrypt.hashSync('$NEW_PASSWORD', 12));")

echo "Checking if $CURRENT_USER user exists..."

# Check if current user exists
USER_EXISTS=$(docker exec -u root uptime-kuma sqlite3 /app/data/kuma.db "SELECT COUNT(*) FROM user WHERE username = '$CURRENT_USER';")

if [ "$USER_EXISTS" -eq "1" ]; then
    echo "$CURRENT_USER user found. Updating password..."
    # Update existing current user
    docker exec -u root uptime-kuma sqlite3 /app/data/kuma.db "UPDATE user SET password = '$HASH' WHERE username = '$CURRENT_USER';"
    echo "✓ $CURRENT_USER password updated successfully!"
else
    echo "$CURRENT_USER user not found. Creating new $CURRENT_USER user..."
    # Insert new current user
    docker exec -u root uptime-kuma sqlite3 /app/data/kuma.db "INSERT INTO user (username, password, active) VALUES ('$CURRENT_USER', '$HASH', 1);"
    echo "✓ $CURRENT_USER user created successfully!"
fi

# Verify the operation
echo ""
echo "Verifying users in database:"
docker exec -u root uptime-kuma sqlite3 /app/data/kuma.db "SELECT id, username, active FROM user ORDER BY id;"

echo ""
echo "=== Password reset complete ==="
echo "Username: $CURRENT_USER"
echo "You can now login with the new password."