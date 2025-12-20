# IP Manager - Complete Docker Images Checklist

## Overview

This document lists ALL Docker images required for air-gapped deployment of IP Manager, including base images needed for building custom containers.

---

## Complete Image List (10 Total)

### Pre-Built Images (6)

These are pulled directly from Docker Hub and used as-is:

1. **mysql:8.0**
   - Purpose: Database server
   - Size: ~500 MB
   - Source: https://hub.docker.com/_/mysql

2. **prom/prometheus:latest**
   - Purpose: Metrics collection and time-series database
   - Size: ~200 MB
   - Source: https://hub.docker.com/r/prom/prometheus

3. **grafana/grafana:latest**
   - Purpose: Monitoring dashboards and visualization
   - Size: ~300 MB
   - Source: https://hub.docker.com/r/grafana/grafana

4. **prom/alertmanager:latest**
   - Purpose: Alert routing and management
   - Size: ~60 MB
   - Source: https://hub.docker.com/r/prom/alertmanager

5. **phpmyadmin:latest**
   - Purpose: MySQL database administration UI
   - Size: ~150 MB
   - Source: https://hub.docker.com/_/phpmyadmin

6. **gcr.io/cadvisor/cadvisor:latest**
   - Purpose: Container resource usage monitoring
   - Size: ~80 MB
   - Source: https://gcr.io/cadvisor/cadvisor

### Custom Built Images (2)

These are built from Dockerfiles in your project:

7. **ipmanager-backend:latest**
   - Built from: `./backend/Dockerfile`
   - Base image: ubuntu:24.04
   - Purpose: FastAPI backend application
   - Size: ~600 MB (includes Python, nmap, dependencies)
   - Contains: Python 3, FastAPI, nmap, curl

8. **ipmanager-frontend:latest**
   - Built from: `./frontend/Dockerfile`
   - Base image: node:18
   - Purpose: React frontend application
   - Size: ~1.2 GB (includes Node.js, npm packages)
   - Contains: Node.js 18, React, npm dependencies

### Base Images for Building (2) - **CRITICAL!**

These are needed to **rebuild** custom images on the air-gapped system:

9. **ubuntu:24.04**
   - Purpose: Base OS for backend container
   - Size: ~80 MB
   - Required: To build ipmanager-backend on air-gapped system
   - **IMPORTANT**: Without this, backend cannot be built on RHEL

10. **node:18**
    - Purpose: Node.js runtime for frontend container
    - Size: ~900 MB
    - Required: To build ipmanager-frontend on air-gapped system
    - **IMPORTANT**: Without this, frontend cannot be built on RHEL

---

## Why Base Images Are Critical

### Scenario Without Base Images:

```
Air-Gapped System:
1. Extract package ✓
2. Load all .tar images ✓
3. Try to start: docker compose up -d
4. Docker tries to build backend
5. ERROR: Cannot pull ubuntu:24.04 (no internet)
6. DEPLOYMENT FAILS ✗
```

### Scenario With Base Images:

```
Air-Gapped System:
1. Extract package ✓
2. Load all .tar images (including ubuntu:24.04, node:18) ✓
3. Run: docker compose up -d
4. Docker builds backend using local ubuntu:24.04 ✓
5. Docker builds frontend using local node:18 ✓
6. DEPLOYMENT SUCCEEDS ✓
```

---

## Verification Commands

### On Source System (Before Packaging):

```bash
# Verify all pre-built images are pulled
docker images | grep -E "mysql|prometheus|grafana|alertmanager|phpmyadmin|cadvisor"

# Verify base images are present
docker images | grep "ubuntu.*24.04"
docker images | grep "node.*18"

# Verify custom images are built
docker images | grep "ipmanager"

# Expected output should show 10 images:
# mysql:8.0
# prom/prometheus:latest
# grafana/grafana:latest
# prom/alertmanager:latest
# phpmyadmin:latest
# gcr.io/cadvisor/cadvisor:latest
# ipmanager-backend:latest
# ipmanager-frontend:latest
# ubuntu:24.04
# node:18
```

### After Packaging:

```bash
cd ipmanager-*-airgap-*/container-images

# Should have 10 .tar files
ls -la *.tar | wc -l
# Output: 10

# Check specific files exist
ls -la | grep -E "ubuntu.*24|node.*18"
```

### On Target System (After Loading Images):

```bash
# Load all images
for img in *.tar; do
    docker load -i "$img"  # or podman load -i "$img"
done

# Verify all 10 images loaded
docker images  # or podman images

# Should see all 10 images listed
```

---

## Package Size Breakdown

