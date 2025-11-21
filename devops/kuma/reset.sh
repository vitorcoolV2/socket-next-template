# Stop and remove the kuma container
docker compose down uptime-kuma

# Remove the data volume to reset everything
sudo rm -rf ./uptime-kuma-data

# Recreate the directory with proper permissions
mkdir -p ./uptime-kuma-data

# Start fresh
docker compose up uptime-kuma -d