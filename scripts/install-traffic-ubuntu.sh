#!/bin/bash
# IP Manager - Traffic Monitoring Integration Script
# Run on Ubuntu laptop where IP Manager is installed
# Location: /home/ubuntu/ipmanager

set -e

echo "=========================================="
echo "IP Manager Traffic Monitoring Integration"
echo "=========================================="
echo ""

# Check if running in correct directory
if [ ! -f "docker-compose.yml" ] || [ ! -d "backend" ] || [ ! -d "frontend" ]; then
    echo "ERROR: This script must be run from /home/ubuntu/ipmanager directory"
    echo "Current directory: $(pwd)"
    echo ""
    echo "Usage:"
    echo "  cd /home/ubuntu/ipmanager"
    echo "  sudo ./install-traffic-monitoring.sh"
    exit 1
fi

# Check if running as sudo
if [ "$EUID" -ne 0 ]; then 
    echo "Please run with sudo:"
    echo "  sudo ./install-traffic-monitoring.sh"
    exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "Installation directory: $SCRIPT_DIR"
echo ""

# Create backups
echo "Step 1: Creating backups..."
echo "============================"

BACKUP_DIR="$SCRIPT_DIR/backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

cp backend/main.py "$BACKUP_DIR/main.py.backup"
cp backend/requirements.txt "$BACKUP_DIR/requirements.txt.backup"
cp frontend/src/App.js "$BACKUP_DIR/App.js.backup"
cp frontend/src/App.css "$BACKUP_DIR/App.css.backup"

echo "✓ Backups created in $BACKUP_DIR"
echo ""

# Update backend requirements
echo "Step 2: Updating backend requirements..."
echo "========================================"

if ! grep -q "paramiko" backend/requirements.txt; then
    cat >> backend/requirements.txt << 'EOF'

# Traffic Monitoring Dependencies
paramiko==3.4.0
pyyaml==6.0.1
EOF
    echo "✓ Added paramiko and pyyaml to requirements.txt"
else
    echo "✓ Dependencies already present"
fi

echo ""

# Create scripts directory
echo "Step 3: Creating scripts directory..."
echo "====================================="

mkdir -p scripts

# Create prepare-vm.sh script
cat > scripts/prepare-vm.sh << 'VMSCRIPT'
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
VMSCRIPT

chmod +x scripts/prepare-vm.sh

echo "✓ Created scripts/prepare-vm.sh"
echo ""

# Update backend main.py
echo "Step 4: Updating backend code..."
echo "================================"

# Check if traffic monitoring code already exists
if grep -q "class SSHManager" backend/main.py; then
    echo "✓ Traffic monitoring code already present"
else
    echo "Adding traffic monitoring code to backend/main.py..."
    
    cat >> backend/main.py << 'BACKEND_CODE'

# ============================================================================
# Traffic Monitoring Integration
# ============================================================================

import paramiko
import json
import time
import uuid
from typing import List, Optional, Dict
from datetime import datetime
import yaml
import threading

class TrafficTestRequest(BaseModel):
    source_ip: str
    target_ip: str
    protocol: str = "tcp"
    duration: int = 60
    bandwidth: str = "100M"
    parallel: int = 1
    reverse: bool = False

class TrafficTestResult(BaseModel):
    test_id: str
    status: str
    source_ip: str
    target_ip: str
    protocol: str
    start_time: float
    end_time: Optional[float] = None
    results: Optional[Dict] = None
    error: Optional[str] = None

class SSHManager:
    """Manage SSH connections to VMs"""
    
    def __init__(self, username="ubuntu", password="ubuntu", key_file=None):
        self.username = username
        self.password = password
        self.key_file = key_file
        self.connections = {}
    
    def connect(self, host: str, port: int = 22):
        """Establish SSH connection to host"""
        try:
            client = paramiko.SSHClient()
            client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            
            if self.key_file:
                client.connect(host, port=port, username=self.username, key_filename=self.key_file, timeout=10)
            else:
                client.connect(host, port=port, username=self.username, password=self.password, timeout=10)
            
            self.connections[host] = client
            return client
        except Exception as e:
            print(f"SSH connection failed to {host}: {e}")
            return None
    
    def execute_command(self, host: str, command: str):
        """Execute command on remote host"""
        try:
            client = self.connections.get(host) or self.connect(host)
            if not client:
                return None, f"Failed to connect to {host}"
            
            stdin, stdout, stderr = client.exec_command(command, timeout=300)
            exit_code = stdout.channel.recv_exit_status()
            
            output = stdout.read().decode('utf-8')
            error = stderr.read().decode('utf-8')
            
            return output, error if error else None
        except Exception as e:
            return None, str(e)
    
    def close(self, host: str):
        """Close SSH connection"""
        if host in self.connections:
            self.connections[host].close()
            del self.connections[host]
    
    def close_all(self):
        """Close all SSH connections"""
        for host in list(self.connections.keys()):
            self.close(host)

