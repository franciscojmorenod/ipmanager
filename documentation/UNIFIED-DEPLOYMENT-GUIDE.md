# Unified Deployment Guide - All 7 Containers on Ubuntu Server

**Target Server:** Ubuntu Server at 192.168.0.199  
**Proxmox Server:** 192.168.0.100 (separate - only for VM creation)

---

## 📦 What Runs Where

### Ubuntu Server (192.168.0.199) - ALL Docker Containers:
1. **ipam-mysql** - MySQL database (port 3306)
2. **ipam-backend** - FastAPI backend (port 8000)
3. **ipam-frontend** - React frontend (port 3000)
4. **phpmyadmin** - Database UI (port 8080)
5. **prometheus** - Metrics collection (port 9090)
6. **grafana** - Dashboards (port 3001)
7. **alertmanager** - Alerts (port 9093)

### Proxmox Server (192.168.0.100) - No Docker:
- Just the Proxmox hypervisor
- IP Manager connects via API to create VMs
- No containers run here

---

## 🚀 Quick Start Installation

### Step 1: Prepare Ubuntu Server (192.168.0.199)

```bash
# SSH to Ubuntu server
ssh ubuntu@192.168.0.199

# Navigate to project
cd /home/ubuntu/ipmanager

# Backup existing docker-compose
cp docker-compose.yml docker-compose.yml.backup

# Download unified version
# (copy docker-compose-unified.yml to this location)
cp docker-compose-unified.yml docker-compose.yml
```

### Step 2: Create Monitoring Directory Structure

```bash
# Still on Ubuntu server (192.168.0.199)
cd /home/ubuntu/ipmanager

# Create monitoring directories
mkdir -p monitoring/{prometheus/targets,grafana/{provisioning,dashboards},alertmanager}
```

### Step 3: Create Prometheus Configuration

```bash
cat > monitoring/prometheus/prometheus.yml << 'YAML'
global:
  scrape_interval: 5s
  evaluation_interval: 5s

scrape_configs:
  # Prometheus itself
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Node exporters on VMs
  - job_name: 'node_exporter'
    file_sd_configs:
      - files:
          - '/etc/prometheus/targets/nodes.yml'
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance

  # iperf3 servers
  - job_name: 'iperf3'
    file_sd_configs:
      - files:
          - '/etc/prometheus/targets/iperf.yml'
YAML
```

### Step 4: Create Prometheus Targets

```bash
# Node exporter targets (VMs with monitoring tools)
cat > monitoring/prometheus/targets/nodes.yml << 'YAML'
- targets:
    - '192.168.0.32:9100'
    - '192.168.0.33:9100'
  labels:
    job: 'node_exporter'
    environment: 'production'
YAML

# iperf3 targets
cat > monitoring/prometheus/targets/iperf.yml << 'YAML'
- targets:
    - '192.168.0.32:5201'
    - '192.168.0.33:5201'
  labels:
    job: 'iperf3'
    environment: 'production'
YAML
```

### Step 5: Create Grafana Provisioning

```bash
# Datasource configuration
mkdir -p monitoring/grafana/provisioning/datasources
cat > monitoring/grafana/provisioning/datasources/prometheus.yml << 'YAML'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
YAML

# Dashboard configuration
mkdir -p monitoring/grafana/provisioning/dashboards
cat > monitoring/grafana/provisioning/dashboards/dashboards.yml << 'YAML'
apiVersion: 1

providers:
  - name: 'Default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
YAML
```

### Step 6: Create Alertmanager Configuration

```bash
cat > monitoring/alertmanager/config.yml << 'YAML'
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'web.hook'

receivers:
  - name: 'web.hook'
    webhook_configs:
      - url: 'http://127.0.0.1:5001/'

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'dev', 'instance']
YAML
```

### Step 7: Stop Existing Containers

```bash
# Stop any running containers
docker compose down

# Verify all stopped
docker ps
```

### Step 8: Start All 7 Containers

```bash
# Start everything with new unified compose file
docker compose up -d

# Watch logs
docker compose logs -f

# Check all containers are running
docker compose ps
```

### Step 9: Verify Services

```bash
# Check each service is accessible
curl http://localhost:3000  # Frontend
curl http://localhost:8000/docs  # Backend API
curl http://localhost:8080  # phpMyAdmin
curl http://localhost:9090  # Prometheus
curl http://localhost:3001  # Grafana
curl http://localhost:9093  # Alertmanager

# Check MySQL
docker exec -it ipam-mysql mysql -u ipmanager -pipmanager_pass_2024 -e "SHOW DATABASES;"
```

---

## 🌐 Access URLs (from any computer on network)

All services now accessible at **192.168.0.199**:

- **IP Manager Frontend:** http://192.168.0.199:3000
- **Backend API Docs:** http://192.168.0.199:8000/docs
- **phpMyAdmin:** http://192.168.0.199:8080
- **Prometheus:** http://192.168.0.199:9090
- **Grafana:** http://192.168.0.199:3001 (admin/admin)
- **Alertmanager:** http://192.168.0.199:9093

---

## 🔧 Update Backend to Use Correct IPs

Since everything now runs on **192.168.0.199**, update frontend to point to correct backend:

```bash
# Edit frontend environment or hardcoded URLs
cd /home/ubuntu/ipmanager/frontend/src

# If using environment variables
echo "REACT_APP_API_URL=http://192.168.0.199:8000" > .env

# Or search and replace in code if hardcoded
sed -i 's|localhost:8000|192.168.0.199:8000|g' App.js
```

**Update Grafana/Prometheus links in frontend:**

```javascript
// In App.js
const openGrafana = () => {
  window.open('http://192.168.0.199:3001', '_blank');
};

const openPrometheus = () => {
  window.open('http://192.168.0.199:9090', '_blank');
};
```

