#!/bin/bash
#
# Progress-Enhanced Packaging Wrapper - Updated for v2
# This wrapper adds real-time package size monitoring to the v2 script
#

GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }

# Check if v2 script exists
if [ ! -f "./package-for-airgap-rhel9-v2.sh" ]; then
    echo "Error: package-for-airgap-rhel9-v2.sh not found in current directory"
    echo ""
    echo "Please ensure the v2 script is in the same directory:"
    echo "  cp package-for-airgap-rhel9-v2.sh ."
    echo "  chmod +x package-for-airgap-rhel9-v2.sh"
    exit 1
fi

START_TIME=$(date +%s)

echo ""
echo "=========================================="
echo "  IP Manager Packaging Wrapper"
echo "=========================================="
echo ""
print_info "This wrapper adds real-time monitoring to the packaging process"
print_info "The v2 script already includes detailed progress - this adds live stats"
echo ""
read -p "Press Enter to start packaging..."
echo ""

# Monitor package directory size in background
monitor_progress() {
    local base_dir="$1"
    local pkg_pattern="ipmanager-rhel9-airgap-*"
    
    while true; do
        # Find the package directory (it's created by the script)
        pkg_dir=$(find "$base_dir" -maxdepth 2 -type d -name "$pkg_pattern" 2>/dev/null | head -1)
        
        if [ -n "$pkg_dir" ] && [ -d "$pkg_dir" ]; then
            size=$(du -sh "$pkg_dir" 2>/dev/null | cut -f1 2>/dev/null || echo "calculating...")
            elapsed=$(($(date +%s) - START_TIME))
            mins=$((elapsed / 60))
            secs=$((elapsed % 60))
            
            # Count files
            file_count=$(find "$pkg_dir" -type f 2>/dev/null | wc -l || echo "0")
            
            printf "\r${CYAN}📊 Live Stats:${NC} Package: %-10s | Files: %-6s | Time: %02d:%02d  " \
                "$size" "$file_count" "$mins" "$secs"
        else
            elapsed=$(($(date +%s) - START_TIME))
            mins=$((elapsed / 60))
            secs=$((elapsed % 60))
            printf "\r${CYAN}📊 Live Stats:${NC} Initializing... | Time: %02d:%02d  " "$mins" "$secs"
        fi
        sleep 2
    done
}

# Get output directory
OUTPUT_DIR="${1:-./ipmanager-rhel9-airgap-package}"

# Start background monitor
monitor_progress "$OUTPUT_DIR" &
MONITOR_PID=$!

# Trap to kill monitor on exit
trap "kill $MONITOR_PID 2>/dev/null; echo ''" EXIT INT TERM

echo ""
# Run the v2 packaging script
./package-for-airgap-rhel9-v2.sh "$@"
RESULT=$?

# Kill monitor
kill $MONITOR_PID 2>/dev/null
wait $MONITOR_PID 2>/dev/null

# Clear the monitor line
echo ""

# Additional summary if successful
if [ $RESULT -eq 0 ]; then
    TOTAL_TIME=$(($(date +%s) - START_TIME))
    MINS=$((TOTAL_TIME / 60))
    SECS=$((TOTAL_TIME % 60))
    
    echo ""
    echo "=========================================="
    echo -e "${GREEN}✅ WRAPPER: Additional Statistics${NC}"
    echo "=========================================="
    echo ""
    echo "  Total execution time: ${MINS}m ${SECS}s"
    
    # Find the package directory
    PKG_DIR=$(find "$OUTPUT_DIR" -maxdepth 2 -type d -name "ipmanager-rhel9-airgap-*" 2>/dev/null | head -1)
    
    if [ -n "$PKG_DIR" ]; then
        echo "  Package directory:"
        echo "    Location: $PKG_DIR"
        
        # Count different file types
        IMG_COUNT=$(find "$PKG_DIR/container-images" -name "*.tar" 2>/dev/null | wc -l)
        SCRIPT_COUNT=$(find "$PKG_DIR/scripts" -name "*.sh" 2>/dev/null | wc -l)
        DOC_COUNT=$(find "$PKG_DIR/documentation" -type f 2>/dev/null | wc -l)
        
        echo "    Container images: $IMG_COUNT"
        echo "    Scripts: $SCRIPT_COUNT"
        echo "    Documentation files: $DOC_COUNT"
        
        # Find archive
        ARCHIVE=$(find "$OUTPUT_DIR" -name "*.tar.gz" -type f 2>/dev/null | head -1)
        if [ -n "$ARCHIVE" ]; then
            echo ""
            echo "  Archive ready for transfer:"
            echo "    $(basename "$ARCHIVE")"
            echo "    $(du -h "$ARCHIVE" | cut -f1)"
        fi
    fi
    
    echo ""
    echo "=========================================="
    echo ""
fi

exit $RESULT
