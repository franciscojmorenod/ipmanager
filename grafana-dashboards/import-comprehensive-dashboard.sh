#!/bin/bash

DASHBOARD_JSON='{
  "dashboard": {
    "title": "Network Traffic Monitoring - IP Manager",
    "tags": ["network", "iperf3", "traffic", "ipmanager"],
    "timezone": "browser",
    "editable": true,
    "panels": [
      {
        "id": 1,
        "gridPos": {"h": 9, "w": 12, "x": 0, "y": 0},
        "type": "graph",
        "title": "📤 Network Bandwidth - Transmit (TX)",
        "targets": [
          {
            "expr": "rate(node_network_transmit_bytes_total{device=\"eth0\"}[30s]) * 8 / 1000000",
            "legendFormat": "{{instance}} TX",
            "refId": "A"
          }
        ],
        "yaxes": [
          {
            "format": "Mbits",
            "label": "Bandwidth (Mbps)",
            "min": 0
          },
          {"format": "short"}
        ],
        "xaxis": {"mode": "time", "show": true},
        "lines": true,
        "fill": 2,
        "linewidth": 3,
        "pointradius": 2,
        "points": false,
        "bars": false,
        "stack": false,
        "percentage": false,
        "legend": {
          "show": true,
          "values": true,
          "min": true,
          "max": true,
          "current": true,
          "total": false,
          "avg": true,
          "alignAsTable": true,
          "rightSide": false
        },
        "nullPointMode": "null",
        "tooltip": {
          "shared": true,
          "sort": 2,
          "value_type": "individual"
        },
        "aliasColors": {}
      },
      {
        "id": 2,
        "gridPos": {"h": 9, "w": 12, "x": 12, "y": 0},
        "type": "graph",
        "title": "📥 Network Bandwidth - Receive (RX)",
        "targets": [
          {
            "expr": "rate(node_network_receive_bytes_total{device=\"eth0\"}[30s]) * 8 / 1000000",
            "legendFormat": "{{instance}} RX",
            "refId": "A"
          }
        ],
        "yaxes": [
          {
            "format": "Mbits",
            "label": "Bandwidth (Mbps)",
            "min": 0
          },
          {"format": "short"}
        ],
        "xaxis": {"mode": "time", "show": true},
        "lines": true,
        "fill": 2,
        "linewidth": 3,
        "pointradius": 2,
        "points": false,
        "bars": false,
        "stack": false,
        "legend": {
          "show": true,
          "values": true,
          "min": true,
          "max": true,
          "current": true,
          "total": false,
          "avg": true,
          "alignAsTable": true,
          "rightSide": false
        },
        "nullPointMode": "null",
        "tooltip": {
          "shared": true,
          "sort": 2,
          "value_type": "individual"
        }
      },
      {
        "id": 3,
        "gridPos": {"h": 8, "w": 8, "x": 0, "y": 9},
        "type": "stat",
        "title": "🚀 Current TX Bandwidth",
        "targets": [
          {
            "expr": "rate(node_network_transmit_bytes_total{device=\"eth0\"}[30s]) * 8 / 1000000",
            "refId": "A"
          }
        ],
        "options": {
          "graphMode": "area",
          "colorMode": "value",
          "justifyMode": "auto",
          "orientation": "auto",
          "reduceOptions": {
            "values": false,
            "calcs": ["lastNotNull"]
          },
          "textMode": "value_and_name"
        },
        "fieldConfig": {
          "defaults": {
            "unit": "Mbits",
            "decimals": 2,
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {"value": 0, "color": "green"},
                {"value": 50, "color": "yellow"},
                {"value": 100, "color": "orange"},
                {"value": 500, "color": "red"}
              ]
            },
            "mappings": []
          }
        }
      },
      {
        "id": 4,
        "gridPos": {"h": 8, "w": 8, "x": 8, "y": 9},
        "type": "stat",
        "title": "📡 Current RX Bandwidth",
        "targets": [
          {
            "expr": "rate(node_network_receive_bytes_total{device=\"eth0\"}[30s]) * 8 / 1000000",
            "refId": "A"
          }
        ],
        "options": {
          "graphMode": "area",
          "colorMode": "value",
          "justifyMode": "auto",
          "orientation": "auto",
          "reduceOptions": {
            "values": false,
            "calcs": ["lastNotNull"]
          },
          "textMode": "value_and_name"
        },
        "fieldConfig": {
          "defaults": {
            "unit": "Mbits",
            "decimals": 2,
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {"value": 0, "color": "green"},
                {"value": 50, "color": "yellow"},
                {"value": 100, "color": "orange"},
                {"value": 500, "color": "red"}
              ]
            }
          }
        }
      },
      {
        "id": 5,
        "gridPos": {"h": 8, "w": 8, "x": 16, "y": 9},
        "type": "stat",
        "title": "💾 Total Data Transferred",
        "targets": [
          {
            "expr": "sum(increase(node_network_transmit_bytes_total{device=\"eth0\"}[5m])) + sum(increase(node_network_receive_bytes_total{device=\"eth0\"}[5m]))",
            "refId": "A"
          }
        ],
        "options": {
          "graphMode": "none",
          "colorMode": "value",
          "justifyMode": "auto",
          "orientation": "auto",
          "reduceOptions": {
            "values": false,
            "calcs": ["lastNotNull"]
          },
          "textMode": "value_and_name"
        },
        "fieldConfig": {
          "defaults": {
            "unit": "bytes",
            "decimals": 2,
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {"value": 0, "color": "blue"}
              ]
            }
          }
        }
      },
      {
        "id": 6,
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 17},
        "type": "graph",
        "title": "📦 Network Packets - TX",
        "targets": [
          {
            "expr": "rate(node_network_transmit_packets_total{device=\"eth0\"}[30s])",
            "legendFormat": "{{instance}} TX packets/s",
            "refId": "A"
          }
        ],
        "yaxes": [
          {
            "format": "pps",
            "label": "Packets/sec",
            "min": 0
          },
          {"format": "short"}
        ],
        "xaxis": {"mode": "time"},
        "lines": true,
        "fill": 1,
        "linewidth": 2,
        "legend": {
          "show": true,
          "values": true,
          "current": true,
          "max": true,
          "avg": true
        }
      },
      {
        "id": 7,
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 17},
        "type": "graph",
        "title": "📦 Network Packets - RX",
        "targets": [
          {
            "expr": "rate(node_network_receive_packets_total{device=\"eth0\"}[30s])",
            "legendFormat": "{{instance}} RX packets/s",
            "refId": "A"
          }
        ],
        "yaxes": [
          {
            "format": "pps",
            "label": "Packets/sec",
            "min": 0
          },
          {"format": "short"}
        ],
        "xaxis": {"mode": "time"},
        "lines": true,
        "fill": 1,
        "linewidth": 2,
        "legend": {
          "show": true,
          "values": true,
          "current": true,
          "max": true,
          "avg": true
        }
      },
      {
        "id": 8,
        "gridPos": {"h": 7, "w": 24, "x": 0, "y": 25},
        "type": "graph",
        "title": "⚠️ Network Errors & Drops",
        "targets": [
          {
            "expr": "rate(node_network_transmit_errs_total{device=\"eth0\"}[1m])",
            "legendFormat": "{{instance}} TX errors",
            "refId": "A"
          },
          {
            "expr": "rate(node_network_receive_errs_total{device=\"eth0\"}[1m])",
            "legendFormat": "{{instance}} RX errors",
            "refId": "B"
          },
          {
            "expr": "rate(node_network_transmit_drop_total{device=\"eth0\"}[1m])",
            "legendFormat": "{{instance}} TX drops",
            "refId": "C"
          },
          {
            "expr": "rate(node_network_receive_drop_total{device=\"eth0\"}[1m])",
            "legendFormat": "{{instance}} RX drops",
            "refId": "D"
          }
        ],
        "yaxes": [
          {
            "format": "short",
            "label": "Errors/Drops per sec",
            "min": 0
          }
        ],
        "lines": true,
        "fill": 0,
        "linewidth": 2,
        "legend": {
          "show": true,
          "values": true,
          "current": true,
          "max": true
        }
      }
    ],
    "schemaVersion": 38,
    "version": 0,
    "refresh": "5s",
    "time": {
      "from": "now-5m",
      "to": "now"
    },
    "timepicker": {
      "refresh_intervals": ["5s", "10s", "30s", "1m", "5m", "15m"],
      "time_options": ["5m", "15m", "1h", "6h", "12h", "24h"]
    }
  },
  "overwrite": true
}'

echo "📊 Importing comprehensive dashboard to Grafana..."
curl -X POST \
  -H "Content-Type: application/json" \
  -u "admin:admin" \
  -d "$DASHBOARD_JSON" \
  http://localhost:3001/api/dashboards/db

echo ""
echo "✅ Dashboard imported successfully!"
echo "📈 Open: http://localhost:3001"
echo ""
echo "Dashboard includes:"
echo "  • TX/RX Bandwidth graphs with legends"
echo "  • Current bandwidth stat panels"
echo "  • Total data transferred counter"
echo "  • Packet rate graphs"
echo "  • Error & drop monitoring"
echo ""
echo "🧪 Test it: ssh ubuntu@192.168.0.33 'iperf3 -c 192.168.0.32 -t 60 -b 100M'"
