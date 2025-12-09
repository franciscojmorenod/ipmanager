# IP Manager v2.0 - MySQL Upgrade Guide

## 🆕 New Features

### Node History Tracking
- **Previously Used Status**: IPs that were active before but are now offline show in YELLOW
- **Persistent Storage**: All node information saved to MySQL database
- **History Tracking**: See when devices were first/last seen and how many times detected

### IP Reservation System
- **Reserve IPs**: Click any cell and reserve it for future use
- **Reservation Details**: Add description, reserved for, and reserved by info
- **Release IPs**: Unreserve IPs when no longer needed
- **Visual Indicator**: Reserved IPs show with 🔒 icon in PURPLE

### Enhanced Status Colors
- 🟢 **Green** - Active (currently online)
- ⚪ **Grey** - Available (never used)
- 🟡 **Yellow** - Previously Used (was online, now offline)
- 🟣 **Purple** - Reserved (locked for specific device)

## 📦 Installation

**Download:** [ipmanager-mysql.tar.gz](computer:///mnt/user-data/outputs/ipmanager-mysql.tar.gz)

### Step 1: Backup Current Installation

```bash
cd ~/ipmanager
docker compose down

# Backup current files
cp -r ~/ipmanager ~/ipmanager-backup
```

### Step 2: Extract New Version

```bash
cd ~
tar -xzf ipmanager-mysql.tar.gz
cd mysql-setup

# Copy files to ipmanager directory
cp docker-compose.yml ~/ipmanager/
mkdir -p ~/ipmanager/mysql
cp init.sql ~/ipmanager/mysql/
cp main.py ~/ipmanager/backend/
cp requirements.txt ~/ipmanager/backend/
cp App.js ~/ipmanager/frontend/src/
cp App-complete.css ~/ipmanager/frontend/src/App.css
```

### Step 3: Start Services

```bash
cd ~/ipmanager

# Start MySQL first (it takes ~30 seconds to initialize)
docker compose up -d mysql

# Wait for MySQL to be ready
echo "Waiting for MySQL to start..."
sleep 30

# Start all services
docker compose up -d

# Check status
docker compose ps
```

### Step 4: Verify Installation

```bash
# Check logs
docker compose logs mysql | tail -20
docker compose logs ipam-backend | tail -20

# Get your IP
hostname -I
```

Open browser: `http://<ubuntu-ip>:3000`

## 🎯 How to Use New Features

### Viewing Node History

1. Click any cell in the grid
2. Modal shows detailed information:
   - Current status
   - Hostname, MAC, Vendor
   - First seen date
   - Last seen date
   - Times detected

### Reserving an IP

1. Click a cell (works for any status except already reserved)
2. Click **"🔒 Reserve IP"** button in modal
3. Fill in reservation form:
   - **Reserved For**: Device name or purpose (required)
   - **Description**: Additional notes
   - **Reserved By**: Your name or team
4. Click **"Confirm Reservation"**
5. IP now shows in PURPLE with lock icon

### Releasing a Reserved IP

1. Click reserved IP cell (purple)
2. Click **"🔓 Release IP"** button
3. Confirm release
4. IP returns to available status

### Understanding "Previously Used" Status

- Device was active in a past scan
- Device is currently offline
- Shows in YELLOW to indicate "this IP was used before"
- Helps identify which IPs to avoid when assigning new devices
- You can still reserve previously-used IPs for the same device

## 📊 Database Structure

### Tables Created

**nodes** - Main IP tracking table
- IP address, subnet, status
- Hostname, MAC, vendor
- First seen, last seen, times seen
- Reservation info, notes

**scan_history** - Scan records
- Subnet, IP range
- Active IPs count, scan duration
- Timestamp

**ip_reservations** - Reservation tracking
- IP address, reserved for, description
- Reserved by, timestamp
- Expiration (future feature)

**node_history** - Historical snapshots
- Node state changes over time
- Status transitions
- Device information changes

## 🔧 API Endpoints

### New Endpoints

```
POST /api/reserve
Body: {
  "ip": "192.168.1.100",
  "reserved_for": "Server",
  "description": "Production web server",
  "reserved_by": "IT Team"
}

POST /api/release/{ip}
Releases a reserved IP

GET /api/node/{ip}
Get detailed node info with history

PUT /api/node/update
Body: {
  "ip": "192.168.1.100",
  "notes": "Custom notes",
  "is_reserved": true
}
```

## 🗄️ Database Access

### Connect to MySQL

```bash
docker exec -it ipam-mysql mysql -u ipmanager -pipmanager_pass_2024 ipmanager
```

### Useful Queries

```sql
-- See all nodes
SELECT ip_address, status, vendor, last_seen FROM nodes ORDER BY last_seen DESC;

-- Count by status
SELECT status, COUNT(*) FROM nodes GROUP BY status;

-- Recently active devices
SELECT ip_address, hostname, vendor, last_seen 
FROM nodes 
WHERE status = 'up' 
ORDER BY last_seen DESC;

-- Previously used but now offline
SELECT ip_address, hostname, vendor, last_seen 
FROM nodes 
WHERE status = 'previously_used' 
ORDER BY last_seen DESC;

-- Reserved IPs
SELECT ip_address, notes, reserved_by, reserved_at 
FROM nodes 
WHERE status = 'reserved';

-- Scan history
SELECT * FROM scan_history ORDER BY scanned_at DESC LIMIT 10;
```

## 🎨 Visual Changes

### New Color Scheme

- **Active (Green)**: Bright green gradient - device is online NOW
- **Available (Grey)**: Subtle grey - never been used
- **Previously Used (Yellow/Orange)**: Warm yellow - was online, now offline
- **Reserved (Purple)**: Purple gradient with lock icon

### New UI Elements

- **Legend Bar**: Shows what each color means
- **Stats Cards**: Now includes "Previously Used" and "Reserved" counts
- **Filter Buttons**: Filter by status including "Previously Used"
- **Reservation Modal**: Form for reserving IPs
- **Enhanced Details Modal**: Shows history and reservation info

## 🔒 Security Notes

### Database Credentials

Default credentials in docker-compose.yml:
```
MYSQL_ROOT_PASSWORD: ipmanager_root_2024
MYSQL_USER: ipmanager
MYSQL_PASSWORD: ipmanager_pass_2024
```

**For production, change these!**

Edit docker-compose.yml before first start:
```yaml
environment:
  MYSQL_ROOT_PASSWORD: your_secure_password
  MYSQL_PASSWORD: your_secure_password
```

## 🐛 Troubleshooting

### MySQL won't start

```bash
# Check logs
docker compose logs mysql

# Remove old data and restart
docker compose down -v
docker compose up -d
```

### Backend can't connect to MySQL

```bash
# Check MySQL is ready
docker compose ps

# Check backend logs
docker compose logs ipam-backend

# Restart backend
docker compose restart ipam-backend
```

### Old data not showing

This is a fresh database. Previous scan data won't appear until you run new scans. The database will build history over time.

## 📈 Benefits

### Why MySQL?

1. **Persistent History**: Data survives container restarts
2. **Track Changes**: See device connection patterns over time
3. **IP Planning**: Identify which IPs are truly free vs. temporarily offline
4. **Reservations**: Prevent IP conflicts by reserving addresses
5. **Reporting**: Query database for network usage reports
6. **Scalability**: Handle large networks efficiently

### Use Cases

- **DHCP Planning**: Reserve static IPs, see which are truly free
- **Device Tracking**: Monitor when devices come and go
- **Network Auditing**: Historical records of all devices
- **IP Assignment**: Avoid assigning IPs that are temporarily offline
- **Documentation**: Notes and descriptions for each IP

## 🎯 Next Steps

After installation:

1. **Run Initial Scan**: Scan your full network to populate database
2. **Reserve Important IPs**: Mark gateway, servers, printers as reserved
3. **Add Notes**: Click devices and add descriptions/notes
4. **Monitor Over Time**: Run periodic scans to build history
5. **Use Filters**: View different status categories

Enjoy the enhanced IP Manager! 🚀
