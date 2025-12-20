#!/bin/bash
#
# Quick test to verify docker save command works
#

echo "Testing docker save command..."
echo ""

# Test with a small image
TEST_IMAGE="mysql:8.0"
TEST_OUTPUT="/tmp/test-mysql.tar"

echo "1. Checking if image exists..."
if docker images "$TEST_IMAGE" --format "{{.Repository}}:{{.Tag}}" | grep -q .; then
    echo "   ✓ Image found: $TEST_IMAGE"
else
    echo "   ✗ Image NOT found: $TEST_IMAGE"
    echo "   Please pull it first: docker pull $TEST_IMAGE"
    exit 1
fi

echo ""
echo "2. Testing docker save..."
echo "   Command: docker save $TEST_IMAGE -o $TEST_OUTPUT"
echo ""

if docker save "$TEST_IMAGE" -o "$TEST_OUTPUT" 2>&1; then
    echo ""
    if [ -f "$TEST_OUTPUT" ]; then
        SIZE=$(du -h "$TEST_OUTPUT" | cut -f1)
        echo "   ✓ SUCCESS! File created: $TEST_OUTPUT ($SIZE)"
        rm -f "$TEST_OUTPUT"
        echo "   ✓ Test file cleaned up"
    else
        echo "   ✗ FAILED! File was not created"
        exit 1
    fi
else
    echo ""
    echo "   ✗ FAILED! Docker save command failed"
    exit 1
fi

echo ""
echo "=========================================="
echo "✓ Docker save command works correctly!"
echo "=========================================="
