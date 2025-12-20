# Complete Air-Gap Packaging Guide for IP Manager
## Ubuntu 24.04 (Source) → RHEL 9 (Air-Gapped Target)

---

## ✅ YES - All 10 Images Are Now Saved!

The updated packaging scripts (`package-for-airgap-rhel9.sh`) now save **ALL 10 required images**.

---

## Complete Image List (10 Total)

### From docker-compose.yml (6 pre-built images):

1. ✅ **mysql:8.0** - Database server
2. ✅ **prom/prometheus:latest** - Metrics collection
3. ✅ **grafana/grafana:latest** - Monitoring dashboards
4. ✅ **prom/alertmanager:latest** - Alert management
5. ✅ **phpmyadmin:latest** - Database admin UI
6. ✅ **gcr.io/cadvisor/cadvisor:latest** - Container monitoring

### Custom Built Images (2):

7. ✅ **ipmanager-backend:latest** 
   - Built from `./backend/Dockerfile`
   - Base: `ubuntu:24.04`
   - Contains: Python, FastAPI, nmap

8. ✅ **ipmanager-frontend:latest**
   - Built from `./frontend/Dockerfile`
   - Base: `node:18`
   - Contains: Node.js, React, npm packages

### Base Images (2) - **CRITICAL FOR AIR-GAPPED!**

9. ✅ **ubuntu:24.04** - Needed to build backend on RHEL 9
10. ✅ **node:18** - Needed to build frontend on RHEL 9

---

## Why Base Images Are Critical

### ❌ Without Base Images (Old Scripts):
```
RHEL 9 Air-Gapped System:
1. Extract package ✓
2. Load 8 images (missing ubuntu:24.04 and node:18) ✓
3. Run: podman-compose up -d
4. Tries to build backend...
5. ERROR: Cannot pull ubuntu:24.04 (no internet!) ✗
6. DEPLOYMENT FAILS ✗
```

### ✅ With Base Images (Updated Scripts):
```
RHEL 9 Air-Gapped System:
1. Extract package ✓
2. Load ALL 10 images (including ubuntu:24.04 and node:18) ✓
3. Run: podman-compose up -d
4. Builds backend using local ubuntu:24.04 ✓
5. Builds frontend using local node:18 ✓
6. All containers start ✓
7. DEPLOYMENT SUCCEEDS ✓
```

---

## Step-by-Step Workflow

### On Ubuntu 24.04 Source System:

#### Step 1: Verify All Images Are Present

```bash
cd ~/ipmanager
chmod +x verify-before-packaging.sh
./verify-before-packaging.sh
```

**Expected output:**
```
[✓] Found: mysql:8.0
[✓] Found: prom/prometheus:latest
[✓] Found: grafana/grafana:latest
[✓] Found: prom/alertmanager:latest
[✓] Found: phpmyadmin:latest
[✓] Found: gcr.io/cadvisor/cadvisor:latest
[✓] Found: ipmanager-backend:latest
[✓] Found: ipmanager-frontend:latest
[✓] Found: ubuntu:24.04
[✓] Found: node:18

Images found: 10/10
[✓] All required images are present!
```

#### Step 2: If Missing Images, Fix Them

**If missing pre-built images:**
```bash
docker pull mysql:8.0
docker pull prom/prometheus:latest
docker pull grafana/grafana:latest
docker pull prom/alertmanager:latest
docker pull phpmyadmin:latest
docker pull gcr.io/cadvisor/cadvisor:latest
docker pull ubuntu:24.04
docker pull node:18
```

**If missing custom images:**
```bash
cd ~/ipmanager
docker compose build
```

**Verify again:**
```bash
./verify-before-packaging.sh
```

#### Step 3: Create Package

```bash
chmod +x package-for-airgap-rhel9.sh
./package-for-airgap-rhel9.sh
```

**What happens:**
1. ✅ Pulls all pre-built images (if not present)
2. ✅ Pulls base images (ubuntu:24.04, node:18)
3. ✅ Builds custom images (backend, frontend)
4. ✅ Saves all 10 images as .tar files
5. ✅ Copies source code (excluding .env)
6. ✅ Creates RHEL-specific deployment scripts
7. ✅ Creates compressed archive

**Result:**
```
ipmanager-rhel9-airgap-20241219_143022.tar.gz (~3-4 GB)
```

#### Step 4: Verify Package Contents

```bash
cd ipmanager-rhel9-airgap-package/ipmanager-rhel9-airgap-*/container-images
ls -la *.tar | wc -l
```

**Should show: 10**

```bash
ls -la *.tar
```

**Should list:**
```
mysql_8.0.tar
prom_prometheus_latest.tar
grafana_grafana_latest.tar
prom_alertmanager_latest.tar
phpmyadmin_latest.tar
cadvisor.tar
ipmanager-backend_latest.tar
ipmanager-frontend_latest.tar
ubuntu_24.04.tar
node_18.tar
```

