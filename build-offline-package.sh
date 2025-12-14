#!/bin/bash
#
# IP Manager Offline Package Builder
# Creates a complete offline deployment package with all dependencies
#
# Run this on a machine WITH internet access
# Then transfer the resulting package to the offline machine
#

set -e  # Exit on error

echo "=========================================="
echo "IP Manager Offline Package Builder"
echo "=========================================="
echo ""

# Configuration
PACKAGE_NAME="ipmanager-offline-package"
PACKAGE_VERSION="2.0-$(date +%Y%m%d)"
BUILD_DIR="/tmp/${PACKAGE_NAME}"
FINAL_PACKAGE="${PACKAGE_NAME}-${PACKAGE_VERSION}.tar.gz"

# Clean up any previous builds
if [ -d "$BUILD_DIR" ]; then
    echo "Cleaning up previous build..."
    rm -rf "$BUILD_DIR"
fi

# Create directory structure
echo "Creating package directory structure..."
mkdir -p "$BUILD_DIR"/{docker-images,source,scripts,dependencies}

cd "$BUILD_DIR"

echo ""
echo "=========================================="
echo "Step 1: Exporting Docker Images"
echo "=========================================="

# List of all required Docker images
DOCKER_IMAGES=(
    "mysql:8.0"
    "phpmyadmin:latest"
    "prom/prometheus:latest"
    "grafana/grafana:latest"
    "prom/alertmanager:latest"
)

echo "Pulling and saving Docker images..."
for image in "${DOCKER_IMAGES[@]}"; do
    echo "  - Pulling $image..."
    docker pull $image
    
    # Create safe filename
    filename=$(echo "$image" | sed 's/[\/:]/_/g')
    echo "  - Saving to docker-images/${filename}.tar..."
    docker save -o "docker-images/${filename}.tar" "$image"
done

echo ""
echo "=========================================="
echo "Step 2: Building Custom Docker Images"
echo "=========================================="

# We need to build backend and frontend images on the source machine
# and include the source code

echo "Copying application source code..."
if [ ! -d "/home/ubuntu/ipmanager" ]; then
    echo "ERROR: /home/ubuntu/ipmanager not found!"
    echo "Please run this script on the machine with ipmanager source code"
    exit 1
fi

