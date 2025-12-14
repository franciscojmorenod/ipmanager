# IP Manager Offline Deployment Guide

**Version:** 2.0  
**Last Updated:** December 2024  
**Purpose:** Deploy IP Manager on airgapped/offline machines

---

## Overview

This guide describes how to create a complete offline deployment package for IP Manager that includes:

✅ All Docker images (7 containers)  
✅ Complete application source code  
✅ All Python dependencies (wheels)  
✅ All Node.js dependencies (node_modules)  
✅ Docker installation packages (.deb)  
✅ Automated installation scripts  
✅ Complete documentation  

---

## Prerequisites

### Source Machine (WITH Internet Access)

**Requirements:**
- Ubuntu Server 20.04+ or 24.04
- Docker and Docker Compose installed
- IP Manager source code in `/home/ubuntu/ipmanager`
- Sufficient disk space: ~20GB for package creation
- Internet connection to download dependencies

**Preparation:**
```bash
# Ensure ipmanager is built and working
cd /home/ubuntu/ipmanager
docker compose build
docker compose up -d
docker compose down

# Verify all images are built
docker images | grep -E "(ipmanager|mysql|prometheus|grafana|phpmyadmin|alertmanager)"
```

### Target Machine (WITHOUT Internet Access)

**Requirements:**
- Ubuntu Server 20.04+ or 24.04
- Static IP: 192.168.0.199 (or modify configuration)
- 8GB RAM minimum (16GB recommended)
- 50GB+ free disk space
- Network access to 192.168.0.x subnet
- No internet connection required

---

## Step 1: Build Offline Package (On Source Machine)

### 1.1 Download Build Script

The build script is provided as `build-offline-package.sh`

### 1.2 Make Script Executable

```bash
chmod +x build-offline-package.sh
```

### 1.3 Run Package Builder

```bash
./build-offline-package.sh
```

**What the script does:**

1. **Exports Docker Images** (7 images):
   - `mysql:8.0`
   - `phpmyadmin:latest`
   - `prom/prometheus:latest`
   - `grafana/grafana:latest`
   - `prom/alertmanager:latest`
   - `ipmanager-backend:latest` (built from source)
   - `ipmanager-frontend:latest` (built from source)

2. **Copies Source Code**:
   - Backend (Python/FastAPI)
   - Frontend (React)
   - MySQL init scripts
   - docker-compose.yml
   - Monitoring configs

3. **Downloads Python Dependencies**:
   - All packages from `backend/requirements.txt`
   - Saved as wheels (.whl) for offline installation

4. **Packages Node.js Dependencies**:
   - Complete `node_modules` directory
   - Compressed as tar.gz to save space

5. **Downloads Docker Installation Packages**:
   - docker-ce, docker-ce-cli, containerd.io
   - docker-buildx-plugin, docker-compose-plugin
   - All .deb packages for offline dpkg installation

6. **Creates Installation Scripts**:
   - `install-offline.sh` - Automated installation
   - Configuration templates
   - Documentation

7. **Generates Final Package**:
   - Everything compressed into single `.tar.gz` file
   - Located at `/tmp/ipmanager-offline-package-YYYYMMDD.tar.gz`

### 1.4 Verify Package

```bash
# Check package was created
ls -lh /tmp/ipmanager-offline-package-*.tar.gz

# Expected size: 3-6GB compressed
```

---

## Step 2: Transfer Package to Offline Machine

### Method 1: USB Drive

```bash
# On source machine (with internet)
sudo cp /tmp/ipmanager-offline-package-*.tar.gz /media/usb/

# Safely eject
sudo umount /media/usb

# On target machine (offline)
sudo cp /media/usb/ipmanager-offline-package-*.tar.gz /tmp/
```

### Method 2: External Hard Drive

```bash
# Same process as USB but with larger capacity
sudo cp /tmp/ipmanager-offline-package-*.tar.gz /media/external-hdd/
```

### Method 3: SCP (if machines can temporarily connect)

```bash
# From source machine to target machine
scp /tmp/ipmanager-offline-package-*.tar.gz ubuntu@192.168.0.199:/tmp/
```

### Method 4: Network Share

```bash
# If you have a local file server both machines can access
cp /tmp/ipmanager-offline-package-*.tar.gz /mnt/shared/
```