---

### On RHEL 9 Target System (Air-Gapped):

#### Step 1: Transfer Package

```bash
# Via USB drive
cp ipmanager-rhel9-airgap-20241219_143022.tar.gz /media/usb/

# Or via internal network
scp ipmanager-rhel9-airgap-20241219_143022.tar.gz user@rhel-server:~/
```

#### Step 2: Extract Package

```bash
cd ~
tar -xzf ipmanager-rhel9-airgap-20241219_143022.tar.gz
cd ipmanager-rhel9-airgap-20241219_143022
```

#### Step 3: Verify Package

```bash
cd scripts
./verify-package-rhel9.sh
```

**Expected output:**
```
[✓] Running on: Red Hat Enterprise Linux release 9.X
[✓] container-images/ exists
[✓] source-code/ exists
[✓] Found 10 container image files
[✓] Package verification passed!
```

#### Step 4: Deploy

```bash
./deploy-rhel9.sh
```

**Interactive prompts:**
```
[!] SELinux is in enforcing mode
Set SELinux to permissive mode? (y/N) y

[*] Firewalld is active
Open firewall ports? (y/N) y

[*] Loading container images...
[✓] Loaded: mysql_8.0.tar
[✓] Loaded: prom_prometheus_latest.tar
[✓] Loaded: ubuntu_24.04.tar  ← BASE IMAGE
[✓] Loaded: node_18.tar  ← BASE IMAGE
...
[✓] Loaded 10 container images

[*] Starting IP Manager services...
[✓] IP Manager started successfully!
```

#### Step 5: Configure

```bash
cd ~/ipmanager
nano .env
```

Update:
- MySQL passwords
- Proxmox host/credentials
- Grafana password

```bash
podman-compose restart
```

#### Step 6: Verify Deployment

```bash
# Check containers
podman-compose ps
# Should show 8 containers running

# Check images
podman images
# Should show all 10 images

# Test web access
curl http://localhost:3000  # Frontend
curl http://localhost:3001  # Grafana
curl http://localhost:9090  # Prometheus
```

---

## Troubleshooting

### Issue: Only 8 .tar files in package

**Cause:** Old packaging script (missing base images)

**Fix:** Re-run packaging with updated script

### Issue: Build fails on RHEL with "ubuntu:24.04 not found"

**Cause:** Base image wasn't loaded

**Fix:**
```bash
cd container-images/
podman load -i ubuntu_24.04.tar
podman images | grep ubuntu
# Should show: ubuntu  24.04
```

### Issue: Build fails with "node:18 not found"

**Cause:** Base image wasn't loaded

**Fix:**
```bash
cd container-images/
podman load -i node_18.tar
podman images | grep node
# Should show: node  18
```

### Issue: Package is missing some images

**Verification on source system:**
```bash
cd ~/ipmanager
./verify-before-packaging.sh
```

Follow the instructions to pull/build missing images, then re-package.

---

## File Checklist

### Scripts to Copy to Your Project:

```bash
# On your Ubuntu source system
cp package-for-airgap-rhel9.sh ~/ipmanager/
cp verify-before-packaging.sh ~/ipmanager/
chmod +x ~/ipmanager/*.sh
```

### Documentation:

- ✅ `DOCKER-IMAGES-CHECKLIST.md` - Complete image reference
- ✅ `RHEL9-DEPLOYMENT-GUIDE.md` - RHEL 9 deployment guide
- ✅ `AIRGAP-DEPLOYMENT-GUIDE.md` - Air-gap deployment guide
- ✅ `DESIGN.pdf` - Complete system documentation

---

## Quick Command Reference

### Source System (Ubuntu 24.04):

```bash
# 1. Verify all images present
./verify-before-packaging.sh

# 2. Create package
./package-for-airgap-rhel9.sh

# 3. Verify package
cd ipmanager-rhel9-airgap-*/container-images
ls -la *.tar | wc -l  # Should be 10
```

### Target System (RHEL 9):

```bash
# 1. Extract
tar -xzf ipmanager-rhel9-airgap-*.tar.gz
cd ipmanager-rhel9-airgap-*/scripts

# 2. Verify
./verify-package-rhel9.sh

# 3. Deploy
./deploy-rhel9.sh

# 4. Configure
nano ~/ipmanager/.env
podman-compose restart

# 5. Access
http://localhost:3000  # IP Manager
http://localhost:3001  # Grafana
```

---

## Summary

✅ **ALL 10 images are now saved** in the updated packaging scripts

✅ **Includes base images** (ubuntu:24.04, node:18) needed for building

✅ **Deployment will work** on air-gapped RHEL 9 systems

✅ **No internet required** on target system

✅ **Complete automation** with interactive configuration

**Package Size:** ~3-4 GB compressed, ~8-10 GB uncompressed

**Deployment Time:** 10-15 minutes (load images + build + start)

---

**You're ready to package and deploy!** 🚀