| Image | Compressed Size (approx) |
|-------|-------------------------|
| mysql:8.0 | 150 MB |
| prom/prometheus:latest | 80 MB |
| grafana/grafana:latest | 100 MB |
| prom/alertmanager:latest | 25 MB |
| phpmyadmin:latest | 50 MB |
| gcr.io/cadvisor/cadvisor:latest | 30 MB |
| ipmanager-backend:latest | 200 MB |
| ipmanager-frontend:latest | 400 MB |
| **ubuntu:24.04** | **30 MB** |
| **node:18** | **300 MB** |
| **Total** | **~1.4 GB compressed** |

Uncompressed: ~4-5 GB

---

## Troubleshooting

### Issue: Package missing base images

**Symptom**: Deployment fails with "image not found" when building

**Check**:
```bash
cd container-images/
ls -la | grep -E "ubuntu|node"
```

**Fix**: Re-run packaging script (updated version includes base images)

### Issue: Image won't load on RHEL

**Symptom**: `podman load -i ubuntu_24.04.tar` fails

**Solution**: 
```bash
# RHEL may need different format
podman pull ubuntu:24.04 --platform linux/amd64
podman save ubuntu:24.04 -o ubuntu_24.04.tar
```

### Issue: Build fails on air-gapped system

**Symptom**: 
```
ERROR: failed to solve: ubuntu:24.04: not found
```

**Cause**: Base image not loaded

**Fix**:
```bash
# Verify base image is loaded
podman images | grep ubuntu

# If not loaded, load it
cd container-images/
podman load -i ubuntu_24.04.tar

# Verify
podman images | grep ubuntu
# Should show: ubuntu  24.04
```

---

## Updated Packaging Scripts

Both packaging scripts (`package-for-airgap.sh` and `package-for-airgap-rhel9.sh`) have been updated to include:

1. ✅ Pull base images (ubuntu:24.04, node:18)
2. ✅ Save base images to .tar files
3. ✅ Include in image manifest
4. ✅ Verify all 10 images are saved

### What Changed:

**Before** (Missing base images):
```bash
IMAGES=(
    "grafana/grafana:latest"
    "prom/prometheus:latest"
    ...
)
# 6-8 images total
```

**After** (Includes base images):
```bash
IMAGES=(
    "grafana/grafana:latest"
    "prom/prometheus:latest"
    ...
)

BASE_IMAGES=(
    "ubuntu:24.04"
    "node:18"
)

# Pull and save base images
# 10 images total
```

---

## Image Manifest Example

The `image-list.txt` file in the package should show:

```
# Container Images for IP Manager
# Load these images on the air-gapped system

grafana/grafana:latest -> grafana_grafana_latest.tar
prom/prometheus:latest -> prom_prometheus_latest.tar
gcr.io/cadvisor/cadvisor:latest -> cadvisor.tar
prom/alertmanager:latest -> prom_alertmanager_latest.tar
phpmyadmin:latest -> phpmyadmin_latest.tar
mysql:8.0 -> mysql_8.0.tar
ipmanager-backend:latest -> ipmanager-backend_latest.tar
ipmanager-frontend:latest -> ipmanager-frontend_latest.tar
ubuntu:24.04 -> ubuntu_24.04.tar
node:18 -> node_18.tar
```

---

## Deployment Flow on Air-Gapped System

### 1. Load Images
```bash
cd container-images/
for img in *.tar; do
    podman load -i "$img"
done
```

### 2. Verify All Images Loaded
```bash
podman images
# Should show all 10 images
```

### 3. Deploy
```bash
cd ../source-code
podman-compose up -d
```

### 4. What Happens:
- Docker/Podman reads docker-compose.yml
- Sees `build: ./backend` directive
- Looks for `ubuntu:24.04` (finds it locally - loaded from .tar)
- Builds backend container ✓
- Sees `build: ./frontend` directive
- Looks for `node:18` (finds it locally - loaded from .tar)
- Builds frontend container ✓
- Starts all containers ✓

---

## Best Practices

### Before Packaging:
1. ✅ Pull all images: `docker compose pull`
2. ✅ Build custom images: `docker compose build`
3. ✅ Verify base images: `docker images | grep -E "ubuntu|node"`
4. ✅ Run packaging script
5. ✅ Verify package contents: Check for 10 .tar files

### On Air-Gapped System:
1. ✅ Load ALL images (don't skip any)
2. ✅ Verify loaded: `podman images` should show 10 images
3. ✅ Then deploy: `podman-compose up -d`

### Verification:
```bash
# Should see 10 images
podman images | wc -l
# Output: 11 (10 + header line)

# Should see all services running
podman-compose ps
# Output: 8 containers (all "Up")
```

---

## Summary

**Total Images Required**: **10**

- **6** Pre-built images (MySQL, Prometheus, Grafana, etc.)
- **2** Custom built images (backend, frontend)
- **2** Base images for building (ubuntu:24.04, node:18) ← **CRITICAL!**

**Package Size**: ~1.4 GB compressed, ~4-5 GB uncompressed

**Updated Scripts**: Both packaging scripts now include ALL 10 images

---

**End of Docker Images Checklist**