---

## Step 3: Install on Offline Machine

### 3.1 Extract Package

```bash
# On offline machine
cd /tmp
tar -xzf ipmanager-offline-package-*.tar.gz
cd ipmanager-offline-package
```

### 3.2 Review Package Contents

```bash
# View manifest
cat MANIFEST.txt

# View README
cat README.md

# Directory structure
tree -L 2
```

Expected structure:
```
ipmanager-offline-package/
├── docker-images/          # ~5GB of Docker images
├── source/                 # Complete source code
├── dependencies/
│   ├── docker/            # Docker .deb packages
│   ├── python/            # Python wheels
│   └── nodejs/            # node_modules.tar.gz
├── scripts/
│   └── install-offline.sh # Main installer
├── README.md
└── MANIFEST.txt
```

### 3.3 Run Installation

```bash
chmod +x scripts/install-offline.sh
./scripts/install-offline.sh
```

**Installation steps performed:**

1. ✅ Checks for Docker, installs if missing
2. ✅ Loads all 7 Docker images from .tar files
3. ✅ Copies source code to `/home/ubuntu/ipmanager`
4. ✅ Installs Python dependencies offline
5. ✅ Extracts node_modules for frontend
6. ✅ Creates monitoring directory structure
7. ✅ Generates configuration files
8. ✅ Creates `.env` file template

**Installation output:**
```
==========================================
IP Manager Offline Installation
==========================================

Step 1: Installing Docker (if needed)...
Docker already installed: Docker version 24.0.7

Step 2: Loading Docker Images...
  - Loading mysql_8.0.tar...
  - Loading phpmyadmin_latest.tar...
  - Loading prom_prometheus_latest.tar...
  - Loading grafana_grafana_latest.tar...
  - Loading prom_alertmanager_latest.tar...
  - Loading ipmanager-backend.tar...
  - Loading ipmanager-frontend.tar...

Step 3: Setting up application directory...
Copying source files...

Step 4: Installing Python dependencies offline...
[Package installation progress]

Step 5: Installing Node.js dependencies offline...
Extracting node_modules...

Step 6: Creating monitoring directory structure...
[Configuration created]

==========================================
Installation Complete!
==========================================
```

---

## Step 4: Configure Application

### 4.1 Set Proxmox Password

```bash
cd /home/ubuntu/ipmanager
nano .env
```

Edit:
```bash
PROXMOX_PASSWORD=your_actual_proxmox_password
```

Save and secure:
```bash
chmod 600 .env
```

### 4.2 Review Configuration (Optional)

```bash
# Review docker-compose.yml
nano docker-compose.yml

# Review backend config
nano backend/main.py

# Review monitoring configs
ls -la monitoring/
```

### 4.3 Adjust IP Address (If Not Using 192.168.0.199)

If your offline machine has a different IP:

```bash
# Update frontend API endpoint
nano frontend/src/App.js
# Find and replace: http://192.168.0.199:8000

# Update docker-compose.yml ports if needed
nano docker-compose.yml
```

---

## Step 5: Start Application

### 5.1 Start All Containers

```bash
cd /home/ubuntu/ipmanager
docker compose up -d
```

### 5.2 Verify All Containers Running

```bash
docker ps
```

Expected output (7 containers):
```
CONTAINER ID   IMAGE                      PORTS                    NAMES
xxxxxxxxx      ipmanager-frontend         0.0.0.0:3000->3000/tcp   ipam-frontend
xxxxxxxxx      ipmanager-backend          (host mode)              ipam-backend
xxxxxxxxx      mysql:8.0                  0.0.0.0:3306->3306/tcp   ipam-mysql
xxxxxxxxx      phpmyadmin:latest          0.0.0.0:8080->80/tcp     phpmyadmin
xxxxxxxxx      prom/prometheus:latest     0.0.0.0:9090->9090/tcp   prometheus
xxxxxxxxx      grafana/grafana:latest     0.0.0.0:3001->3000/tcp   grafana
xxxxxxxxx      prom/alertmanager:latest   0.0.0.0:9093->9093/tcp   alertmanager
```

### 5.3 Check Logs

