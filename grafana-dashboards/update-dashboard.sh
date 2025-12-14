#!/bin/bash

# Update Grafana Dashboard with Improved Y-Axis Labels
# Run this on your Ubuntu server where ipmanager is installed

set -e

echo "🎨 Updating Grafana Dashboard with Descriptive Y-Axis Labels"
echo "============================================================"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
GRAFANA_URL="http://localhost:3001"
GRAFANA_USER="admin"
GRAFANA_PASS="admin"

echo -e "${BLUE}Step 1: Creating improved dashboard JSON...${NC}"

cat > improved-network-dashboard.json << 'DASHBOARD_EOF'
{
  "dashboard": {
    "title": "Network Traffic Monitoring - IP Manager (Enhanced) FM1",
    "tags": ["network", "bandwidth", "ipmanager", "monitoring"],
    "timezone": "browser",
    "editable": true,
    "refresh": "5s",
    "time": {
      "from": "now-15m",
      "to": "now"
    },
    "panels": [
      {
        "id": 1,
        "gridPos": {"h": 10, "w": 12, "x": 0, "y": 0},
        "type": "graph",
        "title": "📤 Network Bandwidth - Transmit (TX)",
        "description": "Outgoing network traffic bandwidth in megabits per second",
        "targets": [
          {
            "expr": "rate(node_network_transmit_bytes_total{device!~\"lo|docker.*|veth.*\"}[1m]) * 8 / 1000000",
            "legendFormat": "{{instance}} - {{device}} TX",
            "refId": "A",
            "intervalFactor": 1
          }
        ],
        "yaxes": [
          {
            "format": "Mbits",
            "label": "Transmit Bandwidth (Mbps)",
            "show": true,
            "min": 0,
            "decimals": 2,
            "logBase": 1
          },
          {
            "format": "short",
            "show": false
          }
        ],
        "xaxis": {
          "mode": "time",
          "show": true
        },
        "lines": true,
        "fill": 2,
        "linewidth": 2,
        "pointradius": 1,
        "points": false,
        "bars": false,
        "stack": false,
        "legend": {
          "show": true,
          "values": true,
          "min": true,
          "max": true,
          "current": true,
          "avg": true,
          "alignAsTable": true,
          "rightSide": false,
          "hideEmpty": false,
          "hideZero": false
        },
        "tooltip": {
          "shared": true,
          "sort": 2,
          "value_type": "individual"
        },
        "nullPointMode": "null",
        "thresholds": [],
        "aliasColors": {},
        "seriesOverrides": []
      },
      {
        "id": 2,
        "gridPos": {"h": 10, "w": 12, "x": 12, "y": 0},
        "type": "graph",
        "title": "📥 Network Bandwidth - Receive (RX)",
        "description": "Incoming network traffic bandwidth in megabits per second",
        "targets": [
          {
            "expr": "rate(node_network_receive_bytes_total{device!~\"lo|docker.*|veth.*\"}[1m]) * 8 / 1000000",
            "legendFormat": "{{instance}} - {{device}} RX",
            "refId": "A",
            "intervalFactor": 1
          }
        ],
        "yaxes": [
          {
            "format": "Mbits",
            "label": "Receive Bandwidth (Mbps)",
            "show": true,
            "min": 0,
            "decimals": 2,
            "logBase": 1
          },
          {
            "format": "short",
            "show": false
          }
        ],
        "xaxis": {
          "mode": "time",
          "show": true
        },
        "lines": true,
        "fill": 2,
        "linewidth": 2,
        "pointradius": 1,
        "points": false,
        "bars": false,
        "stack": false,
        "legend": {
          "show": true,
          "values": true,
          "min": true,
          "max": true,
          "current": true,
          "avg": true,
          "alignAsTable": true,
          "rightSide": false,
          "hideEmpty": false,
          "hideZero": false
        },
        "tooltip": {
          "shared": true,
          "sort": 2,
          "value_type": "individual"
        },
        "nullPointMode": "null",
        "thresholds": [],
        "aliasColors": {},
        "seriesOverrides": []
      },
      {
        "id": 3,
        "gridPos": {"h": 8, "w": 6, "x": 0, "y": 10},
        "type": "stat",
        "title": "📊 Current TX Bandwidth",
        "description": "Current transmit bandwidth",
        "targets": [
          {
            "expr": "rate(node_network_transmit_bytes_total{device!~\"lo|docker.*|veth.*\"}[1m]) * 8 / 1000000",
            "refId": "A"
          }
        ],
        "options": {
          "reduceOptions": {
            "values": false,
            "calcs": ["lastNotNull"],
            "fields": ""
          },
          "orientation": "auto",
          "textMode": "value_and_name",
          "colorMode": "value",
          "graphMode": "area",
          "justifyMode": "auto"
        },
        "fieldConfig": {
          "defaults": {
            "unit": "Mbits",
            "decimals": 2,
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {"value": null, "color": "green"},
                {"value": 100, "color": "yellow"},
                {"value": 500, "color": "orange"},
                {"value": 800, "color": "red"}
              ]
            }
          }
        }
      },
      {
        "id": 4,
        "gridPos": {"h": 8, "w": 6, "x": 6, "y": 10},
        "type": "stat",
        "title": "📊 Current RX Bandwidth",
        "description": "Current receive bandwidth",
        "targets": [
          {
            "expr": "rate(node_network_receive_bytes_total{device!~\"lo|docker.*|veth.*\"}[1m]) * 8 / 1000000",
            "refId": "A"
          }
        ],
        "options": {
          "reduceOptions": {
            "values": false,
            "calcs": ["lastNotNull"],
            "fields": ""
          },
          "orientation": "auto",
          "textMode": "value_and_name",
          "colorMode": "value",
          "graphMode": "area",
          "justifyMode": "auto"
        },
        "fieldConfig": {
          "defaults": {
            "unit": "Mbits",
            "decimals": 2,
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {"value": null, "color": "green"},
                {"value": 100, "color": "yellow"},
                {"value": 500, "color": "orange"},
                {"value": 800, "color": "red"}
              ]
            }
          }
        }
      },
      {
        "id": 5,
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 10},
        "type": "graph",
        "title": "📦 Packet Rate (TX/RX)",
        "description": "Network packet transmission rate",
        "targets": [
          {
            "expr": "rate(node_network_transmit_packets_total{device!~\"lo|docker.*|veth.*\"}[1m])",
            "legendFormat": "{{instance}} - {{device}} TX",
            "refId": "A"
          },
          {
            "expr": "rate(node_network_receive_packets_total{device!~\"lo|docker.*|veth.*\"}[1m])",
            "legendFormat": "{{instance}} - {{device}} RX",
            "refId": "B"
          }
        ],
        "yaxes": [
          {
            "format": "pps",
            "label": "Packets per Second",
            "show": true,
            "min": 0,
            "decimals": 0,
            "logBase": 1
          },
          {
            "format": "short",
            "show": false
          }
        ],
        "xaxis": {
          "mode": "time",
          "show": true
        },
        "lines": true,
        "linewidth": 2,
        "fill": 1,
        "legend": {
          "show": true,
          "values": true,
          "current": true,
          "avg": true,
          "max": true
        },
        "tooltip": {
          "shared": true,
          "sort": 2
        }
      },
      {
        "id": 6,
        "gridPos": {"h": 7, "w": 12, "x": 0, "y": 18},
        "type": "graph",
        "title": "⚠️ Network Errors & Drops",
        "description": "Network transmission errors and dropped packets",
        "targets": [
          {
            "expr": "rate(node_network_transmit_errs_total{device!~\"lo|docker.*|veth.*\"}[1m])",
            "legendFormat": "{{instance}} - {{device}} TX Errors",
            "refId": "A"
          },
          {
            "expr": "rate(node_network_receive_errs_total{device!~\"lo|docker.*|veth.*\"}[1m])",
            "legendFormat": "{{instance}} - {{device}} RX Errors",
            "refId": "B"
          },
          {
            "expr": "rate(node_network_transmit_drop_total{device!~\"lo|docker.*|veth.*\"}[1m])",
            "legendFormat": "{{instance}} - {{device}} TX Drops",
            "refId": "C"
          },
          {
            "expr": "rate(node_network_receive_drop_total{device!~\"lo|docker.*|veth.*\"}[1m])",
            "legendFormat": "{{instance}} - {{device}} RX Drops",
            "refId": "D"
          }
        ],
        "yaxes": [
          {
            "format": "pps",
            "label": "Errors/Drops per Second",
            "show": true,
            "min": 0,
            "decimals": 0
          },
          {
            "format": "short",
            "show": false
          }
        ],
        "xaxis": {
          "mode": "time",
          "show": true
        },
        "lines": true,
        "linewidth": 2,
        "alert": {
          "conditions": [
            {
              "evaluator": {
                "params": [1],
                "type": "gt"
              },
              "operator": {
                "type": "and"
              },
              "query": {
                "params": ["A", "5m", "now"]
              },
              "reducer": {
                "params": [],
                "type": "avg"
              },
              "type": "query"
            }
          ],
          "executionErrorState": "alerting",
          "frequency": "1m",
          "handler": 1,
          "name": "Network Errors Alert",
          "noDataState": "no_data",
          "notifications": []
        }
      },
      {
        "id": 7,
        "gridPos": {"h": 7, "w": 12, "x": 12, "y": 18},
        "type": "graph",
        "title": "💾 Total Data Transferred",
        "description": "Cumulative data transferred over time",
        "targets": [
          {
            "expr": "node_network_transmit_bytes_total{device!~\"lo|docker.*|veth.*\"} / 1073741824",
            "legendFormat": "{{instance}} - {{device}} TX (GB)",
            "refId": "A"
          },
          {
            "expr": "node_network_receive_bytes_total{device!~\"lo|docker.*|veth.*\"} / 1073741824",
            "legendFormat": "{{instance}} - {{device}} RX (GB)",
            "refId": "B"
          }
        ],
        "yaxes": [
          {
            "format": "decgbytes",
            "label": "Total Data (Gigabytes)",
            "show": true,
            "min": 0,
            "decimals": 2
          },
          {
            "format": "short",
            "show": false
          }
        ],
        "xaxis": {
          "mode": "time",
          "show": true
        },
        "lines": true,
        "linewidth": 2,
        "fill": 0,
        "legend": {
          "show": true,
          "values": true,
          "current": true
        }
      }
    ]
  },
  "overwrite": true
}
DASHBOARD_EOF

