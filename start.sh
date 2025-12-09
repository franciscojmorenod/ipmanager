#!/bin/bash
# Start IP Manager
# Run with: bash start.sh

set -e

echo "================================================"
echo "Starting IP Manager"
echo "================================================"
echo ""

# Check if Docker is running
if ! systemctl is-active --quiet docker; then
    echo "Starting Docker service..."
    sudo systemctl start docker
fi

# Pull latest images
echo "Pulling Docker images..."
docker compose pull

# Start services
echo "Starting services..."
docker compose up -d

echo ""
echo "Waiting for services to start..."
sleep 10

# Get IP address
IP_ADDR=$(hostname -I | awk '{print $1}')

echo ""
echo "================================================"
echo "✓ IP Manager Started Successfully!"
echo "================================================"
echo ""
echo "Access URLs:"
echo "  Frontend: http://$IP_ADDR:3000"
echo "  Backend:  http://$IP_ADDR:8000"
echo "  API Docs: http://$IP_ADDR:8000/docs"
echo ""
echo "From Windows, open: http://$IP_ADDR:3000"
echo ""
echo "Useful commands:"
echo "  View logs:    docker compose logs -f"
echo "  Stop:         bash stop.sh"
echo "  Restart:      docker compose restart"
echo "================================================"
