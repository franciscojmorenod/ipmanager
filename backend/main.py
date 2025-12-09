"""
FastAPI Backend for IP Manager with MySQL persistence
Tracks node history and allows IP reassignment
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, validator
from typing import List, Optional
import nmap
import asyncio
from datetime import datetime
import mysql.connector
from mysql.connector import pooling
import os
import subprocess
import re

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
            # Device is offline - mark as previously_used if it was seen before
            if existing['times_seen'] > 0:
                cursor.execute("""
                    UPDATE nodes 
                    SET status = 'previously_used', last_scanned = NOW()
                    WHERE ip_address = %s AND status != 'reserved'
                """, (ip_address,))
            else:
                cursor.execute("""
                    UPDATE nodes 
                    SET status = %s, last_scanned = NOW()
                    WHERE ip_address = %s AND status != 'reserved'
                """, (status, ip_address))
    else:
        # New node - create it
        new_status = status if status == 'up' else 'down'
        cursor.execute("""
            INSERT INTO nodes (ip_address, subnet, last_octet, status, hostname, mac_address, vendor)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
        """, (ip_address, subnet, last_octet, new_status, hostname, mac, vendor))
        
        if status == 'up':
            node_id = cursor.lastrowid
            cursor.execute("""
                INSERT INTO node_history (node_id, ip_address, status, hostname, mac_address, vendor)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, (node_id, ip_address, status, hostname, mac, vendor))
    
    conn.commit()
    cursor.close()

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
