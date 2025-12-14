#!/bin/bash
# Import Grafana Dashboard for Network Traffic Monitoring

GRAFANA_URL="http://localhost:3001"
GRAFANA_USER="admin"
GRAFANA_PASS="admin"

echo "📊 Importing Network Traffic Dashboard to Grafana..."

curl -X POST \
  -H "Content-Type: application/json" \
  -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
  -d @network-traffic-dashboard.json \
  "${GRAFANA_URL}/api/dashboards/db"

if [ $? -eq 0 ]; then
  echo ""
  echo "✓ Dashboard imported successfully!"
  echo ""
  echo "📈 View it at: http://192.168.0.100:3001/d/network-traffic"
  echo ""
  echo "Default credentials:"
  echo "  Username: admin"
  echo "  Password: admin"
else
  echo ""
  echo "✗ Failed to import dashboard"
  echo "Make sure Grafana is running: docker compose ps"
fi
