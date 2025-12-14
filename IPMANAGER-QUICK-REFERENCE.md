# IP Manager Quick Reference Card

**System:** Ubuntu Server 192.168.0.199:/home/ubuntu/ipmanager  
**Version:** 2.0  
**Updated:** December 14, 2024

---

## 🚀 Quick Access URLs

| Service | URL | Login |
|---------|-----|-------|
| **IP Manager** | http://192.168.0.199:3000 | - |
| **API Docs** | http://192.168.0.199:8000/docs | - |
| **phpMyAdmin** | http://192.168.0.199:8080 | root / ipmanager_root_2024 |
| **Prometheus** | http://192.168.0.199:9090 | - |
| **Grafana** | http://192.168.0.199:3001 | admin / admin |
| **Alertmanager** | http://192.168.0.199:9093 | - |

---

## 🐳 Container Management

### View Status
```bash
cd /home/ubuntu/ipmanager
docker ps                    # Running containers
docker compose ps            # Compose stack status
```

### Start/Stop All
```bash
docker compose up -d         # Start all
docker compose down          # Stop all
docker compose restart       # Restart all
```

### Restart Individual Container
```bash
docker compose restart backend
docker compose restart frontend
docker compose restart mysql
docker compose restart prometheus
docker compose restart grafana
```

### View Logs
```bash
docker compose logs -f                    # All containers
docker logs ipam-backend --tail 100 -f    # Backend only
docker logs ipam-frontend -f              # Frontend only
docker logs prometheus -f                 # Prometheus only
```

---

## 🔧 Common Operations

### After System Reboot
```bash
cd /home/ubuntu/ipmanager
docker compose down
docker compose up -d
```
*Note: Should auto-start with `restart: unless-stopped` policy*

### Update Backend Code
```bash
cd /home/ubuntu/ipmanager
docker compose up -d --build backend
docker compose restart backend
```

### Update Frontend Code
```bash
cd /home/ubuntu/ipmanager
docker compose up -d --build frontend
docker compose restart frontend
```

### Database Backup
```bash
docker exec ipam-mysql mysqldump -uipmanager -pipmanager_pass_2024 ipmanager > backup-$(date +%Y%m%d).sql
```

### Database Restore
```bash
docker exec -i ipam-mysql mysql -uipmanager -pipmanager_pass_2024 ipmanager < backup.sql
```

---

## 📊 Monitoring Operations

### Add VM to Monitoring
```bash
# Edit target file
nano /home/ubuntu/ipmanager/monitoring/prometheus/targets/nodes.yml

# Add entry:
- targets:
    - '192.168.0.XX:9100'
  labels:
    job: 'node_exporter'

# Reload Prometheus (no restart needed)
curl -X POST http://192.168.0.199:9090/-/reload
```

### View Prometheus Targets
```bash
curl http://192.168.0.199:9090/api/v1/targets | jq .
```

### Check Grafana Datasource
```bash
curl -u admin:admin http://192.168.0.199:3001/api/datasources
```

---

## 🛠️ Troubleshooting

### Container Not Starting
```bash
docker compose ps -a                      # Check status
docker logs <container-name> --tail 50    # Check logs
docker compose down                       # Clean stop
docker compose up -d --force-recreate     # Force recreate
```

### Network Scan Not Working
```bash
# Verify backend network mode
docker inspect ipam-backend | grep NetworkMode
# Should show: "NetworkMode": "host"

# Test ICMP from backend
docker exec ipam-backend ping -c 3 192.168.0.1

# Restart backend
docker compose restart backend
```

### Database Connection Issues
```bash
# Check MySQL health
docker exec ipam-mysql mysqladmin ping -h localhost

# Test from backend
docker exec ipam-backend nc -zv 127.0.0.1 3306

# Restart MySQL
docker compose restart mysql
```

### Prometheus Not Scraping
```bash
# Check target config
cat /home/ubuntu/ipmanager/monitoring/prometheus/targets/nodes.yml

# Test from Prometheus container
docker exec prometheus wget -O- http://192.168.0.32:9100/metrics

# Check VM node_exporter
ssh ubuntu@192.168.0.32 "systemctl status node_exporter"
```

---

## 🔐 Security

### SSH to Ubuntu Server
```bash
ssh ubuntu@192.168.0.199
```

### Access Container Shell
```bash
docker exec -it ipam-backend bash
docker exec -it ipam-frontend bash
docker exec -it ipam-mysql bash
```

### MySQL Console
```bash
docker exec -it ipam-mysql mysql -uipmanager -pipmanager_pass_2024 ipmanager
```

---

## 📁 Important Files

| File | Purpose |
|------|---------|
| `/home/ubuntu/ipmanager/docker-compose.yml` | Container orchestration |
| `/home/ubuntu/ipmanager/.env` | Proxmox password |
| `/home/ubuntu/ipmanager/backend/main.py` | Backend API code |
| `/home/ubuntu/ipmanager/frontend/src/App.js` | Frontend UI code |
| `/home/ubuntu/ipmanager/monitoring/prometheus/prometheus.yml` | Prometheus config |
| `/home/ubuntu/ipmanager/monitoring/prometheus/targets/nodes.yml` | VM monitoring targets |

---

## 🚨 Emergency Procedures

### Complete System Reset
```bash
cd /home/ubuntu/ipmanager

# Stop everything
docker compose down

# Remove all containers and volumes
docker compose down -v

# Start fresh
docker compose up -d

# Check status
docker compose ps
```

### Check All Services Health
```bash
# Quick health check script
curl -s http://localhost:3000 > /dev/null && echo "✓ Frontend OK" || echo "✗ Frontend DOWN"
curl -s http://localhost:8000/docs > /dev/null && echo "✓ Backend OK" || echo "✗ Backend DOWN"
curl -s http://localhost:9090 > /dev/null && echo "✓ Prometheus OK" || echo "✗ Prometheus DOWN"
curl -s http://localhost:3001 > /dev/null && echo "✓ Grafana OK" || echo "✗ Grafana DOWN"
docker exec ipam-mysql mysqladmin ping -h localhost && echo "✓ MySQL OK" || echo "✗ MySQL DOWN"
```

---

## 📝 Common Tasks Checklist

### Daily
- [ ] Check container status: `docker ps`
- [ ] Review error logs: `docker compose logs | grep ERROR`

### Weekly
- [ ] Backup database
- [ ] Check disk usage: `df -h`
- [ ] Review Grafana dashboards

### Monthly
- [ ] Update Docker images: `docker compose pull`
- [ ] Clean old logs: `docker system prune -f`
- [ ] System updates: `apt update && apt upgrade`

---

## 🎯 Performance Tips

### Free Up Disk Space
```bash
# Remove unused Docker resources
docker system prune -a

# Remove old backups
find /backup -name "*.sql" -mtime +30 -delete
```

### Check Resource Usage
```bash
# Container resources
docker stats

# System resources
htop
df -h
free -h
```

---

## 📞 Support Information

**Documentation:** `/mnt/user-data/outputs/IPMANAGER-DESIGN-DOCUMENT.md`  
**Logs Location:** `docker compose logs`  
**Backup Location:** `/backup/ipmanager/`  

**Container Names:**
- ipam-mysql
- ipam-backend
- ipam-frontend
- phpmyadmin
- prometheus
- grafana
- alertmanager

---

**Keep this card handy for quick reference!**
