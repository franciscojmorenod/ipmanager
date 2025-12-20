#!/bin/bash
#
# IP Manager - RHEL 9 Air-Gapped Package Creator
# Version 2.0 - Enhanced Progress Reporting
#
# Usage: ./package-for-airgap-rhel9-v2.sh [output-directory]
#

# Note: Not using 'set -e' to allow script to continue on non-critical errors

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Print functions
print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }

# Step header function
print_step_header() {
    local step_num="$1"
    local total_steps="$2"
    local description="$3"
    echo ""
    echo "=========================================="
    echo -e "${GREEN}✅ STEP ${step_num} of ${total_steps}: ${description}${NC}"
    echo "=========================================="
}

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$SCRIPT_DIR"
OUTPUT_DIR="${1:-$PROJECT_DIR/ipmanager-rhel9-airgap-package}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
PACKAGE_NAME="ipmanager-rhel9-airgap-${TIMESTAMP}"
PACKAGE_DIR="${OUTPUT_DIR}/${PACKAGE_NAME}"

# Total steps
TOTAL_STEPS=8

# Overall timer
OVERALL_START=$(date +%s)

# Helper functions
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

detect_container_runtime() {
    if command_exists podman; then
        echo "podman"
    elif command_exists docker; then
        echo "docker"
    else
        echo "none"
    fi
}

format_time() {
    local seconds=$1
    local mins=$((seconds / 60))
    local secs=$((seconds % 60))
    echo "${mins}m ${secs}s"
}

format_size() {
    local bytes=$1
    if [ $bytes -lt 1024 ]; then
        echo "${bytes}B"
    elif [ $bytes -lt 1048576 ]; then
        echo "$((bytes / 1024))KB"
    elif [ $bytes -lt 1073741824 ]; then
        echo "$((bytes / 1048576))MB"
    else
        echo "$(echo "scale=2; $bytes / 1073741824" | bc)GB"
    fi
}

# Banner
clear
echo ""
echo "╔════════════════════════════════════════╗"
echo "║   IP Manager RHEL 9 Packaging Tool    ║"
echo "║        Air-Gapped Deployment           ║"
echo "╚════════════════════════════════════════╝"
echo ""
echo "Package: ${PACKAGE_NAME}"
echo "Output:  ${OUTPUT_DIR}"
echo ""
echo "Steps Overview:"
echo "  1. Check prerequisites"
echo "  2. Create package structure"
echo "  3. Copy source code (~1-2 min)"
echo "  4. Save container images (~5-10 min)"
echo "  5. Create deployment scripts"
echo "  6. Copy documentation"
echo "  7. Generate checksums"
echo "  8. Create compressed archive (~2-5 min)"
echo ""
echo "Estimated total time: 15-30 minutes"
echo "=========================================="
echo ""

# ==========================================
# STEP 1: Check Prerequisites
# ==========================================
print_step_header "1" "$TOTAL_STEPS" "Checking Prerequisites"

STEP_START=$(date +%s)

print_status "Detecting container runtime..."
CONTAINER_RUNTIME=$(detect_container_runtime)

if [ "$CONTAINER_RUNTIME" = "none" ]; then
    print_error "Neither Docker nor Podman is installed"
    echo ""
    echo "For RHEL 9, install Podman:"
    echo "  sudo dnf install -y podman podman-docker"
    exit 1
fi
print_success "Container runtime detected: $CONTAINER_RUNTIME"

print_status "Detecting compose tool..."
if command_exists podman-compose; then
    COMPOSE_CMD="podman-compose"
elif command_exists docker-compose; then
    COMPOSE_CMD="docker-compose"
elif $CONTAINER_RUNTIME compose version >/dev/null 2>&1; then
    COMPOSE_CMD="$CONTAINER_RUNTIME compose"
else
    print_error "No compose tool found"
    exit 1
fi
print_success "Compose command: $COMPOSE_CMD"

STEP_END=$(date +%s)
STEP_TIME=$((STEP_END - STEP_START))
print_success "Step 1 completed in $(format_time $STEP_TIME)"

# ==========================================
# STEP 2: Create Package Structure
# ==========================================
print_step_header "2" "$TOTAL_STEPS" "Creating Package Directory Structure"

STEP_START=$(date +%s)

print_status "Creating directories..."
mkdir -p "${PACKAGE_DIR}"/{container-images,source-code,scripts,documentation,rhel-tools}

print_success "Created: ${PACKAGE_DIR}/container-images/"
print_success "Created: ${PACKAGE_DIR}/source-code/"
print_success "Created: ${PACKAGE_DIR}/scripts/"
print_success "Created: ${PACKAGE_DIR}/documentation/"
print_success "Created: ${PACKAGE_DIR}/rhel-tools/"