```bash
# View all logs
docker compose logs -f

# View specific container
docker logs ipam-backend -f
docker logs ipam-frontend -f
```

### 5.4 Test Services

```bash
# Test each endpoint
curl http://localhost:3000                 # Frontend
curl http://localhost:8000/docs            # Backend API
curl http://localhost:8080                 # phpMyAdmin
curl http://localhost:9090                 # Prometheus
curl http://localhost:3001                 # Grafana
curl http://localhost:9093                 # Alertmanager

# Test database
docker exec -it ipam-mysql mysql -uipmanager -pipmanager_pass_2024 -e "SHOW DATABASES;"
```

---

## Step 6: Access and Verify

### 6.1 Access Web Interfaces

From any computer on the network:

| Service | URL | Credentials |
|---------|-----|-------------|
| **IP Manager** | http://192.168.0.199:3000 | None |
| **API Docs** | http://192.168.0.199:8000/docs | None |
| **phpMyAdmin** | http://192.168.0.199:8080 | root / ipmanager_root_2024 |
| **Grafana** | http://192.168.0.199:3001 | admin / admin |
| **Prometheus** | http://192.168.0.199:9090 | None |
| **Alertmanager** | http://192.168.0.199:9093 | None |

### 6.2 Test Network Scanning

1. Open IP Manager: http://192.168.0.199:3000
2. Click "Scan Network"
3. Enter subnet: `192.168.0`
4. Click "Start Scan"
5. Verify active devices are detected

### 6.3 Verify Database

```bash
# Check tables exist
docker exec -it ipam-mysql mysql -uipmanager -pipmanager_pass_2024 ipmanager -e "SHOW TABLES;"

# Should show:
# +---------------------+
# | Tables_in_ipmanager |
# +---------------------+
# | device_history      |
# | ip_addresses        |
# | node_history        |
# | nodes               |
# | vm_traffic_tests    |
# +---------------------+
```

---

## Troubleshooting Offline Installation

### Issue: Docker Not Installing

**Symptom:** dpkg fails to install Docker packages

**Solution:**
```bash
cd dependencies/docker
sudo dpkg -i *.deb
sudo apt-get install -f -y  # Fix dependencies

# If still failing, install manually in order:
sudo dpkg -i containerd.io_*.deb
sudo dpkg -i docker-ce-cli_*.deb
sudo dpkg -i docker-ce_*.deb
sudo dpkg -i docker-buildx-plugin_*.deb
sudo dpkg -i docker-compose-plugin_*.deb
```

### Issue: Docker Images Not Loading

**Symptom:** "docker load" fails

**Solution:**
```bash
# Load images one by one to identify problem
cd docker-images
for tar in *.tar; do
    echo "Loading $tar..."
    docker load -i "$tar" || echo "Failed: $tar"
done

# Check available space
df -h

# Clean up Docker if needed
docker system prune -a
```

### Issue: Python Dependencies Fail

**Symptom:** pip install errors

**Solution:**
```bash
cd dependencies/python

# Install with verbose output
pip install --no-index --find-links=. *.whl --break-system-packages -v

# Or install individually
for wheel in *.whl; do
    pip install --no-index --find-links=. "$wheel" --break-system-packages || echo "Failed: $wheel"
done
```

### Issue: node_modules Missing

**Symptom:** Frontend build fails

**Solution:**
```bash
cd /home/ubuntu/ipmanager/frontend

# Extract from package
tar -xzf /tmp/ipmanager-offline-package/dependencies/nodejs/node_modules.tar.gz

# Or rebuild (requires npm to be installed offline)
npm install --offline
```

### Issue: Container Can't Start

**Symptom:** Docker compose up fails

**Solution:**
```bash
# Check for port conflicts
sudo netstat -tulpn | grep -E '(3000|8000|3306|8080|9090|3001|9093)'

# View detailed error
docker compose up

# Check individual container
docker logs <container-name>

# Restart specific service
docker compose restart <service-name>
```

### Issue: Network Scanning Fails

**Symptom:** No devices detected

**Solution:**
```bash
# Verify host network mode
docker inspect ipam-backend | grep NetworkMode
# Should show: "NetworkMode": "host"

# Test from backend container
docker exec -it ipam-backend ping -c 3 192.168.0.1
docker exec -it ipam-backend nmap -sn 192.168.0.1-10

# Check nmap is installed
docker exec -it ipam-backend which nmap
docker exec -it ipam-backend nmap --version
```

