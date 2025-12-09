# IP Manager - Ubuntu Installation Package

Network IP Address Manager with nmap scanning for Ubuntu 24.04.3

## Quick Install

**1. Extract the package:**
```bash
tar -xzf ipmanager-ubuntu.tar.gz
cd ipmanager
```

**2. Run installation:**
```bash
sudo bash install.sh
```

**3. Log out and log back in** (required for Docker group)

**4. Start the IP Manager:**
```bash
cd ~/ipmanager
bash start.sh
```

**5. Access from any device on your network:**
- Find Ubuntu laptop IP: `hostname -I`
- Open browser: `http://<ubuntu-ip>:3000`
- Example: `http://192.168.1.100:3000`

## Usage

### Start IP Manager
```bash
cd ~/ipmanager
bash start.sh
```

### Stop IP Manager  
```bash
bash stop.sh
```

### View Logs
```bash
docker compose logs -f
```

### Check Status
```bash
docker compose ps
```

## Scanning Your Network

1. Open `http://<ubuntu-laptop-ip>:3000` in browser
2. Enter subnet (e.g., `192.168.1`)
3. Set IP range (e.g., `0` to `255`)
4. Click **"Start Scan"**
5. View active/inactive devices with:
   - IP addresses
   - Hostnames
   - MAC addresses
   - Vendor information

## Features

- ✅ Real nmap scanning (accurate detection)
- ✅ MAC address and vendor identification
- ✅ Hostname resolution
- ✅ Fast concurrent scanning
- ✅ Works on host network (192.168.1.x)
- ✅ Web-based interface
- ✅ Auto-reload on code changes

## Network Configuration

The IP Manager uses `network_mode: host` which means:
- Containers share the Ubuntu laptop's network
- Direct access to 192.168.1.x network
- nmap can scan the actual network
- No Docker networking issues

## Troubleshooting

**Can't access from Windows:**
```bash
# Check Ubuntu firewall
sudo ufw status

# Allow ports if needed
sudo ufw allow 3000
sudo ufw allow 8000
```

**Services won't start:**
```bash
# Check Docker
sudo systemctl status docker

# Restart Docker
sudo systemctl restart docker
```

**Permission denied:**
```bash
# Make sure you're in docker group
groups | grep docker

# If not, run install.sh again
sudo bash install.sh
```

## File Structure

```
~/ipmanager/
├── docker-compose.yml    # Container configuration
├── start.sh             # Start script
├── stop.sh              # Stop script
├── backend/
│   ├── Dockerfile
│   ├── main.py          # FastAPI + nmap
│   └── requirements.txt
└── frontend/
    ├── Dockerfile
    ├── package.json
    ├── public/
    └── src/
        └── App.js       # React interface
```

## Requirements

- Ubuntu 24.04.3
- 4GB RAM minimum
- Network connection to scan subnet
- Bridged or host network (not NAT)

## Security Notes

- IP Manager requires privileged mode for nmap
- Only use on trusted networks
- Change default ports if needed
- Consider adding authentication for production

## Access from Windows

1. Find Ubuntu laptop IP: `hostname -I` on Ubuntu
2. Open browser on Windows
3. Navigate to: `http://192.168.1.XXX:3000`
4. Start scanning your network!

## Support

For issues:
1. Check logs: `docker compose logs`
2. Verify network: `ip addr show`
3. Test nmap: `nmap -sn 192.168.1.1`
4. Check Docker: `docker ps`