---

## 📊 Verify Monitoring Stack

### Check Prometheus Targets

1. Open: http://192.168.0.199:9090/targets
2. Should see:
   - prometheus (1/1 up)
   - node_exporter (2/2 up) - if VMs are prepared
   - iperf3 (2/2 up) - if VMs are prepared

### Check Grafana

1. Open: http://192.168.0.199:3001
2. Login: admin / admin
3. Go to Connections → Data sources
4. Verify Prometheus is connected
5. Test & Save

---

## 🖥️ Prepare VMs for Monitoring

On each VM you want to monitor (e.g., 192.168.0.32, 192.168.0.33):

```bash
# Install node_exporter
wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar xvfz node_exporter-1.7.0.linux-amd64.tar.gz
sudo cp node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
sudo chmod +x /usr/local/bin/node_exporter

# Create systemd service
sudo tee /etc/systemd/system/node_exporter.service << 'SERVICE'
[Unit]
Description=Node Exporter
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE

# Install iperf3
sudo apt update
sudo apt install -y iperf3

# Create iperf3 service
sudo tee /etc/systemd/system/iperf3-server.service << 'SERVICE'
[Unit]
Description=iperf3 server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/iperf3 -s
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE

# Enable password auth for SSH (needed for traffic tests)
sudo sed -i 's/#PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo rm -f /etc/ssh/sshd_config.d/*.conf

# Start services
sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
sudo systemctl enable --now iperf3-server
sudo systemctl restart sshd

# Verify
systemctl status node_exporter
systemctl status iperf3-server
ss -tulpn | grep -E '(9100|5201)'
```

---

## 🔄 Managing the Stack

### View All Container Status

```bash
docker compose ps
```

### View Logs

```bash
# All containers
docker compose logs -f

# Specific container
docker compose logs -f backend
docker compose logs -f prometheus
docker compose logs -f grafana
```

### Restart Services

```bash
# Restart all
docker compose restart

# Restart specific service
docker compose restart backend
docker compose restart prometheus
```

### Stop All

```bash
docker compose down
```

### Start All

```bash
docker compose up -d
```

### Update a Container

```bash
# Rebuild and restart specific service
docker compose up -d --build backend

# Restart specific service
docker compose restart frontend
```

---

## 📈 Test Traffic Monitoring

1. **Open IP Manager:** http://192.168.0.199:3000
2. **Scan Network** to find active VMs
3. **Click on VM** (e.g., 192.168.0.32)
4. **Click "Traffic Test"**
5. **Select target:** 192.168.0.33
6. **Configure:** TCP, 60s, 100M
7. **Click "Start Test"**
8. **Click "Open Grafana"** - http://192.168.0.199:3001
9. **Watch live graphs** during test
10. **View results** when complete

---

## 🗂️ Directory Structure

```
/home/ubuntu/ipmanager/
├── docker-compose.yml (UNIFIED - all 7 containers)
├── backend/
│   ├── main.py
│   ├── Dockerfile
│   └── requirements.txt
├── frontend/
│   ├── src/
│   │   ├── App.js
│   │   └── App.css
│   ├── package.json
│   └── Dockerfile
├── mysql/
│   └── init.sql
├── monitoring/
│   ├── prometheus/
│   │   ├── prometheus.yml
│   │   └── targets/
│   │       ├── nodes.yml
│   │       └── iperf.yml
│   ├── grafana/
│   │   ├── provisioning/
│   │   │   ├── datasources/
│   │   │   │   └── prometheus.yml
│   │   │   └── dashboards/
│   │   │       └── dashboards.yml
│   │   └── dashboards/
│   └── alertmanager/
│       └── config.yml
└── .env (optional - Proxmox credentials)
```

---

## 🔒 Security Notes

- **Firewall:** Only allow access from 192.168.0.x network
- **Passwords:** Change default passwords in production
- **SSH:** VMs need password auth enabled for traffic tests
- **Proxmox:** Store credentials in .env file (not in docker-compose.yml)

---

## 🐛 Troubleshooting

### Container won't start

```bash
# Check logs
docker compose logs <container-name>

# Check if port is already in use
sudo netstat -tulpn | grep <port>

# Restart specific container
docker compose restart <container-name>
```

### Prometheus can't reach VMs

```bash
# Check Prometheus targets
curl http://192.168.0.199:9090/api/v1/targets | jq

# Test from Ubuntu server
curl http://192.168.0.32:9100/metrics
curl http://192.168.0.33:9100/metrics

# Check VM services
ssh ubuntu@192.168.0.32 "systemctl status node_exporter"
```

### Traffic test fails

```bash
# Check backend can SSH to VMs
docker exec -it ipam-backend ssh ubuntu@192.168.0.32

# Verify iperf3 running
ssh ubuntu@192.168.0.32 "systemctl status iperf3-server"

# Check backend logs
docker compose logs backend | grep -i traffic
```

---

## ✅ Final Checklist

- [ ] All 7 containers running: `docker compose ps`
- [ ] Frontend accessible: http://192.168.0.199:3000
- [ ] Backend API accessible: http://192.168.0.199:8000/docs
- [ ] Prometheus targets UP: http://192.168.0.199:9090/targets
- [ ] Grafana accessible: http://192.168.0.199:3001
- [ ] VMs have node_exporter running (port 9100)
- [ ] VMs have iperf3 running (port 5201)
- [ ] Traffic test works end-to-end
- [ ] Grafana shows live metrics during test

---

**Deployment Complete! 🎉**

Everything now runs on **Ubuntu Server at 192.168.0.199**  
Proxmox at **192.168.0.100** is only used for VM creation via API

