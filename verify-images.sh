#!/bin/bash
#
# Pre-Packaging Verification Script
# Ensures all 10 required Docker images are present
#

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

echo "=========================================="
echo "  IP Manager Pre-Packaging Verification"
echo "=========================================="
echo ""

# Check Docker
if ! docker ps >/dev/null 2>&1; then
    print_error "Docker is not running"
    exit 1
fi
print_success "Docker is running"
echo ""

print_status "Checking for required images (10 total)..."
echo ""

# Required images array
images=(
    "mysql:8.0"
    "prom/prometheus:latest"
    "grafana/grafana:latest"
    "prom/alertmanager:latest"
    "phpmyadmin:latest"
    "gcr.io/cadvisor/cadvisor:latest"
    "ipmanager-backend:latest"
    "ipmanager-frontend:latest"
    "ubuntu:24.04"
    "node:18"
)

found=0
missing=()

for img in "${images[@]}"; do
    if docker images "$img" --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -q .; then
        print_success "Found: $img"
        ((found++))
    else
        print_error "Missing: $img"
        missing+=("$img")
    fi
done

echo ""
echo "=========================================="
echo "  Summary"
echo "=========================================="
echo ""
echo "Images found: $found/10"

if [ $found -eq 10 ]; then
    print_success "All required images present!"
    echo ""
    echo "Image sizes:"
    docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}" | grep -E "mysql:8.0|prometheus:latest|grafana:latest|alertmanager:latest|phpmyadmin:latest|cadvisor:latest|ipmanager-|ubuntu:24.04|node:18"
    echo ""
    echo "Ready to package:"
    echo "  ./package-for-airgap-rhel9.sh"
    exit 0
else
    print_error "Missing $((10-found)) images"
    echo ""
    echo "To fix:"
    echo ""
    
    # Check what's missing
    need_pull=0
    need_build=0
    
    for img in "${missing[@]}"; do
        if [[ "$img" == "ipmanager-"* ]]; then
            need_build=1
        else
            need_pull=1
            echo "  docker pull $img"
        fi
    done
    
    if [ $need_build -eq 1 ]; then
        echo ""
        echo "  # Build custom images"
        echo "  docker compose build"
    fi
    
    echo ""
    echo "Then run this script again"
    exit 1
fi
