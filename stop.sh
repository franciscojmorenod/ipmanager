#!/bin/bash
# Stop IP Manager
# Run with: bash stop.sh

echo "Stopping IP Manager..."
docker compose stop

echo "✓ IP Manager stopped"
echo ""
echo "To start again: bash start.sh"