# Initialize SSH manager
ssh_manager = SSHManager(username="ubuntu", password="ubuntu")

# Store active traffic tests
active_traffic_tests: Dict[str, TrafficTestResult] = {}

@app.post("/api/traffic/start", response_model=TrafficTestResult)
async def start_traffic_test(request: TrafficTestRequest):
    """Start iperf3 traffic test between two VMs"""
    try:
        test_id = str(uuid.uuid4())
        
        # Build iperf3 command
        cmd_parts = [
            "iperf3",
            "-c", request.target_ip,
            "-t", str(request.duration),
            "-J"
        ]
        
        if request.protocol == "udp":
            cmd_parts.append("-u")
        
        if request.bandwidth:
            cmd_parts.extend(["-b", request.bandwidth])
        
        if request.parallel > 1:
            cmd_parts.extend(["-P", str(request.parallel)])
        
        if request.reverse:
            cmd_parts.append("-R")
        
        command = " ".join(cmd_parts)
        
        # Create test record
        test_record = TrafficTestResult(
            test_id=test_id,
            status="running",
            source_ip=request.source_ip,
            target_ip=request.target_ip,
            protocol=request.protocol,
            start_time=time.time()
        )
        
        active_traffic_tests[test_id] = test_record
        
        # Execute test asynchronously
        def run_test():
            try:
                output, error = ssh_manager.execute_command(request.source_ip, command)
                
                if error:
                    test_record.status = "failed"
                    test_record.error = error
                else:
                    test_record.status = "completed"
                    try:
                        test_record.results = json.loads(output)
                    except json.JSONDecodeError:
                        test_record.results = {"raw_output": output}
                
                test_record.end_time = time.time()
                
            except Exception as e:
                test_record.status = "failed"
                test_record.error = str(e)
                test_record.end_time = time.time()
        
        thread = threading.Thread(target=run_test, daemon=True)
        thread.start()
        
        return test_record
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/traffic/status/{test_id}", response_model=TrafficTestResult)
async def get_traffic_test_status(test_id: str):
    """Get status of traffic test"""
    if test_id not in active_traffic_tests:
        raise HTTPException(status_code=404, detail="Test not found")
    
    return active_traffic_tests[test_id]

@app.get("/api/traffic/results/{test_id}")
async def get_traffic_test_results(test_id: str):
    """Get detailed results of completed test"""
    if test_id not in active_traffic_tests:
        raise HTTPException(status_code=404, detail="Test not found")
    
    test = active_traffic_tests[test_id]
    
    if test.status == "running":
        return {"status": "running", "message": "Test is still in progress"}
    
    if test.status == "failed":
        return {"status": "failed", "error": test.error}
    
    results = test.results
    if not results:
        return {"status": "completed", "message": "No results available"}
    
    try:
        summary = {
            "test_id": test_id,
            "source": test.source_ip,
            "target": test.target_ip,
            "protocol": test.protocol,
            "bandwidth_bps": results.get("end", {}).get("sum_received", {}).get("bits_per_second", 0),
            "bandwidth_mbps": round(results.get("end", {}).get("sum_received", {}).get("bits_per_second", 0) / 1000000, 2),
            "bytes_transferred": results.get("end", {}).get("sum_received", {}).get("bytes", 0),
            "retransmits": results.get("end", {}).get("sum_sent", {}).get("retransmits", 0),
            "jitter_ms": results.get("end", {}).get("sum", {}).get("jitter_ms", 0),
            "lost_packets": results.get("end", {}).get("sum", {}).get("lost_packets", 0),
            "packets": results.get("end", {}).get("sum", {}).get("packets", 0),
            "lost_percent": results.get("end", {}).get("sum", {}).get("lost_percent", 0),
            "raw_results": results
        }
        return summary
    except Exception as e:
        return {"status": "completed", "results": results, "parse_error": str(e)}