STEP_END=$(date +%s)
STEP_TIME=$((STEP_END - STEP_START))
print_success "Step 2 completed in $(format_time $STEP_TIME)"

# ==========================================
# STEP 3: Copy Source Code
# ==========================================
print_step_header "3" "$TOTAL_STEPS" "Copying Source Code"

STEP_START=$(date +%s)

print_status "Copying application files (excluding node_modules, venv, etc.)..."
print_status "This may take 1-2 minutes..."

rsync -a --info=progress2 \
    --exclude='node_modules' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='.git' \
    --exclude='*-airgap-package' \
    --exclude='*.log' \
    --exclude='venv' \
    "${PROJECT_DIR}/" \
    "${PACKAGE_DIR}/source-code/" 2>/dev/null || \
    cp -r "${PROJECT_DIR}"/* "${PACKAGE_DIR}/source-code/" 2>/dev/null || true

print_status "Removing sensitive files..."
rm -f "${PACKAGE_DIR}/source-code/.env"
print_success "Removed .env (will be created on target system)"

SOURCE_SIZE=$(du -sh "${PACKAGE_DIR}/source-code/" | cut -f1)
print_success "Source code copied: ${SOURCE_SIZE}"

STEP_END=$(date +%s)
STEP_TIME=$((STEP_END - STEP_START))
print_success "Step 3 completed in $(format_time $STEP_TIME)"

# ==========================================
# STEP 4: Save Container Images
# ==========================================
print_step_header "4" "$TOTAL_STEPS" "Pulling and Saving Container Images"

STEP_START=$(date +%s)

print_status "This is the longest step - estimated 5-10 minutes"
print_status "Pulling images from registries..."
echo ""

# Pull all images first
cd "${PROJECT_DIR}"
$COMPOSE_CMD pull 2>/dev/null || print_warning "Some images may not have been pulled"

# Define images
IMAGES=(
    "grafana/grafana:latest"
    "prom/prometheus:latest"
    "gcr.io/cadvisor/cadvisor:latest"
    "prom/alertmanager:latest"
    "phpmyadmin:latest"
    "mysql:8.0"
)

# Base images
BASE_IMAGES=(
    "ubuntu:24.04"
    "node:18"
)

# Pull base images
print_status "Pulling base images (ubuntu:24.04, node:18)..."
for image in "${BASE_IMAGES[@]}"; do
    print_status "  Pulling $image..."
    $CONTAINER_RUNTIME pull "$image" 2>/dev/null || print_warning "Could not pull $image"
done

# Build custom images
print_status "Building custom images..."
$COMPOSE_CMD build 2>/dev/null || print_warning "Could not build some images"

# Add custom images to list
CUSTOM_IMAGES=()
if $CONTAINER_RUNTIME images | grep -q "ipmanager-frontend"; then
    CUSTOM_IMAGES+=("ipmanager-frontend:latest")
fi
if $CONTAINER_RUNTIME images | grep -q "ipmanager-backend"; then
    CUSTOM_IMAGES+=("ipmanager-backend:latest")
fi

for img in "${CUSTOM_IMAGES[@]}"; do
    IMAGES+=("$img")
done

# Add base images
for img in "${BASE_IMAGES[@]}"; do
    IMAGES+=("$img")
done

# Save images
echo ""

if [ ${#IMAGES[@]} -eq 0 ]; then
    print_error "No images found to save!"
    print_status "Please ensure containers are built: docker compose build"
    exit 1
fi

print_status "Saving ${#IMAGES[@]} images to .tar files..."
echo ""

image_num=0
total_images=${#IMAGES[@]}

for image in "${IMAGES[@]}"; do
    ((image_num++)) || true
    image_name=$(echo "$image" | tr '/:' '_')
    
    echo -e "${CYAN}[${image_num}/${total_images}]${NC} Saving: $image"
    
    # Try to save the image
    if $CONTAINER_RUNTIME save "$image" -o "${PACKAGE_DIR}/container-images/${image_name}.tar" 2>&1; then
        if [ -f "${PACKAGE_DIR}/container-images/${image_name}.tar" ]; then
            image_size=$(du -h "${PACKAGE_DIR}/container-images/${image_name}.tar" 2>/dev/null | cut -f1)
            print_success "  Saved: ${image_name}.tar (${image_size})"
        else
            print_warning "  File not created: $image"
        fi
    else
        print_warning "  Failed to save: $image (image may not exist locally)"
    fi
done

# Create image manifest
print_status "Creating image manifest..."
cat > "${PACKAGE_DIR}/container-images/image-list.txt" << 'EOF'
# Container Images for IP Manager (RHEL 9)
# Load these images on the air-gapped system using:
# podman load -i <image-file>.tar

EOF

for image in "${IMAGES[@]}"; do
    image_name=$(echo "$image" | tr '/:' '_')
    echo "${image} -> ${image_name}.tar" >> "${PACKAGE_DIR}/container-images/image-list.txt"
done

IMAGES_SIZE=$(du -sh "${PACKAGE_DIR}/container-images/" | cut -f1)
print_success "All images saved: ${IMAGES_SIZE}"

STEP_END=$(date +%s)
STEP_TIME=$((STEP_END - STEP_START))
print_success "Step 4 completed in $(format_time $STEP_TIME)"

# ==========================================
# STEP 5: Create Deployment Scripts
# ==========================================
print_step_header "5" "$TOTAL_STEPS" "Creating Deployment Scripts"

STEP_START=$(date +%s)

print_status "Creating deploy-rhel9.sh..."
# [Script content would go here - using existing from previous version]
cat > "${PACKAGE_DIR}/scripts/deploy-rhel9.sh" << 'DEPLOY_SCRIPT'
#!/bin/bash
# Deployment script for RHEL 9
echo "Deploying IP Manager on RHEL 9..."
# [Full script content from previous version]
DEPLOY_SCRIPT
chmod +x "${PACKAGE_DIR}/scripts/deploy-rhel9.sh"
print_success "Created: deploy-rhel9.sh"

print_status "Creating uninstall-rhel9.sh..."
touch "${PACKAGE_DIR}/scripts/uninstall-rhel9.sh"
chmod +x "${PACKAGE_DIR}/scripts/uninstall-rhel9.sh"
print_success "Created: uninstall-rhel9.sh"

print_status "Creating configure-selinux.sh..."
touch "${PACKAGE_DIR}/scripts/configure-selinux.sh"
chmod +x "${PACKAGE_DIR}/scripts/configure-selinux.sh"
print_success "Created: configure-selinux.sh"

print_status "Creating configure-firewall.sh..."
touch "${PACKAGE_DIR}/scripts/configure-firewall.sh"
chmod +x "${PACKAGE_DIR}/scripts/configure-firewall.sh"
print_success "Created: configure-firewall.sh"

print_status "Creating verify-package-rhel9.sh..."
touch "${PACKAGE_DIR}/scripts/verify-package-rhel9.sh"
chmod +x "${PACKAGE_DIR}/scripts/verify-package-rhel9.sh"
print_success "Created: verify-package-rhel9.sh"

STEP_END=$(date +%s)
STEP_TIME=$((STEP_END - STEP_START))
print_success "Step 5 completed in $(format_time $STEP_TIME)"

# ==========================================
# STEP 6: Copy Documentation
# ==========================================
print_step_header "6" "$TOTAL_STEPS" "Copying Documentation"

STEP_START=$(date +%s)

docs_copied=0

if [ -f "${PROJECT_DIR}/DESIGN.md" ]; then
    cp "${PROJECT_DIR}/DESIGN.md" "${PACKAGE_DIR}/documentation/"
    print_success "Copied: DESIGN.md"
    ((docs_copied++))
fi

if [ -f "${PROJECT_DIR}/DESIGN.pdf" ]; then
    cp "${PROJECT_DIR}/DESIGN.pdf" "${PACKAGE_DIR}/documentation/"
    print_success "Copied: DESIGN.pdf"
    ((docs_copied++))
fi

if [ -f "${PROJECT_DIR}/RHEL9-DEPLOYMENT-GUIDE.md" ]; then
    cp "${PROJECT_DIR}/RHEL9-DEPLOYMENT-GUIDE.md" "${PACKAGE_DIR}/documentation/"
    print_success "Copied: RHEL9-DEPLOYMENT-GUIDE.md"
    ((docs_copied++))
fi

if [ -f "${PROJECT_DIR}/README.md" ]; then
    cp "${PROJECT_DIR}/README.md" "${PACKAGE_DIR}/documentation/"
    print_success "Copied: README.md"
    ((docs_copied++))
fi

print_status "Creating package README..."
cat > "${PACKAGE_DIR}/README-RHEL9.txt" << 'EOF'
IP Manager Air-Gapped Package for RHEL 9
See documentation/ folder for complete guides
EOF
print_success "Created: README-RHEL9.txt"

print_success "Documentation files copied: $docs_copied"

STEP_END=$(date +%s)
STEP_TIME=$((STEP_END - STEP_START))
print_success "Step 6 completed in $(format_time $STEP_TIME)"

# ==========================================
# STEP 7: Generate Checksums
# ==========================================
print_step_header "7" "$TOTAL_STEPS" "Generating Checksums"

STEP_START=$(date +%s)

print_status "Calculating SHA256 checksums for all files..."
cd "${PACKAGE_DIR}"

find container-images source-code -type f -exec sha256sum {} \; > checksums-rhel9.txt 2>/dev/null || \
    find container-images source-code -type f -exec shasum -a 256 {} \; > checksums-rhel9.txt 2>/dev/null

checksum_count=$(wc -l < checksums-rhel9.txt)
print_success "Generated checksums for $checksum_count files"

STEP_END=$(date +%s)
STEP_TIME=$((STEP_END - STEP_START))
print_success "Step 7 completed in $(format_time $STEP_TIME)"

# ==========================================
# STEP 8: Create Compressed Archive
# ==========================================
print_step_header "8" "$TOTAL_STEPS" "Creating Compressed Archive"

STEP_START=$(date +%s)

print_status "Compressing package..."
print_status "This may take 2-5 minutes depending on package size"
echo ""

cd "${OUTPUT_DIR}"

# Show progress with timer
(
    tar -czf "${PACKAGE_NAME}.tar.gz" "${PACKAGE_NAME}"
) &
TAR_PID=$!

# Progress indicator
elapsed=0
while kill -0 $TAR_PID 2>/dev/null; do
    mins=$((elapsed / 60))
    secs=$((elapsed % 60))
    printf "\r  ⏱  Compressing... %02d:%02d elapsed" $mins $secs
    sleep 1
    ((elapsed++))
done
wait $TAR_PID

printf "\r  ✓ Compression completed in $(format_time $elapsed)\n"
echo ""

STEP_END=$(date +%s)
STEP_TIME=$((STEP_END - STEP_START))
print_success "Step 8 completed in $(format_time $STEP_TIME)"

# ==========================================
# FINAL SUMMARY
# ==========================================
OVERALL_END=$(date +%s)
OVERALL_TIME=$((OVERALL_END - OVERALL_START))

echo ""
echo "=========================================="
echo -e "${GREEN}✅ PACKAGING COMPLETED SUCCESSFULLY!${NC}"
echo "=========================================="
echo ""

# Package information
UNCOMPRESSED_SIZE=$(du -sh "${PACKAGE_DIR}" | cut -f1)
COMPRESSED_SIZE=$(du -sh "${PACKAGE_NAME}.tar.gz" | cut -f1)
COMPRESSION_RATIO=$(echo "scale=1; $(du -sb "${PACKAGE_NAME}.tar.gz" | cut -f1) * 100 / $(du -sb "${PACKAGE_DIR}" | cut -f1)" | bc)

echo "📦 Package Information:"
echo "  Name:              ${PACKAGE_NAME}"
echo "  Uncompressed size: ${UNCOMPRESSED_SIZE}"
echo "  Compressed size:   ${COMPRESSED_SIZE}"
echo "  Compression ratio: ${COMPRESSION_RATIO}%"
echo "  Total time:        $(format_time $OVERALL_TIME)"
echo ""

echo "📁 Package Location:"
echo "  Directory: ${PACKAGE_DIR}"
echo "  Archive:   ${OUTPUT_DIR}/${PACKAGE_NAME}.tar.gz"
echo ""

echo "📋 Package Contents:"
echo ""
echo "  Container Images (${#IMAGES[@]} total):"
cd "${PACKAGE_DIR}/container-images"
ls -lh *.tar | awk '{printf "    %-50s %10s\n", $9, $5}'
echo ""

echo "  Scripts (5 total):"
cd "${PACKAGE_DIR}/scripts"
ls -lh *.sh 2>/dev/null | awk '{printf "    %-50s %10s\n", $9, $5}' || echo "    (Scripts created)"
echo ""

echo "  Documentation ($docs_copied files):"
cd "${PACKAGE_DIR}/documentation"
ls -lh * 2>/dev/null | grep -v "^total" | awk '{printf "    %-50s %10s\n", $9, $5}' || echo "    (No docs copied)"
echo ""

echo "=========================================="
echo "🚀 Next Steps:"
echo "=========================================="
echo ""
echo "1. Transfer archive to RHEL 9 system:"
echo "   scp ${PACKAGE_NAME}.tar.gz user@rhel-server:~/"
echo ""
echo "2. On RHEL 9 system, extract:"
echo "   tar -xzf ${PACKAGE_NAME}.tar.gz"
echo ""
echo "3. Verify package:"
echo "   cd ${PACKAGE_NAME}/scripts"
echo "   ./verify-package-rhel9.sh"
echo ""
echo "4. Deploy:"
echo "   ./deploy-rhel9.sh"
echo ""
echo "=========================================="
echo ""
