# phpMyAdmin Setup Guide

## 📊 Add phpMyAdmin to IP Manager

phpMyAdmin provides a web-based interface to view and manage your MySQL database.

### Benefits

✅ **Visual Database Management**
- Browse tables and data
- Run SQL queries easily
- Export data (CSV, SQL, Excel)
- Edit records directly
- View table structures
- Monitor database size

✅ **Development & Debugging**
- Test SQL queries
- View scan history
- Check node tracking
- Debug reservation issues
- Analyze usage patterns

✅ **Reporting**
- Export node lists
- Generate reports
- Create custom queries
- Track historical data

## 🚀 Installation

### Step 1: Update docker-compose.yml

Replace your current `docker-compose.yml` with the new version that includes phpMyAdmin.

**Download:** [docker-compose.yml with phpMyAdmin](computer:///mnt/user-data/outputs/docker-compose-phpmyadmin.yml)

Or manually add this service to your existing docker-compose.yml:

```yaml
  phpmyadmin:
    image: phpmyadmin:latest
    container_name: ipam-phpmyadmin
    restart: unless-stopped
    depends_on:
      - mysql
    environment:
      PMA_HOST: mysql
      PMA_PORT: 3306
      PMA_USER: ipmanager
      PMA_PASSWORD: ipmanager_pass_2024
      MYSQL_ROOT_PASSWORD: ipmanager_root_2024
      PMA_ABSOLUTE_URI: http://localhost:8080
    ports:
      - "8080:80"
```

### Step 2: Start phpMyAdmin

```bash
cd ~/ipmanager

# Start phpMyAdmin
docker compose up -d phpmyadmin

# Check status
docker compose ps

# Should see ipam-phpmyadmin running
```

### Step 3: Access phpMyAdmin

**From Ubuntu laptop:**
```
http://localhost:8080
```

**From Windows/other device on network:**
```
http://<ubuntu-ip>:8080
```

Example: `http://192.168.1.100:8080`

### Step 4: Login

**Credentials:**
- **Server:** mysql
- **Username:** ipmanager
- **Password:** ipmanager_pass_2024

Or login as root:
- **Username:** root
- **Password:** ipmanager_root_2024

## 📋 Common Tasks

### View All Nodes

1. Click **ipmanager** database (left sidebar)
2. Click **nodes** table
3. Click **Browse** tab
4. See all IP addresses and their info

### Find Active Devices

Click **SQL** tab and run:

```sql
SELECT ip_address, hostname, vendor, mac_address, last_seen 
FROM nodes 
WHERE status = 'up' 
ORDER BY last_seen DESC;
```

### Find Previously Used IPs

```sql
SELECT ip_address, hostname, vendor, last_seen, times_seen
FROM nodes 
WHERE status = 'previously_used' 
ORDER BY last_seen DESC;
```

### Find Reserved IPs

```sql
SELECT ip_address, notes, reserved_by, reserved_at
FROM nodes 
WHERE status = 'reserved'
ORDER BY reserved_at DESC;
```

### View Scan History

```sql
SELECT subnet, start_ip, end_ip, active_ips, total_ips, 
       ROUND(scan_duration, 2) as duration_sec,
       scanned_at
FROM scan_history 
ORDER BY scanned_at DESC 
LIMIT 20;
```

### Export All Nodes to CSV

1. Go to **nodes** table
2. Click **Export** tab
3. Choose format: **CSV**
4. Click **Go**

### Search for Specific Vendor

```sql
SELECT ip_address, hostname, vendor, mac_address, status
FROM nodes 
WHERE vendor LIKE '%Apple%'
ORDER BY ip_address;
```

### Get Network Statistics

```sql
SELECT 
    status,
    COUNT(*) as count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM nodes), 2) as percentage
FROM nodes
GROUP BY status;
```

### Find IPs with Notes

```sql
SELECT ip_address, notes, status, last_seen
FROM nodes 
WHERE notes IS NOT NULL AND notes != ''
ORDER BY last_seen DESC;
```

### Device Connection History

```sql
SELECT n.ip_address, n.hostname, n.vendor,
       COUNT(h.id) as connection_count,
       MIN(h.recorded_at) as first_connection,
       MAX(h.recorded_at) as last_connection
FROM nodes n
LEFT JOIN node_history h ON n.id = h.node_id
GROUP BY n.ip_address
HAVING connection_count > 1
ORDER BY connection_count DESC;
```

## 🔒 Security Considerations

### Production Deployment

For production use, you should:

1. **Change Default Passwords**
```yaml
environment:
  MYSQL_ROOT_PASSWORD: your_secure_root_password
  MYSQL_PASSWORD: your_secure_user_password
```

2. **Restrict Access**

Add firewall rule to only allow specific IPs:

```bash
# Only allow access from specific IP
sudo ufw allow from 192.168.1.50 to any port 8080

# Or only localhost
# Change ports mapping in docker-compose.yml:
ports:
  - "127.0.0.1:8080:80"
```

3. **Use HTTPS** (for production)

Set up reverse proxy with SSL:
```bash
# Install nginx
sudo apt install nginx

# Configure with Let's Encrypt SSL
# Point to phpMyAdmin container
```

4. **Enable 2FA** (optional)

phpMyAdmin supports two-factor authentication. Configure in phpMyAdmin settings.

### Development (Current Setup)

Current setup is fine for:
- Internal network use
- Development/testing
- Home lab environments
- Trusted network segments

## 🎯 Useful phpMyAdmin Features

### Structure View
- See table columns
- View indexes
- Check foreign keys
- Analyze table size

### SQL Query Builder
- Visual query builder
- No SQL knowledge needed
- Generate queries automatically

### Operations
- Optimize tables
- Repair tables
- Check table integrity
- Change table settings

### Import/Export
- Backup database
- Restore backups
- Export specific tables
- Import CSV data

### User Management
- Create new users (as root)
- Set permissions
- Manage access rights

## 🐛 Troubleshooting

### Can't Access phpMyAdmin

```bash
# Check if running
docker compose ps

# Check logs
docker compose logs phpmyadmin

# Restart
docker compose restart phpmyadmin
```

### Connection Refused

```bash
# Make sure MySQL is running
docker compose ps mysql

# Check MySQL logs
docker compose logs mysql --tail 30
```

### Wrong Credentials

Double-check your docker-compose.yml environment variables match the login credentials.

### Port 8080 Already in Use

Change the port mapping in docker-compose.yml:
```yaml
ports:
  - "8081:80"  # Use 8081 instead
```

Then access at `http://<ip>:8081`

## 📊 Performance Monitoring

### Database Size

**SQL tab:**
```sql
SELECT 
    table_name,
    ROUND(((data_length + index_length) / 1024 / 1024), 2) AS size_mb
FROM information_schema.TABLES 
WHERE table_schema = 'ipmanager'
ORDER BY size_mb DESC;
```

### Row Counts

```sql
SELECT 
    table_name,
    table_rows
FROM information_schema.TABLES 
WHERE table_schema = 'ipmanager';
```

### Most Active IPs

```sql
SELECT 
    ip_address,
    hostname,
    vendor,
    times_seen,
    last_seen
FROM nodes
ORDER BY times_seen DESC
LIMIT 20;
```

## 🎓 Learning Resources

- **phpMyAdmin Docs:** https://docs.phpmyadmin.net/
- **SQL Tutorial:** https://www.w3schools.com/sql/
- **MySQL Reference:** https://dev.mysql.com/doc/

## 🔗 Quick Links

After setup, bookmark these:

- **IP Manager:** http://<ubuntu-ip>:3000
- **API Docs:** http://<ubuntu-ip>:8000/docs
- **phpMyAdmin:** http://<ubuntu-ip>:8080

---

**Pro Tip:** Use phpMyAdmin to create custom SQL views for reporting, analyze network trends, and maintain your IP database efficiently! 📊
