#!/bin/bash
# VM Preparation Script - Install iperf3 and node_exporter
# Run this on each Ubuntu VM that will be monitored

set -e

echo "=========================================="
echo "VM Monitoring Tools Installation"
echo "=========================================="
echo ""

if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root:"
    echo "  sudo ./prepare-vm.sh"
    exit 1
fi

VM_IP=$(hostname -I | awk '{print $1}')
echo "VM IP Address: $VM_IP"
echo ""

echo "Step 1: Updating system..."
apt update
apt upgrade -y

echo ""
echo "Step 2: Installing dependencies..."
apt install -y wget curl iperf3 net-tools

echo ""
echo "Step 3: Installing node_exporter..."

NODE_EXPORTER_VERSION="1.7.0"
cd /tmp

wget -q https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
tar xvfz node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
cp node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
chown root:root /usr/local/bin/node_exporter
rm -rf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64*

cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
Documentation=https://github.com/prometheus/node_exporter
After=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/node_exporter \
    --web.listen-address=:9100 \
    --collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/) \
    --collector.netclass.ignored-devices=^(veth.*|docker.*|br-.*)$ \
    --collector.netdev.device-exclude=^(veth.*|docker.*|br-.*)$

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter

echo "✓ node_exporter installed and started on port 9100"

echo ""
echo "Step 4: Configuring iperf3 server..."

cat > /etc/systemd/system/iperf3-server.service << 'EOF'
[Unit]
Description=iperf3 Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/iperf3 -s
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable iperf3-server
systemctl start iperf3-server

echo "✓ iperf3 server installed and started on port 5201"

echo ""
echo "Step 5: Configuring firewall..."

if systemctl is-active --quiet ufw; then
    ufw allow 9100/tcp comment 'Node Exporter'
    ufw allow 5201/tcp comment 'iperf3 TCP'
    ufw allow 5201/udp comment 'iperf3 UDP'
    echo "✓ Firewall rules added"
else
    echo "UFW not active, skipping"
fi

echo ""
echo "Step 6: Creating test scripts..."

cat > /usr/local/bin/test-monitoring << 'EOF'
#!/bin/bash
echo "Testing Node Exporter..."
curl -s http://localhost:9100/metrics | head -n 5
if [ $? -eq 0 ]; then
    echo "✓ Node Exporter responding"
else
    echo "✗ Node Exporter not responding"
fi

echo ""
echo "Testing iperf3 server..."
ss -tulpn | grep :5201
if [ $? -eq 0 ]; then
    echo "✓ iperf3 server listening"
else
    echo "✗ iperf3 server not listening"
fi

echo ""
echo "System Info:"
echo "  IP: $(hostname -I | awk '{print $1}')"
echo "  Hostname: $(hostname)"
echo "  Uptime: $(uptime -p)"
EOF

chmod +x /usr/local/bin/test-monitoring

cat > /usr/local/bin/traffic-test << 'EOF'
#!/bin/bash
if [ -z "$1" ]; then
    echo "Usage: traffic-test <target-ip> [tcp|udp] [duration]"
    echo "Example: traffic-test 192.168.0.51 tcp 30"
    exit 1
fi

TARGET=$1
PROTOCOL=${2:-tcp}
DURATION=${3:-10}

echo "Starting traffic test..."
echo "Target: $TARGET"
echo "Protocol: $PROTOCOL"
echo "Duration: ${DURATION}s"
echo ""

if [ "$PROTOCOL" = "udp" ]; then
    iperf3 -c $TARGET -u -t $DURATION -b 100M
else
    iperf3 -c $TARGET -t $DURATION
fi
EOF

chmod +x /usr/local/bin/traffic-test

echo "✓ Test scripts created"

echo ""
echo "Step 7: Verifying installation..."

if systemctl is-active --quiet node_exporter; then
    echo "✓ node_exporter is running"
    NODE_METRICS=$(curl -s http://localhost:9100/metrics | wc -l)
    echo "  Metrics available: $NODE_METRICS"
else
    echo "✗ node_exporter is not running"
fi

if systemctl is-active --quiet iperf3-server; then
    echo "✓ iperf3 server is running"
else
    echo "✗ iperf3 server is not running"
fi

echo ""
echo "Network Configuration:"
echo "  IP Address: $VM_IP"
echo "  Listening ports:"
ss -tulpn | grep -E '(9100|5201)'

echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "Services installed:"
echo "  ✓ node_exporter  - Port 9100 (metrics)"
echo "  ✓ iperf3 server  - Port 5201 (traffic)"
echo ""
echo "Test commands:"
echo "  test-monitoring           - Test all services"
echo "  traffic-test <target-ip>  - Run traffic test"
echo ""
echo "View metrics:"
echo "  curl http://$VM_IP:9100/metrics"
echo ""
