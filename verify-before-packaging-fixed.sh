#!/bin/bash
#
# Pre-Packaging Verification Script
# Run this on Ubuntu source system BEFORE creating the air-gap package
# Ensures all 10 required Docker images are present
#

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }

echo "=========================================="
echo "  IP Manager Pre-Packaging Verification"
echo "=========================================="
echo ""

# Check if Docker is running
if ! docker ps >/dev/null 2>&1; then
    print_error "Docker is not running or you don't have permission"
    exit 1
fi

print_success "Docker is running"
echo ""

# Define required images
declare -A REQUIRED_IMAGES
REQUIRED_IMAGES["mysql:8.0"]="Database server"
REQUIRED_IMAGES["prom/prometheus:latest"]="Metrics collection"
REQUIRED_IMAGES["grafana/grafana:latest"]="Monitoring dashboards"
REQUIRED_IMAGES["prom/alertmanager:latest"]="Alert management"
REQUIRED_IMAGES["phpmyadmin:latest"]="Database admin UI"
REQUIRED_IMAGES["gcr.io/cadvisor/cadvisor:latest"]="Container monitoring"
REQUIRED_IMAGES["ipmanager-backend:latest"]="Backend application (custom built)"
REQUIRED_IMAGES["ipmanager-frontend:latest"]="Frontend application (custom built)"
REQUIRED_IMAGES["ubuntu:24.04"]="Base image for backend (CRITICAL!)"
REQUIRED_IMAGES["node:18"]="Base image for frontend (CRITICAL!)"

missing_images=()
found_count=0
total_count=${#REQUIRED_IMAGES[@]}

print_status "Checking for required images (${total_count} total)..."
echo ""

# Get list of all docker images
all_images=$(docker images --format "{{.Repository}}:{{.Tag}}")

for image in "${!REQUIRED_IMAGES[@]}"; do
    if echo "$all_images" | grep -Fx "$image" >/dev/null; then
        print_success "Found: $image"
        ((found_count++))
    else
        print_error "Missing: $image"
        missing_images+=("$image")
    fi
done

echo ""
echo "=========================================="
echo "  Summary"
echo "=========================================="
echo ""
echo "Images found: ${found_count}/${total_count}"

if [ ${#missing_images[@]} -eq 0 ]; then
    print_success "All required images are present!"
    echo ""
    echo "You can now run the packaging script:"
    echo "  ./package-for-airgap-rhel9.sh"
    echo ""
    
    # Show images with sizes
    print_status "Image sizes:"
    echo ""
    printf "%-40s %15s\n" "IMAGE" "SIZE"
    printf "%-40s %15s\n" "-----" "----"
    for image in "${!REQUIRED_IMAGES[@]}"; do
        size=$(docker images --format "{{.Size}}" "$image" 2>/dev/null | head -1)
        printf "%-40s %15s\n" "$image" "$size"
    done
    echo ""
    
    exit 0
else
    print_error "Missing ${#missing_images[@]} images!"
    echo ""
    echo "Missing images:"
    for img in "${missing_images[@]}"; do
        echo "  - $img (${REQUIRED_IMAGES[$img]})"
    done
    echo ""
    
    # Provide instructions to fix
    echo "=========================================="
    echo "  How to Fix"
    echo "=========================================="
    echo ""
    
    # Separate missing images into categories
    missing_prebuilt=()
    missing_custom=()
    
    for img in "${missing_images[@]}"; do
        if [[ "$img" == "ipmanager-backend:latest" ]] || [[ "$img" == "ipmanager-frontend:latest" ]]; then
            missing_custom+=("$img")
        else
            missing_prebuilt+=("$img")
        fi
    done
    
    if [ ${#missing_prebuilt[@]} -gt 0 ]; then
        print_status "Step 1: Pull missing pre-built images"
        echo ""
        for img in "${missing_prebuilt[@]}"; do
            echo "  docker pull $img"
        done
        echo ""
    fi
    
    if [ ${#missing_custom[@]} -gt 0 ]; then
        print_status "Step 2: Build missing custom images"
        echo ""
        echo "  cd ~/ipmanager"
        echo "  docker compose build"
        echo ""
    fi
    
    echo "Step 3: Run this script again to verify"
    echo "  ./verify-before-packaging.sh"
    echo ""
    
    exit 1
fi
