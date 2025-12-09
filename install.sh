#!/bin/bash
# IP Manager Installation Script for Ubuntu 24.04
# Run with: sudo bash install.sh

set -e

echo "================================================"
echo "IP Manager Installation Script"
echo "Ubuntu 24.04.3"
echo "================================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root: sudo bash install.sh"
    exit 1
fi

# Get the actual user (not root)
ACTUAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(eval echo ~$ACTUAL_USER)

echo "[1/7] Updating system packages..."
apt update
apt upgrade -y

echo ""
echo "[2/7] Installing Docker..."
apt install -y docker.io docker-compose

echo ""
echo "[3/7] Installing nmap..."
apt install -y nmap

echo ""
echo "[4/7] Configuring Docker permissions..."
usermod -aG docker $ACTUAL_USER
systemctl enable docker
systemctl start docker

echo ""
echo "[5/7] Installing Python dependencies..."
apt install -y python3 python3-pip python3-venv

echo ""
echo "[6/7] Creating installation directory..."
INSTALL_DIR="$USER_HOME/ipmanager"
mkdir -p $INSTALL_DIR
chown -R $ACTUAL_USER:$ACTUAL_USER $INSTALL_DIR

echo ""
echo "[7/7] Setting up project files..."
# Files will be copied from the package

echo ""
echo "================================================"
echo "✓ Installation Complete!"
echo "================================================"
echo ""
echo "Next steps:"
echo "1. Log out and log back in (for Docker group)"
echo "2. cd ~/ipmanager"
echo "3. bash start.sh"
echo ""
echo "Access the IP Manager at: http://$(hostname -I | awk '{print $1}'):3000"
echo "================================================"