cp -r /home/ubuntu/ipmanager/* source/

echo "Building backend Docker image..."
cd source/backend
docker build -t ipmanager-backend:latest .
docker save -o ../../docker-images/ipmanager-backend.tar ipmanager-backend:latest
cd ../..

echo "Building frontend Docker image..."
cd source/frontend
docker build -t ipmanager-frontend:latest .
docker save -o ../../docker-images/ipmanager-frontend.tar ipmanager-frontend:latest
cd ../..

echo ""
echo "=========================================="
echo "Step 3: Downloading System Dependencies"
echo "=========================================="

# Create a list of APT packages needed
echo "Downloading Docker installation packages..."
mkdir -p dependencies/docker

# Download Docker packages (for Ubuntu 24.04)
cd dependencies/docker

# Create a script to download all Docker dependencies
cat > download-docker-deps.sh << 'SCRIPT'
#!/bin/bash
apt-get update
apt-get download docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
SCRIPT

chmod +x download-docker-deps.sh

# If running on Ubuntu, download the packages
if command -v apt-get &> /dev/null; then
    echo "Downloading Docker .deb packages..."
    
    # Add Docker's official GPG key and repository
    mkdir -p /tmp/docker-repo-setup
    cd /tmp/docker-repo-setup
    
    # Download packages to our dependencies directory
    apt-get update
    cd "$BUILD_DIR/dependencies/docker"
    apt-get download docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || \
        echo "Note: Could not download Docker packages. You may need to add Docker repository first."
fi

cd "$BUILD_DIR"

echo ""
echo "=========================================="
echo "Step 4: Collecting Python Dependencies"
echo "=========================================="

# Download all Python packages with dependencies
mkdir -p dependencies/python

echo "Downloading Python packages for backend..."
if [ -f "source/backend/requirements.txt" ]; then
    pip download -r source/backend/requirements.txt -d dependencies/python
else
    echo "Warning: backend/requirements.txt not found"
fi

echo ""
echo "=========================================="
echo "Step 5: Collecting Node.js Dependencies"
echo "=========================================="

# Package entire node_modules from built frontend
mkdir -p dependencies/nodejs

echo "Copying node_modules from frontend..."
if [ -d "source/frontend/node_modules" ]; then
    # Create a tarball of node_modules to save space
    echo "  - Creating node_modules archive..."
    cd source/frontend
    tar -czf ../../dependencies/nodejs/node_modules.tar.gz node_modules/
    cd ../..
else
    echo "Warning: frontend/node_modules not found. Installing..."
    cd source/frontend
    if [ -f "package.json" ]; then
        npm install
        tar -czf ../../dependencies/nodejs/node_modules.tar.gz node_modules/
    fi
    cd ../..
fi

# Also save package.json and package-lock.json
cp source/frontend/package*.json dependencies/nodejs/ 2>/dev/null || true

echo ""
echo "=========================================="
echo "Step 6: Creating Installation Scripts"
echo "=========================================="

# Create installation script for offline machine
cat > scripts/install-offline.sh << 'INSTALL_SCRIPT'
#!/bin/bash
#
# IP Manager Offline Installation Script
# Run this on the offline/airgapped machine
#

set -e

echo "=========================================="
echo "IP Manager Offline Installation"
echo "=========================================="
echo ""

INSTALL_DIR="/home/ubuntu/ipmanager"

# Check if running as root for Docker installation
if [ "$EUID" -eq 0 ]; then 
    echo "Please do not run as root. Run as the ubuntu user."
    echo "The script will use sudo when needed."
    exit 1
fi

echo "Step 1: Installing Docker (if needed)..."
if ! command -v docker &> /dev/null; then
    echo "Docker not found. Installing from local packages..."
    
    cd dependencies/docker
    sudo dpkg -i *.deb 2>/dev/null || true
    sudo apt-get install -f -y  # Fix any dependency issues
    
    # Add current user to docker group
    sudo usermod -aG docker $USER
    
    echo "Docker installed. You may need to log out and back in for group changes to take effect."
    echo "Or run: newgrp docker"
else
    echo "Docker already installed: $(docker --version)"
fi

echo ""
echo "Step 2: Loading Docker Images..."
cd ../../docker-images

for tarfile in *.tar; do
    echo "  - Loading $tarfile..."
    docker load -i "$tarfile"
done

echo ""
echo "Step 3: Setting up application directory..."
if [ -d "$INSTALL_DIR" ]; then
    echo "Backing up existing installation..."
    sudo mv "$INSTALL_DIR" "${INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
fi

sudo mkdir -p "$INSTALL_DIR"
sudo chown $USER:$USER "$INSTALL_DIR"

echo "Copying source files..."
cp -r ../source/* "$INSTALL_DIR/"

echo ""
echo "Step 4: Installing Python dependencies offline..."
cd ../dependencies/python
if [ -n "$(ls -A .)" ]; then
    pip install --no-index --find-links=. *.whl *.tar.gz --break-system-packages 2>/dev/null || \
        echo "Note: Some Python packages may already be installed"
fi

echo ""
echo "Step 5: Installing Node.js dependencies offline..."
cd ../nodejs
if [ -f "node_modules.tar.gz" ]; then
    echo "Extracting node_modules..."
    tar -xzf node_modules.tar.gz -C "$INSTALL_DIR/frontend/"
fi

echo ""
echo "Step 6: Creating monitoring directory structure..."
cd "$INSTALL_DIR"
mkdir -p monitoring/{prometheus/targets,grafana/{provisioning/{datasources,dashboards},dashboards},alertmanager}

# Create Prometheus config
cat > monitoring/prometheus/prometheus.yml << 'PROM_CONFIG'
global:
  scrape_interval: 5s
  evaluation_interval: 5s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node_exporter'
    file_sd_configs:
      - files: ['/etc/prometheus/targets/nodes.yml']

  - job_name: 'iperf3'
    file_sd_configs:
      - files: ['/etc/prometheus/targets/iperf.yml']
PROM_CONFIG

# Create initial target files
echo '[]' > monitoring/prometheus/targets/nodes.yml
echo '[]' > monitoring/prometheus/targets/iperf.yml

# Create Grafana datasource
mkdir -p monitoring/grafana/provisioning/datasources
cat > monitoring/grafana/provisioning/datasources/prometheus.yml << 'GRAFANA_DS'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
GRAFANA_DS

# Create dashboard provisioning
mkdir -p monitoring/grafana/provisioning/dashboards
cat > monitoring/grafana/provisioning/dashboards/dashboards.yml << 'GRAFANA_DASH'
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
GRAFANA_DASH

# Create Alertmanager config
cat > monitoring/alertmanager/config.yml << 'ALERT_CONFIG'
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
ALERT_CONFIG

echo ""
echo "Step 7: Creating .env file for Proxmox credentials..."
cat > .env << 'ENV_FILE'
PROXMOX_PASSWORD=your_proxmox_password_here
ENV_FILE

chmod 600 .env
echo "Please edit $INSTALL_DIR/.env and set your Proxmox password"

echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Edit $INSTALL_DIR/.env and set your Proxmox password"
echo "2. Review $INSTALL_DIR/docker-compose.yml"
echo "3. Start the stack:"
echo "   cd $INSTALL_DIR"
echo "   docker compose up -d"
echo ""
echo "Access URLs:"
echo "  - IP Manager: http://192.168.0.199:3000"
echo "  - API Docs:   http://192.168.0.199:8000/docs"
echo "  - Grafana:    http://192.168.0.199:3001"
echo "  - Prometheus: http://192.168.0.199:9090"
echo ""
INSTALL_SCRIPT

chmod +x scripts/install-offline.sh

# Create README for the package
cat > README.md << 'README'
# IP Manager Offline Deployment Package

This package contains everything needed to deploy IP Manager on an airgapped/offline machine.

## Package Contents

```
ipmanager-offline-package/
├── docker-images/          # All Docker images as .tar files
│   ├── mysql_8.0.tar
│   ├── phpmyadmin_latest.tar
│   ├── prom_prometheus_latest.tar
│   ├── grafana_grafana_latest.tar
│   ├── prom_alertmanager_latest.tar
│   ├── ipmanager-backend.tar
│   └── ipmanager-frontend.tar
├── source/                 # Complete application source code
│   ├── backend/
│   ├── frontend/
│   ├── mysql/
│   ├── monitoring/
│   └── docker-compose.yml
├── dependencies/           # All dependencies
│   ├── docker/            # Docker installation packages (.deb)
│   ├── python/            # Python wheels and packages
│   └── nodejs/            # node_modules archive
├── scripts/               # Installation scripts
│   └── install-offline.sh
└── README.md              # This file
```

## System Requirements

**Target Machine (Offline):**
- Ubuntu 20.04 or 24.04 LTS
- 8GB RAM minimum (16GB recommended)
- 50GB+ free disk space
- Network access to 192.168.0.x subnet
- Static IP: 192.168.0.199 (or update docker-compose.yml)

## Installation Instructions

### 1. Transfer Package to Offline Machine

Use any method to transfer the package:
- USB drive
- External hard drive
- Network file share (if available)
- SCP/SFTP from a connected machine

```bash
# Example using USB drive
# On source machine:
cp ipmanager-offline-package-*.tar.gz /media/usb/

# On offline machine:
cp /media/usb/ipmanager-offline-package-*.tar.gz /tmp/
```

### 2. Extract Package

```bash
cd /tmp
tar -xzf ipmanager-offline-package-*.tar.gz
cd ipmanager-offline-package
```

### 3. Run Installation Script

```bash
chmod +x scripts/install-offline.sh
./scripts/install-offline.sh
```

The script will:
1. Install Docker (if needed)
2. Load all Docker images
3. Copy source files to /home/ubuntu/ipmanager
4. Install Python dependencies
5. Extract node_modules
6. Create monitoring directory structure
7. Generate configuration files

### 4. Configure Application

```bash
cd /home/ubuntu/ipmanager

# Edit Proxmox credentials
nano .env
# Set: PROXMOX_PASSWORD=your_actual_password

# Review configuration (optional)
nano docker-compose.yml
```

### 5. Start Application

```bash
cd /home/ubuntu/ipmanager
docker compose up -d
```

### 6. Verify Installation

```bash
# Check all containers are running
docker ps

# Expected output: 7 containers
# - ipam-mysql
# - ipam-backend
# - ipam-frontend
# - phpmyadmin
# - prometheus
# - grafana
# - alertmanager

# Check logs
docker compose logs -f
```

### 7. Access Application

Open browser and navigate to:
- **IP Manager UI:** http://192.168.0.199:3000
- **API Documentation:** http://192.168.0.199:8000/docs
- **Grafana:** http://192.168.0.199:3001 (admin/admin)
- **Prometheus:** http://192.168.0.199:9090

## Troubleshooting

### Docker Permission Issues

If you get permission errors:
```bash
sudo usermod -aG docker $USER
newgrp docker
```

### Images Not Loading

```bash
# Load images manually
cd docker-images
for tar in *.tar; do docker load -i $tar; done
```

### Container Fails to Start

```bash
# Check logs
docker logs <container-name>

# Restart specific container
docker compose restart <service-name>
```

### Network Scanning Not Working

```bash
# Verify backend is using host network mode
docker inspect ipam-backend | grep NetworkMode
# Should show: "NetworkMode": "host"

# Test network access
docker exec ipam-backend ping -c 3 192.168.0.1
```

## Post-Installation

### Setup VMs for Monitoring

On each VM you want to monitor:
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

# Start service
sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
```

### Add VM to Monitoring

```bash
# Edit Prometheus targets
nano /home/ubuntu/ipmanager/monitoring/prometheus/targets/nodes.yml

# Add:
- targets:
    - '192.168.0.32:9100'
  labels:
    job: 'node_exporter'

# Reload Prometheus
curl -X POST http://192.168.0.199:9090/-/reload
```

## Package Information

**Version:** 2.0
**Build Date:** [Generated at build time]
**Source Machine:** [Where package was built]
**Target OS:** Ubuntu 20.04/24.04

## Support

For issues or questions, refer to:
- Complete documentation: IPMANAGER-DESIGN-DOCUMENT.pdf
- Quick reference: IPMANAGER-QUICK-REFERENCE.md

## Files Included

- Docker Images: 7 images (~5GB compressed)
- Source Code: Complete application
- Dependencies: All Python and Node.js packages
- Documentation: Design docs and quick reference
README

echo ""
echo "Step 7: Creating manifest file..."
cat > MANIFEST.txt << MANIFEST
IP Manager Offline Package Manifest
====================================
Build Date: $(date)
Build Host: $(hostname)
Build User: $(whoami)

Docker Images:
MANIFEST

ls -lh docker-images/*.tar >> MANIFEST.txt

cat >> MANIFEST.txt << MANIFEST

Source Files:
MANIFEST

find source -type f | head -20 >> MANIFEST.txt
echo "  ... (additional files)" >> MANIFEST.txt

cat >> MANIFEST.txt << MANIFEST

Dependencies:
  - Python packages: $(ls dependencies/python/*.whl 2>/dev/null | wc -l) wheels
  - Docker packages: $(ls dependencies/docker/*.deb 2>/dev/null | wc -l) debs
  - Node modules: $([ -f dependencies/nodejs/node_modules.tar.gz ] && echo "included" || echo "not found")

Total Package Size (uncompressed): $(du -sh . | cut -f1)
MANIFEST

echo ""
echo "=========================================="
echo "Step 8: Creating final archive..."
echo "=========================================="

cd /tmp
echo "Compressing package (this may take several minutes)..."
tar -czf "$FINAL_PACKAGE" "$PACKAGE_NAME/"

FINAL_SIZE=$(du -h "$FINAL_PACKAGE" | cut -f1)

echo ""
echo "=========================================="
echo "Package Build Complete!"
echo "=========================================="
echo ""
echo "Package: /tmp/$FINAL_PACKAGE"
echo "Size: $FINAL_SIZE"
echo ""
echo "To use this package:"
echo "1. Transfer /tmp/$FINAL_PACKAGE to your offline machine"
echo "2. Extract: tar -xzf $FINAL_PACKAGE"
echo "3. Run: cd $PACKAGE_NAME && ./scripts/install-offline.sh"
echo ""
echo "Package contents:"
cat "$BUILD_DIR/MANIFEST.txt"
echo ""