echo -e "${GREEN}✓ Dashboard JSON created${NC}"

echo -e "${BLUE}Step 2: Importing dashboard to Grafana...${NC}"

RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
  -d @improved-network-dashboard.json \
  "${GRAFANA_URL}/api/dashboards/db")

if echo "$RESPONSE" | grep -q '"status":"success"'; then
    echo -e "${GREEN}✓ Dashboard imported successfully!${NC}"
    
    DASHBOARD_UID=$(echo "$RESPONSE" | grep -o '"uid":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    echo ""
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}✓ Dashboard Updated Successfully!${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo ""
    echo -e "${BLUE}Key Improvements:${NC}"
    echo -e "  📊 Y-Axis Labels:"
    echo -e "     • TX: 'Transmit Bandwidth (Mbps)'"
    echo -e "     • RX: 'Receive Bandwidth (Mbps)'"
    echo -e "     • Packets: 'Packets per Second'"
    echo -e "     • Errors: 'Errors/Drops per Second'"
    echo ""
    echo -e "  🎨 Visual Enhancements:"
    echo -e "     • Descriptive panel titles with emojis"
    echo -e "     • Panel descriptions for context"
    echo -e "     • Legend shows min/max/avg/current"
    echo -e "     • Color thresholds for stat panels"
    echo ""
    echo -e "  📈 New Panels Added:"
    echo -e "     • Current bandwidth stat panels"
    echo -e "     • Combined packet rate graph"
    echo -e "     • Network errors & drops monitoring"
    echo -e "     • Total data transferred counter"
    echo ""
    echo -e "${YELLOW}Access your dashboard:${NC}"
    echo -e "  ${GRAFANA_URL}/d/${DASHBOARD_UID}"
    echo ""
    echo -e "${YELLOW}Or browse to:${NC}"
    echo -e "  ${GRAFANA_URL} → Dashboards → 'Network Traffic Monitoring - IP Manager (Enhanced)'"
    echo ""
else
    echo -e "${YELLOW}⚠ Response:${NC} $RESPONSE"
    echo ""
    echo -e "${YELLOW}Troubleshooting:${NC}"
    echo "1. Check if Grafana is running:"
    echo "   docker ps | grep grafana"
    echo ""
    echo "2. Verify Grafana URL:"
    echo "   curl ${GRAFANA_URL}/api/health"
    echo ""
    echo "3. Check credentials (default is admin/admin)"
fi

echo ""
echo -e "${BLUE}Cleanup...${NC}"
rm -f improved-network-dashboard.json
echo -e "${GREEN}✓ Done!${NC}"