---

## Package Size Breakdown

Approximate sizes for planning transfer:

| Component | Compressed | Uncompressed |
|-----------|-----------|--------------|
| Docker Images | 2-3 GB | 5-7 GB |
| Source Code | 10-50 MB | 50-100 MB |
| Python Dependencies | 50-100 MB | 150-300 MB |
| Node Modules | 100-200 MB | 500 MB - 1 GB |
| Docker Packages | 50-100 MB | 150-200 MB |
| **Total Package** | **3-5 GB** | **7-10 GB** |

---

## Updating Offline Installation

### Method 1: New Package

1. Build fresh package on source machine
2. Transfer to offline machine
3. Stop current installation: `docker compose down`
4. Backup data: `cp -r /home/ubuntu/ipmanager /home/ubuntu/ipmanager.backup`
5. Run new installer
6. Restore data if needed
7. Start: `docker compose up -d`

### Method 2: Incremental Update

```bash
# On source machine - export only changed images
docker save -o backend-update.tar ipmanager-backend:latest

# Transfer to offline machine
# Load updated image
docker load -i backend-update.tar

# Restart service
cd /home/ubuntu/ipmanager
docker compose up -d --force-recreate backend
```

---

## Security Considerations

### Offline Package Security

- 🔒 Package contains no credentials (passwords set during installation)
- 🔒 Docker images are official or built from trusted source
- 🔒 Package should be transferred via secure physical media
- 🔒 Verify package integrity with checksums

### Generate Checksums

**On source machine:**
```bash
sha256sum /tmp/ipmanager-offline-package-*.tar.gz > package.sha256
cat package.sha256
```

**On target machine:**
```bash
sha256sum -c package.sha256
# Should output: ipmanager-offline-package-*.tar.gz: OK
```

---

## Best Practices

### 1. Test Package Before Production

- Build package on test source machine
- Install on test offline machine
- Verify all functionality
- Then create production package

### 2. Document Your Configuration

```bash
# Save your settings
cd /home/ubuntu/ipmanager
tar -czf ipmanager-config-backup.tar.gz .env monitoring/ docker-compose.yml
```

### 3. Keep Package Updated

- Rebuild package quarterly or when updates available
- Test new packages in staging environment
- Maintain version control of packages

### 4. Plan Storage

- Keep package on secure backup media
- Store in multiple locations
- Label clearly with version and date

---

## Appendix: Manual Package Creation

If the automated script doesn't work, you can manually create the package:

### A. Export Docker Images

```bash
docker save -o mysql.tar mysql:8.0
docker save -o phpmyadmin.tar phpmyadmin:latest
docker save -o prometheus.tar prom/prometheus:latest
docker save -o grafana.tar grafana/grafana:latest
docker save -o alertmanager.tar prom/alertmanager:latest
docker save -o backend.tar ipmanager-backend:latest
docker save -o frontend.tar ipmanager-frontend:latest
```

### B. Download Python Packages

```bash
pip download -r backend/requirements.txt -d python-packages/
```

### C. Archive node_modules

```bash
cd frontend
tar -czf node_modules.tar.gz node_modules/
```

### D. Create Package

```bash
mkdir ipmanager-offline-package
mv *.tar ipmanager-offline-package/
cp -r /home/ubuntu/ipmanager ipmanager-offline-package/source/
mv python-packages ipmanager-offline-package/dependencies/
tar -czf ipmanager-offline-package.tar.gz ipmanager-offline-package/
```

---

## Support and Documentation

**Included Documentation:**
- `IPMANAGER-DESIGN-DOCUMENT.pdf` - Complete system design
- `IPMANAGER-QUICK-REFERENCE.md` - Daily operations guide
- `README.md` - Package overview and quick start

**Online Resources (when available):**
- Docker documentation: https://docs.docker.com
- nmap documentation: https://nmap.org
- Proxmox API: https://pve.proxmox.com/wiki/Proxmox_VE_API

---

**Document Version:** 1.0  
**Last Updated:** December 2024  
**Author:** Francisco  
**Status:** Production Ready