@app.get("/api/traffic/active")
async def get_active_tests():
    """Get list of all active traffic tests"""
    active = [t for t in active_traffic_tests.values() if t.status == "running"]
    completed = [t for t in active_traffic_tests.values() if t.status == "completed"]
    failed = [t for t in active_traffic_tests.values() if t.status == "failed"]
    
    return {
        "active": active,
        "completed": completed[-10:],
        "failed": failed[-10:],
        "total_active": len(active),
        "total_completed": len(completed),
        "total_failed": len(failed)
    }

@app.post("/api/traffic/vm/check")
async def check_vm_monitoring(request: dict):
    """Check if VM has monitoring tools installed"""
    ip = request.get("ip")
    try:
        output, error = ssh_manager.execute_command(ip, "systemctl is-active node_exporter")
        node_exporter_running = output and output.strip() == "active"
        
        output, error = ssh_manager.execute_command(ip, "systemctl is-active iperf3-server")
        iperf3_running = output and output.strip() == "active"
        
        output, error = ssh_manager.execute_command(ip, "ss -tulpn | grep -E '(9100|5201)'")
        ports_listening = bool(output)
        
        try:
            import requests
            metrics_response = requests.get(f"http://{ip}:9100/metrics", timeout=5)
            metrics_available = metrics_response.status_code == 200
            metrics_count = len(metrics_response.text.split('\n')) if metrics_available else 0
        except:
            metrics_available = False
            metrics_count = 0
        
        return {
            "ip": ip,
            "node_exporter_running": node_exporter_running,
            "iperf3_running": iperf3_running,
            "ports_listening": ports_listening,
            "metrics_available": metrics_available,
            "metrics_count": metrics_count,
            "ready": node_exporter_running and iperf3_running and metrics_available
        }
        
    except Exception as e:
        return {
            "ip": ip,
            "error": str(e),
            "ready": False
        }

BACKEND_CODE

    echo "✓ Added traffic monitoring code to backend/main.py"
fi

echo ""

# Prompt for frontend updates
echo "Step 5: Frontend updates..."
echo "==========================="
echo ""
echo "⚠️  MANUAL STEP REQUIRED:"
echo ""
echo "The frontend (React) code needs to be added manually to:"
echo "  - frontend/src/App.js"
echo "  - frontend/src/App.css"
echo ""
echo "Refer to these files:"
echo "  - frontend-traffic-complete.jsx"
echo "  - traffic-styles.css"
echo ""
echo "Would you like to see the changes needed? (y/n)"
read -p "> " response

if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
    echo ""
    echo "=== Changes needed for App.js ==="
    echo "1. Add state variables (around line 10)"
    echo "2. Add traffic monitoring functions"
    echo "3. Add buttons in detail modal"
    echo "4. Add Traffic Test Modal"
    echo "5. Add Results Modal"
    echo ""
    echo "=== Changes needed for App.css ==="
    echo "1. Add traffic monitoring styles at bottom"
    echo ""
    echo "Press Enter to continue..."
    read
fi

echo ""

# Rebuild backend
echo "Step 6: Rebuilding backend..."
echo "=============================="

echo "Stopping containers..."
docker compose down

echo "Rebuilding backend..."
docker compose build ipam-backend --no-cache

echo "Starting containers..."
docker compose up -d

echo "Waiting for containers to start..."
sleep 10

echo "✓ Backend rebuilt and restarted"
echo ""

# Verify
echo "Step 7: Verification..."
echo "======================="

echo "Checking container status..."
docker compose ps

echo ""
echo "Testing backend health..."
curl -s http://localhost:8000/health || echo "⚠️  Backend not responding yet"

echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "✅ Installed:"
echo "  - Backend dependencies (paramiko, pyyaml)"
echo "  - Traffic monitoring API endpoints"
echo "  - VM preparation script"
echo ""
echo "⚠️  Manual steps remaining:"
echo "  1. Update frontend/src/App.js with traffic UI code"
echo "  2. Update frontend/src/App.css with traffic styles"
echo "  3. Install monitoring stack on Proxmox"
echo ""
echo "Files backed up to:"
echo "  $BACKUP_DIR"
echo ""
echo "VM preparation script:"
echo "  $SCRIPT_DIR/scripts/prepare-vm.sh"
echo ""
echo "Next steps:"
echo "  1. Edit frontend files (App.js, App.css)"
echo "  2. SSH to Proxmox and install monitoring stack"
echo "  3. Run prepare-vm.sh on each test VM"
echo "  4. Start traffic tests!"
echo ""
