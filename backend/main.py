"""
FastAPI Backend for IP Manager with MySQL persistence
Tracks node history and allows IP reassignment
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, validator
#from typing import List, Optional
import nmap
import asyncio
from datetime import datetime
import mysql.connector
from mysql.connector import pooling

import os
import subprocess
import re
from pathlib import Path

import paramiko
import json
import time
import uuid
from typing import List, Optional, Dict
from datetime import datetime
import yaml
import threading


app = FastAPI(title="IP Manager API", version="2.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# MySQL connection pool
db_config = {
    "host": os.getenv("MYSQL_HOST", "localhost"),
    "port": int(os.getenv("MYSQL_PORT", 3306)),
    "user": os.getenv("MYSQL_USER", "ipmanager"),
    "password": os.getenv("MYSQL_PASSWORD", "ipmanager_pass_2024"),
    "database": os.getenv("MYSQL_DATABASE", "ipmanager"),
    "pool_name": "ipmanager_pool",
    "pool_size": 10
}

try:
    connection_pool = pooling.MySQLConnectionPool(**db_config)
    print("✓ MySQL connection pool created successfully")
except Exception as e:
    print(f"✗ Failed to create MySQL pool: {e}")
    connection_pool = None

def get_db_connection():
    """Get a database connection from the pool"""
    if connection_pool:
        return connection_pool.get_connection()
    return None

class ScanRequest(BaseModel):
    subnet: str
    start_ip: int = 0
    end_ip: int = 255
    
    @validator("start_ip", "end_ip")
    def validate_ip_range(cls, v):
        if not 0 <= v <= 255:
            raise ValueError("IP must be 0-255")
        return v
    
    @validator("subnet")
    def validate_subnet(cls, v):
        parts = v.split(".")
        if len(parts) != 3:
            raise ValueError("Subnet must be x.x.x")
        return v

class IPStatus(BaseModel):
    ip: str
    status: str  # 'up', 'down', 'previously_used', 'reserved'
    hostname: Optional[str] = None
    mac_address: Optional[str] = None
    vendor: Optional[str] = None
    open_ports: List[int] = []
    last_scanned: str
    first_seen: Optional[str] = None
    last_seen: Optional[str] = None
    times_seen: int = 0
    notes: Optional[str] = None
    is_reserved: bool = False

class ReserveIPRequest(BaseModel):
    ip: str
    reserved_for: str
    description: Optional[str] = None
    reserved_by: Optional[str] = None

class UpdateNodeRequest(BaseModel):
    ip: str
    notes: Optional[str] = None
    is_reserved: Optional[bool] = None

class ScanResponse(BaseModel):
    subnet: str
    total_ips: int
    active_ips: int
    inactive_ips: int
    previously_used_ips: int
    reserved_ips: int
    scan_time: float
    results: List[IPStatus]


# =============================================0

def add_prometheus_target(ip_address: str):
    """Add a new VM to Prometheus targets"""
    targets_file = Path("/app/monitoring/prometheus/targets/nodes.yml")
    
    try:
        # Read existing targets
        if targets_file.exists():
            with open(targets_file, 'r') as f:
                data = yaml.safe_load(f) or []
        else:
            data = []
        
        # Ensure we have the right structure
        if not data:
            data = [{
                'targets': [],
                'labels': {
                    'job': 'node_exporter',
                    'environment': 'production'
                }
            }]
        
        # Add new target if not already present
        new_target = f"{ip_address}:9100"
        if new_target not in data[0]['targets']:
            data[0]['targets'].append(new_target)
            data[0]['targets'].sort()  # Keep sorted
            
            # Write back to file
            with open(targets_file, 'w') as f:
                yaml.dump(data, f, default_flow_style=False, sort_keys=False)
            
            # Reload Prometheus
            try:
                import requests
                requests.post('http://localhost:9090/-/reload', timeout=5)
                print(f"✓ Added {ip_address} to Prometheus targets and reloaded")
            except Exception as e:
                print(f"⚠ Added target but couldn't reload Prometheus: {e}")
            
            return True
        else:
            print(f"Target {ip_address} already exists in Prometheus")
            return False
            
    except Exception as e:
        print(f"Failed to add Prometheus target: {e}")
        return False


# =============================================1
def update_or_create_node(conn, ip_address, subnet, last_octet, status, hostname=None, mac=None, vendor=None):
    """Update existing node or create new one"""
    cursor = conn.cursor(dictionary=True)

    # Check if node exists
    cursor.execute("SELECT * FROM nodes WHERE ip_address = %s", (ip_address,))
    existing = cursor.fetchone()
    
    if existing:
        # Node exists - update it
        if status == 'up':
            # Device is back online
            cursor.execute("""
                UPDATE nodes 
                SET status = %s, hostname = %s, mac_address = %s, vendor = %s,
                    last_seen = NOW(), last_scanned = NOW(), times_seen = times_seen + 1
                WHERE ip_address = %s
            """, (status, hostname, mac, vendor, ip_address))
            
            # Record in history
            cursor.execute("""
                INSERT INTO node_history (node_id, ip_address, status, hostname, mac_address, vendor)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, (existing['id'], ip_address, status, hostname, mac, vendor))
        else:
            # Device is offline
            # Only mark as 'previously_used' if it was ACTUALLY online before (status was 'up')
            if existing['status'] == 'up':
                cursor.execute("""
                    UPDATE nodes 
                    SET status = 'previously_used', last_scanned = NOW()
                    WHERE ip_address = %s AND status != 'reserved'
                """, (ip_address,))
            else:
                # Was never up, keep as 'down'
                cursor.execute("""
                    UPDATE nodes 
                    SET last_scanned = NOW()
                    WHERE ip_address = %s AND status != 'reserved'
                """, (ip_address,))
    else:
        # New node - ONLY create it if it's actually responding (up)
        if status == 'up':
            cursor.execute("""
                INSERT INTO nodes (ip_address, subnet, last_octet, status, hostname, mac_address, vendor, times_seen, last_seen)
                VALUES (%s, %s, %s, %s, %s, %s, %s, 1, NOW())
            """, (ip_address, subnet, last_octet, status, hostname, mac, vendor))
            
            node_id = cursor.lastrowid
            cursor.execute("""
                INSERT INTO node_history (node_id, ip_address, status, hostname, mac_address, vendor)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, (node_id, ip_address, status, hostname, mac, vendor))
        else:
            # Don't create database entries for IPs that don't respond
            # They'll show as 'unknown' in the grid (no data)
            pass
    
    conn.commit()
    cursor.close()
# =============================================2    




def get_node_info(conn, ip_address):
    """Get node information from database"""
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT * FROM nodes WHERE ip_address = %s", (ip_address,))
    node = cursor.fetchone()
    cursor.close()
    return node

async def scan_ip_range(subnet: str, start_ip: int, end_ip: int) -> List[IPStatus]:
    """Scan IP range using nmap and update database"""
    results = []
    ip_range = f"{subnet}.{start_ip}-{end_ip}"
    
    print(f"\n{'='*60}")
    print(f"Scanning {ip_range} with nmap...")
    print(f"{'='*60}")
    
    conn = get_db_connection()
    if not conn:
        print("✗ Database connection failed")
        # Return empty results if DB is down
        for last_octet in range(start_ip, end_ip + 1):
            ip = f"{subnet}.{last_octet}"
            results.append(IPStatus(
                ip=ip,
                status="unknown",
                last_scanned=datetime.now().isoformat()
            ))
        return results
    
    try:
        nm = nmap.PortScanner()
        nm.scan(hosts=ip_range, arguments='-sn -n -T4')
        
        active_ips = set(nm.all_hosts())
        print(f"Nmap found {len(active_ips)} responding hosts")
        
        for last_octet in range(start_ip, end_ip + 1):
            ip = f"{subnet}.{last_octet}"
            
            # Check current scan status
            is_up = ip in active_ips and nm[ip].state() == "up"
            current_status = 'up' if is_up else 'down'
            
            hostname = None
            mac_address = None
            vendor = None
            
            if is_up:
                host_info = nm[ip]
                
                if 'hostnames' in host_info and host_info['hostnames']:
                    hostname = host_info['hostnames'][0].get('name')
                
                if 'addresses' in host_info:
                    mac_address = host_info['addresses'].get('mac')
                    if mac_address and 'vendor' in host_info:
                        vendor = host_info['vendor'].get(mac_address)
                
                print(f"  UP: {ip}" + (f" ({vendor})" if vendor else ""))
            
            # Update database
            update_or_create_node(conn, ip, subnet, last_octet, current_status, hostname, mac_address, vendor)
            
            # Get updated node info from DB
            node = get_node_info(conn, ip)
            
            if node:
                results.append(IPStatus(
                    ip=ip,
                    status=node['status'],
                    hostname=node['hostname'],
                    mac_address=node['mac_address'],
                    vendor=node['vendor'],
                    last_scanned=node['last_scanned'].isoformat(),
                    first_seen=node['first_seen'].isoformat() if node['first_seen'] else None,
                    last_seen=node['last_seen'].isoformat() if node['last_seen'] else None,
                    times_seen=node['times_seen'],
                    notes=node['notes'],
                    is_reserved=bool(node['is_reserved'])
                ))
            else:
                results.append(IPStatus(
                    ip=ip,
                    status=current_status,
                    last_scanned=datetime.now().isoformat()
                ))
        
        # Record scan in history
        cursor = conn.cursor()
        active_count = sum(1 for r in results if r.status == 'up')
        cursor.execute("""
            INSERT INTO scan_history (subnet, start_ip, end_ip, total_ips, active_ips, scan_duration)
            VALUES (%s, %s, %s, %s, %s, %s)
        """, (subnet, start_ip, end_ip, len(results), active_count, 0))
        conn.commit()
        cursor.close()
        
        print(f"{'='*60}\n")
    
    except Exception as e:
        print(f"Scan error: {e}")
        import traceback
        traceback.print_exc()
    finally:
        if conn:
            conn.close()
    
    return results

@app.get("/")
async def root():
    return {
        "message": "IP Manager API v2.0", 
        "features": ["Node tracking", "IP reservation", "History"],
        "database": "connected" if connection_pool else "disconnected"
    }

@app.get("/health")
async def health_check():
    db_status = "connected"
    try:
        conn = get_db_connection()
        if conn:
            conn.close()
        else:
            db_status = "disconnected"
    except:
        db_status = "error"
    
    return {
        "status": "healthy", 
        "timestamp": datetime.now().isoformat(),
        "database": db_status
    }

@app.post("/api/scan", response_model=ScanResponse)
async def scan_network(request: ScanRequest):
    """Scan network and update node database"""
    scan_start = datetime.now()
    results = await scan_ip_range(request.subnet, request.start_ip, request.end_ip)
    
    active_count = sum(1 for r in results if r.status == 'up')
    inactive_count = sum(1 for r in results if r.status == 'down')
    previously_used_count = sum(1 for r in results if r.status == 'previously_used')
    reserved_count = sum(1 for r in results if r.status == 'reserved')
    
    return ScanResponse(
        subnet=f"{request.subnet}.{request.start_ip}-{request.end_ip}",
        total_ips=len(results),
        active_ips=active_count,
        inactive_ips=inactive_count,
        previously_used_ips=previously_used_count,
        reserved_ips=reserved_count,
        scan_time=(datetime.now() - scan_start).total_seconds(),
        results=results
    )

@app.post("/api/reserve")
async def reserve_ip(request: ReserveIPRequest):
    """Reserve an IP address"""
    conn = get_db_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="Database connection failed")
    
    try:
        cursor = conn.cursor()
        
        # Update node as reserved
        cursor.execute("""
            UPDATE nodes 
            SET status = 'reserved', is_reserved = TRUE, 
                reserved_by = %s, reserved_at = NOW(),
                notes = %s
            WHERE ip_address = %s
        """, (request.reserved_by, request.description, request.ip))
        
        # Add reservation record
        cursor.execute("""
            INSERT INTO ip_reservations (ip_address, reserved_for, description, reserved_by)
            VALUES (%s, %s, %s, %s)
        """, (request.ip, request.reserved_for, request.description, request.reserved_by))
        
        conn.commit()
        cursor.close()
        
        return {"status": "success", "message": f"IP {request.ip} reserved"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        conn.close()

@app.post("/api/release/{ip}")
async def release_ip(ip: str):
    """Release a reserved IP"""
    conn = get_db_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="Database connection failed")
    
    try:
        cursor = conn.cursor()
        
        cursor.execute("""
            UPDATE nodes 
            SET status = 'down', is_reserved = FALSE, 
                reserved_by = NULL, reserved_at = NULL
            WHERE ip_address = %s
        """, (ip,))
        
        cursor.execute("""
            UPDATE ip_reservations 
            SET is_active = FALSE
            WHERE ip_address = %s AND is_active = TRUE
        """, (ip,))
        
        conn.commit()
        cursor.close()
        
        return {"status": "success", "message": f"IP {ip} released"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        conn.close()

@app.put("/api/node/update")
async def update_node(request: UpdateNodeRequest):
    """Update node information"""
    conn = get_db_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="Database connection failed")
    
    try:
        cursor = conn.cursor()
        
        if request.notes is not None:
            cursor.execute("""
                UPDATE nodes SET notes = %s WHERE ip_address = %s
            """, (request.notes, request.ip))
        
        if request.is_reserved is not None:
            status = 'reserved' if request.is_reserved else 'down'
            cursor.execute("""
                UPDATE nodes 
                SET is_reserved = %s, status = %s
                WHERE ip_address = %s
            """, (request.is_reserved, status, request.ip))
        
        conn.commit()
        cursor.close()
        
        return {"status": "success", "message": "Node updated"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        conn.close()

@app.get("/api/node/{ip}")
async def get_node(ip: str):
    """Get detailed node information including history"""
    conn = get_db_connection()
    if not conn:
        raise HTTPException(status_code=404, detail="Database unavailable")
    
    try:
        cursor = conn.cursor(dictionary=True)
        
        # Get node info
        cursor.execute("SELECT * FROM nodes WHERE ip_address = %s", (ip,))
        node = cursor.fetchone()
        
        if not node:
            raise HTTPException(status_code=404, detail="Node not found")
        
        # Get history
        cursor.execute("""
            SELECT * FROM node_history 
            WHERE ip_address = %s 
            ORDER BY recorded_at DESC 
            LIMIT 10
        """, (ip,))
        history = cursor.fetchall()
        
        cursor.close()
        
        return {
            "node": node,
            "history": history
        }
    finally:
        conn.close()

@app.get("/api/networks/discover")
async def discover_networks():
    """Discover all network interfaces and their subnets"""
    networks = []
    
    try:
        # result = subprocess.run(
        #     ['ip', 'addr', 'show'],
        #     capture_output=True,
        #     text=True,
        #     timeout=5
        # )

        result = subprocess.run(
            ['hostname', '-I'],
            capture_output=True,
            text=True,
            timeout=5,
            shell=False
        )

        # Parse the output - it's just space-separated IPs
        ips = result.stdout.strip().split()

        for ip_addr in ips:
            if ip_addr.startswith('127.'):
                continue
            
            octets = [int(x) for x in ip_addr.split('.')]
            subnet = f"{octets[0]}.{octets[1]}.{octets[2]}"

            networks.append({
                "interface": "host",
                "ip_address": ip_addr,
                "subnet": subnet,
                "prefix": 24,
                "subnet_mask": "255.255.255.0",
                "total_ips": 254,
                "network_type": "Local",
                "is_primary": True
            })        
        
        current_interface = None
        
        for line in result.stdout.split('\n'):
            # Match interface name
            if_match = re.match(r'^\d+:\s+(\w+):', line)
            if if_match:
                current_interface = if_match.group(1)
            
            # Match IP address with subnet
            ip_match = re.search(r'inet\s+(\d+\.\d+\.\d+\.\d+)/(\d+)', line)
            if ip_match and current_interface:
                ip_addr = ip_match.group(1)
                prefix = int(ip_match.group(2))
                
                # Skip loopback
                if ip_addr.startswith('127.'):
                    continue
                
                # Calculate subnet (first 3 octets for /24)
                octets = [int(x) for x in ip_addr.split('.')]
                subnet = f"{octets[0]}.{octets[1]}.{octets[2]}"
                
                networks.append({
                    "interface": current_interface,
                    "ip_address": ip_addr,
                    "subnet": subnet,
                    "prefix": prefix,
                    "subnet_mask": "255.255.255.0",
                    "total_ips": 254,
                    "network_type": "Local" if current_interface.startswith(('eth', 'en', 'wlan', 'wl')) else "Virtual"
                })
        
        # Get default gateway
        try:
            route_result = subprocess.run(
                ['ip', 'route', 'show', 'default'],
                capture_output=True,
                text=True,
                timeout=5
            )
            
            gateway_match = re.search(r'default via (\d+\.\d+\.\d+\.\d+)', route_result.stdout)
            if gateway_match:
                gateway = gateway_match.group(1)
                gateway_subnet = '.'.join(gateway.split('.')[:3])
                for net in networks:
                    if net['subnet'] == gateway_subnet:
                        net['is_primary'] = True
                        net['gateway'] = gateway
        except:
            pass
        
        # Sort: primary first
        networks.sort(key=lambda x: (not x.get('is_primary', False), x['interface']))
        
        return {"networks": networks, "count": len(networks)}
        
    except Exception as e:
        print(f"Network discovery error: {e}")
        return {"networks": [], "count": 0, "error": str(e)}    

    #===========================================================

    # Proxmox Integration
import requests
import urllib3

# Disable SSL warnings for self-signed certs
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Proxmox Configuration
PROXMOX_HOST = os.getenv("PROXMOX_HOST", "192.168.0.100")
PROXMOX_PORT = os.getenv("PROXMOX_PORT", "8006")
PROXMOX_USER = os.getenv("PROXMOX_USER", "root@pam")
PROXMOX_PASSWORD = os.getenv("PROXMOX_PASSWORD")
PROXMOX_NODE = os.getenv("PROXMOX_NODE", "proxmox")

class ProxmoxAPI:
    """Proxmox VE API Client"""
    
    def __init__(self, host, port, user, password, verify_ssl=False):
        self.base_url = f"https://{host}:{port}/api2/json"
        self.verify_ssl = verify_ssl
        self.ticket = None
        self.csrf_token = None
        self.authenticate(user, password)
    
    def authenticate(self, user, password):
        """Get authentication ticket"""
        try:
            response = requests.post(
                f"{self.base_url}/access/ticket",
                data={"username": user, "password": password},
                verify=self.verify_ssl,
                timeout=10
            )
            response.raise_for_status()
            data = response.json()["data"]
            self.ticket = data["ticket"]
            self.csrf_token = data["CSRFPreventionToken"]
            return True
        except Exception as e:
            print(f"Proxmox authentication failed: {e}")
            return False
    
    def get_headers(self):
        """Get request headers with auth"""
        return {
            "CSRFPreventionToken": self.csrf_token,
            "Cookie": f"PVEAuthCookie={self.ticket}"
        }
    
    def get(self, endpoint):
        """GET request"""
        response = requests.get(
            f"{self.base_url}/{endpoint}",
            headers=self.get_headers(),
            verify=self.verify_ssl,
            timeout=10
        )
        response.raise_for_status()
        return response.json()["data"]
    
    def post(self, endpoint, data):
        """POST request"""
        response = requests.post(
            f"{self.base_url}/{endpoint}",
            headers=self.get_headers(),
            data=data,
            verify=self.verify_ssl,
            timeout=30
        )
        response.raise_for_status()
        return response.json()["data"]

# Pydantic models for Proxmox
class ProxmoxVMRequest(BaseModel):
    ip_address: str
    vm_name: str
    cores: int = 2
    memory: int = 2048
    disk_size: int = 32
    template_id: Optional[int] = None
    start_vm: bool = True
    bridge: str = "vmbr0"
    gateway: str = "192.168.0.1"
    nameserver: str = "8.8.8.8"

@app.get("/api/proxmox/status")
async def proxmox_status():
    """Check Proxmox connectivity"""
    try:
        if not PROXMOX_PASSWORD:
            return {"connected": False, "error": "Proxmox credentials not configured"}
        
        proxmox = ProxmoxAPI(PROXMOX_HOST, PROXMOX_PORT, PROXMOX_USER, PROXMOX_PASSWORD, verify_ssl=False)
        version = proxmox.get("version")
        
        return {
            "connected": True,
            "host": PROXMOX_HOST,
            "node": PROXMOX_NODE,
            "version": version.get("version", "Unknown")
        }
    except Exception as e:
        return {"connected": False, "error": str(e)}

@app.get("/api/proxmox/templates")
async def get_proxmox_templates():
    """Get list of available VM templates"""
    try:
        proxmox = ProxmoxAPI(PROXMOX_HOST, PROXMOX_PORT, PROXMOX_USER, PROXMOX_PASSWORD, verify_ssl=False)
        vms = proxmox.get(f"nodes/{PROXMOX_NODE}/qemu")
        
        templates = []
        for vm in vms:
            if vm.get("template", 0) == 1:
                templates.append({
                    "vmid": vm["vmid"],
                    "name": vm["name"],
                    "type": "qemu",
                    "status": vm.get("status", "unknown"),
                    "description": vm.get("description", "")
                })
        
        return {"templates": templates, "count": len(templates)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get templates: {str(e)}")

@app.get("/api/proxmox/nextid")
async def get_next_vmid():
    """Get next available VM ID"""
    try:
        proxmox = ProxmoxAPI(PROXMOX_HOST, PROXMOX_PORT, PROXMOX_USER, PROXMOX_PASSWORD, verify_ssl=False)
        next_id = proxmox.get("cluster/nextid")
        return {"next_vmid": int(next_id)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/proxmox/create-vm")
async def create_proxmox_vm(request: ProxmoxVMRequest):
    """Create a new Proxmox VM with specified IP"""
    try:
        proxmox = ProxmoxAPI(PROXMOX_HOST, PROXMOX_PORT, PROXMOX_USER, PROXMOX_PASSWORD, verify_ssl=False)
        vmid = int(proxmox.get("cluster/nextid"))
        
        subnet_parts = request.ip_address.split('.')
        cidr = "24"
        

        if request.template_id:
            clone_data = {"newid": vmid, "name": request.vm_name, "full": 1}
            task = proxmox.post(f"nodes/{PROXMOX_NODE}/qemu/{request.template_id}/clone", clone_data)
            
            import time
            time.sleep(3)  # Wait longer for clone to complete
            
            config_data = {
                "cores": request.cores,
                "memory": request.memory,
                "ipconfig0": f"ip={request.ip_address}/{cidr},gw={request.gateway}",
                "nameserver": request.nameserver,
                "boot": "order=scsi0",  # Ensure boot order is set
                "ciuser": "ubuntu",  # Set default username
                "cipassword": "ubuntu"  # Set default password
            }
            proxmox.post(f"nodes/{PROXMOX_NODE}/qemu/{vmid}/config", config_data)        
        else:
            vm_data = {
                "vmid": vmid,
                "name": request.vm_name,
                "cores": request.cores,
                "memory": request.memory,
                "net0": f"virtio,bridge={request.bridge}",
                "scsi0": f"local-lvm:{request.disk_size}",
                "ostype": "l26",
                "ipconfig0": f"ip={request.ip_address}/{cidr},gw={request.gateway}",
                "nameserver": request.nameserver
            }
            task = proxmox.post(f"nodes/{PROXMOX_NODE}/qemu", vm_data)
        
        if request.start_vm:
            import time
            time.sleep(3)
            proxmox.post(f"nodes/{PROXMOX_NODE}/qemu/{vmid}/status/start", {})
        
        conn = get_db_connection()
        if conn:
            cursor = conn.cursor()
            cursor.execute("""
                UPDATE nodes 
                SET status = 'reserved', is_reserved = TRUE,
                    notes = CONCAT(COALESCE(notes, ''), '\nProxmox VM: ', %s, ' (VMID: ', %s, ')'),
                    reserved_by = 'Proxmox', reserved_at = NOW()
                WHERE ip_address = %s
            """, (request.vm_name, vmid, request.ip_address))
            conn.commit()
            cursor.close()
            conn.close()
        
        add_prometheus_target(request.ip_address)            
        
        return {
            "success": True,
            "vmid": vmid,
            "vm_name": request.vm_name,
            "ip_address": request.ip_address,
            "message": f"VM {request.vm_name} created successfully with ID {vmid}"
        }
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to create VM: {str(e)}")

# =============================================

@app.delete("/api/network/clear/{subnet}")
async def clear_network_data(subnet: str):
    """Clear all node data for a specific subnet"""
    try:
        conn = get_db_connection()
        if not conn:
            raise HTTPException(status_code=500, detail="Database connection failed")
        
        cursor = conn.cursor()
        
        cursor.execute("DELETE FROM node_history WHERE ip_address LIKE %s", (f"{subnet}.%",))
        cursor.execute("DELETE FROM scan_history WHERE subnet = %s", (subnet,))
        cursor.execute("DELETE FROM ip_reservations WHERE ip_address LIKE %s", (f"{subnet}.%",))
        cursor.execute("DELETE FROM nodes WHERE subnet = %s", (subnet,))
        
        conn.commit()
        nodes_deleted = cursor.rowcount
        
        cursor.close()
        conn.close()
        
        return {
            "success": True,
            "subnet": subnet,
            "message": f"Cleared all data for subnet {subnet}.x",
            "nodes_deleted": nodes_deleted
        }
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to clear network: {str(e)}")


@app.post("/api/network/reset-status/{subnet}")
async def reset_network_status(subnet: str):
    """Reset all nodes in a subnet to 'down' status"""
    try:
        conn = get_db_connection()
        if not conn:
            raise HTTPException(status_code=500, detail="Database connection failed")
        
        cursor = conn.cursor()
        
        cursor.execute("""
            UPDATE nodes 
            SET status = 'down', last_scanned = NULL
            WHERE subnet = %s AND is_reserved = FALSE
        """, (subnet,))
        
        conn.commit()
        nodes_reset = cursor.rowcount
        
        cursor.close()
        conn.close()
        
        return {
            "success": True,
            "subnet": subnet,
            "message": f"Reset status for {nodes_reset} nodes in {subnet}.x",
            "nodes_reset": nodes_reset
        }
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to reset network: {str(e)}")
# ============================================================================
# Traffic Monitoring Integration
# ============================================================================



class TrafficTestRequest(BaseModel):
    source_ip: str
    target_ip: str
    protocol: str = "tcp"
    duration: int = 60
    bandwidth: str = "100M"
    parallel: int = 1
    reverse: bool = False

class TrafficTestResult(BaseModel):
    test_id: str
    status: str
    source_ip: str
    target_ip: str
    protocol: str
    start_time: float
    end_time: Optional[float] = None
    results: Optional[Dict] = None
    error: Optional[str] = None

class SSHManager:
    """Manage SSH connections to VMs"""
    
    def __init__(self, username="ubuntu", password="ubuntu", key_file=None):
        self.username = username
        self.password = password
        self.key_file = key_file
        self.connections = {}
    
    def connect(self, host: str, port: int = 22):
        """Establish SSH connection to host"""
        try:
            client = paramiko.SSHClient()
            client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            
            print(f"🔌 Connecting to {host}:{port} as {self.username}...")
            
            client.connect(
                hostname=host,
                port=port,
                username=self.username,
                password=self.password,
                timeout=15,
                allow_agent=False,
                look_for_keys=False,
                banner_timeout=60
            )
            
            print(f"✓ Connected to {host}")
            self.connections[host] = client
            return client
            
        except Exception as e:
            print(f"✗ SSH failed to {host}: {e}")
            import traceback
            traceback.print_exc()
            return None


    def execute_command(self, host: str, command: str):
        """Execute command on remote host"""
        try:
            client = self.connections.get(host) or self.connect(host)
            if not client:
                return None, f"Failed to connect to {host}"
            
            stdin, stdout, stderr = client.exec_command(command, timeout=300)
            exit_code = stdout.channel.recv_exit_status()
            
            output = stdout.read().decode('utf-8')
            error = stderr.read().decode('utf-8')
            
            return output, error if error else None
        except Exception as e:
            return None, str(e)
    
    def close(self, host: str):
        """Close SSH connection"""
        if host in self.connections:
            self.connections[host].close()
            del self.connections[host]
    
    def close_all(self):
        """Close all SSH connections"""
        for host in list(self.connections.keys()):
            self.close(host)

# Initialize SSH manager
ssh_manager = SSHManager(username="ubuntu", password="ubuntu")

# Store active traffic tests
active_traffic_tests: Dict[str, TrafficTestResult] = {}

@app.post("/api/traffic/start", response_model=TrafficTestResult)
async def start_traffic_test(request: TrafficTestRequest):
    """Start iperf3 traffic test between two VMs"""
    try:
        test_id = str(uuid.uuid4())
        
        # Build iperf3 command
        cmd_parts = [
            "iperf3",
            "-c", request.target_ip,
            "-t", str(request.duration),
            "-J"
        ]
        
        if request.protocol == "udp":
            cmd_parts.append("-u")
        
        if request.bandwidth:
            cmd_parts.extend(["-b", request.bandwidth])
        
        if request.parallel > 1:
            cmd_parts.extend(["-P", str(request.parallel)])
        
        if request.reverse:
            cmd_parts.append("-R")
        
        command = " ".join(cmd_parts)
        
        # Create test record
        test_record = TrafficTestResult(
            test_id=test_id,
            status="running",
            source_ip=request.source_ip,
            target_ip=request.target_ip,
            protocol=request.protocol,
            start_time=time.time()
        )
        
        active_traffic_tests[test_id] = test_record
        
        # Execute test asynchronously
        def run_test():
            try:
                output, error = ssh_manager.execute_command(request.source_ip, command)
                
                if error:
                    test_record.status = "failed"
                    test_record.error = error
                else:
                    test_record.status = "completed"
                    try:
                        test_record.results = json.loads(output)
                    except json.JSONDecodeError:
                        test_record.results = {"raw_output": output}
                
                test_record.end_time = time.time()
                
            except Exception as e:
                test_record.status = "failed"
                test_record.error = str(e)
                test_record.end_time = time.time()
        
        thread = threading.Thread(target=run_test, daemon=True)
        thread.start()
        
        return test_record
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/traffic/status/{test_id}", response_model=TrafficTestResult)
async def get_traffic_test_status(test_id: str):
    """Get status of traffic test"""
    if test_id not in active_traffic_tests:
        raise HTTPException(status_code=404, detail="Test not found")
    
    return active_traffic_tests[test_id]

@app.get("/api/traffic/results/{test_id}")
async def get_traffic_test_results(test_id: str):
    """Get detailed results of completed test"""
    if test_id not in active_traffic_tests:
        raise HTTPException(status_code=404, detail="Test not found")
    
    test = active_traffic_tests[test_id]
    
    if test.status == "running":
        return {"status": "running", "message": "Test is still in progress"}
    
    if test.status == "failed":
        return {"status": "failed", "error": test.error}
    
    results = test.results
    if not results:
        return {"status": "completed", "message": "No results available"}
    
    try:
        # For UDP use "sum", for TCP use "sum_received"
        if test.protocol == "udp":
            end_data = results.get("end", {}).get("sum", {})
        else:
            end_data = results.get("end", {}).get("sum_received", {})
        
        summary = {
            "test_id": test_id,
            "source": test.source_ip,
            "target": test.target_ip,
            "protocol": test.protocol,
            "status": "completed",
            "bandwidth_bps": end_data.get("bits_per_second", 0),
            "bandwidth_mbps": round(end_data.get("bits_per_second", 0) / 1000000, 2),
            "bytes_transferred": end_data.get("bytes", 0),
            "retransmits": results.get("end", {}).get("sum_sent", {}).get("retransmits", 0) if test.protocol == "tcp" else 0,
            "jitter_ms": end_data.get("jitter_ms", 0),
            "lost_packets": end_data.get("lost_packets", 0),
            "packets": end_data.get("packets", 0),
            "lost_percent": end_data.get("lost_percent", 0),
            "raw_results": results
        }
        return summary    
    
    except Exception as e:
        return {"status": "completed", "results": results, "parse_error": str(e)}

@app.get("/api/traffic/active")
async def get_active_tests():
    """Get list of all active traffic tests"""
    active = [t for t in active_traffic_tests.values() if t.status == "running"]
    completed = [t for t in active_traffic_tests.values() if t.status == "completed"]
    failed = [t for t in active_traffic_tests.values() if t.status == "failed"]
    
    return {
        "active": active,
        "completed": completed[-10:],
        "failed": failed[-10:],
        "total_active": len(active),
        "total_completed": len(completed),
        "total_failed": len(failed)
    }

@app.post("/api/traffic/vm/check")
async def check_vm_monitoring(request: dict):
    """Check if VM has monitoring tools installed"""
    ip = request.get("ip")
    try:
        output, error = ssh_manager.execute_command(ip, "systemctl is-active node_exporter")
        node_exporter_running = output and output.strip() == "active"
        
        output, error = ssh_manager.execute_command(ip, "systemctl is-active iperf3-server")
        iperf3_running = output and output.strip() == "active"
        
        output, error = ssh_manager.execute_command(ip, "ss -tulpn | grep -E '(9100|5201)'")
        ports_listening = bool(output)
        
        try:
            import requests
            metrics_response = requests.get(f"http://{ip}:9100/metrics", timeout=5)
            metrics_available = metrics_response.status_code == 200
            metrics_count = len(metrics_response.text.split('\n')) if metrics_available else 0
        except:
            metrics_available = False
            metrics_count = 0
        
        return {
            "ip": ip,
            "node_exporter_running": node_exporter_running,
            "iperf3_running": iperf3_running,
            "ports_listening": ports_listening,
            "metrics_available": metrics_available,
            "metrics_count": metrics_count,
            "ready": node_exporter_running and iperf3_running and metrics_available
        }
        
    except Exception as e:
        return {
            "ip": ip,
            "error": str(e),
            "ready": False
        }

