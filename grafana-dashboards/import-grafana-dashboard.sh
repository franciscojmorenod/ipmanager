#!/bin/bash

DASHBOARD_JSON='{
  "dashboard": {
    "title": "Network Traffic Monitoring",
    "tags": ["network", "iperf3", "traffic"],
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
        "type": "graph",
        "title": "Network Bandwidth (TX)",
        "targets": [
          {
            "expr": "rate(node_network_transmit_bytes_total{device!~\"lo|docker.*|veth.*\"}[1m]) * 8 / 1000000",
            "legendFormat": "{{instance}} - {{device}} TX",
            "refId": "A"
          }
        ],
        "yaxes": [
          {"format": "Mbits", "label": "Bandwidth (Mbps)"},
          {"format": "short"}
        ],
        "xaxis": {"mode": "time"},
        "lines": true,
        "fill": 2,
        "linewidth": 2,
        "legend": {"show": true, "values": true, "current": true, "max": true, "avg": true}
      },
      {
        "id": 2,
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
        "type": "graph",
        "title": "Network Bandwidth (RX)",
        "targets": [
          {
            "expr": "rate(node_network_receive_bytes_total{device!~\"lo|docker.*|veth.*\"}[1m]) * 8 / 1000000",
            "legendFormat": "{{instance}} - {{device}} RX",
            "refId": "A"
          }
        ],
        "yaxes": [
          {"format": "Mbits", "label": "Bandwidth (Mbps)"},
          {"format": "short"}
        ],
        "xaxis": {"mode": "time"},
        "lines": true,
        "fill": 2,
        "linewidth": 2,
        "legend": {"show": true, "values": true, "current": true, "max": true, "avg": true}
      }
    ],
    "refresh": "5s",
    "time": {"from": "now-15m", "to": "now"}
  },
  "overwrite": true
}'

echo "Importing dashboard to Grafana..."
curl -X POST \
  -H "Content-Type: application/json" \
  -u "admin:admin" \
  -d "$DASHBOARD_JSON" \
  http://localhost:3001/api/dashboards/db

echo ""
echo "✓ Dashboard imported!"
echo "📈 Open: http://localhost:3001"
