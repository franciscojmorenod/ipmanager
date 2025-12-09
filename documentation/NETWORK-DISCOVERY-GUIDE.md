# Network Discovery Feature - Setup Guide

## 🌐 What This Does

Automatically discovers all networks your Ubuntu laptop can reach and lets you switch between them with one click!

### Features

✅ **Auto-Discovery**
- Detects all network interfaces (eth0, wlan0, etc.)
- Shows IP addresses and subnets
- Identifies primary network (with gateway)
- Lists virtual interfaces (Docker, VPN)

✅ **Visual Network Selector**
- Click 🌐 button next to subnet input
- See all available networks
- One-click to switch networks
- Shows interface name, IP, gateway

✅ **Smart Detection**
- Primary network marked with green badge
- Shows total addressable IPs
- Interface type (Local vs Virtual)
- Gateway information

## 🎯 Use Cases

**Multi-Network Environments:**
- Home network: 192.168.1.x
- Guest network: 192.168.2.x
- IoT network: 10.0.0.x
- VPN networks

**Network Monitoring:**
- Scan multiple subnets without manual entry
- Quick network switching
- Track devices across different networks

## 🚀 Installation

### Step 1: Update Backend

Add these two endpoints to your `~/ipmanager/backend/main.py`:

```python
# Add after other imports
import subprocess
import re

# Add these endpoints before the last line

@app.get("/api/networks/discover")
async def discover_networks():
    """Discover all network interfaces and their subnets"""
    networks = []
    
    try:
        result = subprocess.run(
            ['ip', 'addr', 'show'],
            capture_output=True,
            text=True,
            timeout=5
        )
        
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
```

### Step 2: Update Frontend

**Add the network button to your App.js:**

Find the subnet input section (around line 430) and replace:

```jsx
<input
  type="text"
  value={subnet}
  onChange={(e) => setSubnet(e.target.value)}
  placeholder="192.168.1"
  disabled={scanning}
  className="subnet-input"
/>
```

With:

```jsx
<div style={{display: 'flex', gap: '10px'}}>
  <input
    type="text"
    value={subnet}
    onChange={(e) => setSubnet(e.target.value)}
    placeholder="192.168.1"
    disabled={scanning}
    className="subnet-input"
  />
  <button
    onClick={() => setShowNetworkModal(true)}
    className="network-btn"
    title="Discover Networks"
  >
    🌐
  </button>
</div>
```

**Add state variables at the top:**

```jsx
const [showNetworkModal, setShowNetworkModal] = useState(false);
const [availableNetworks, setAvailableNetworks] = useState([]);
const [loadingNetworks, setLoadingNetworks] = useState(false);
```

**Add useEffect for auto-discovery:**

```jsx
useEffect(() => {
  discoverNetworks();
}, []);
```

**Add these functions:**

```jsx
const discoverNetworks = async () => {
  setLoadingNetworks(true);
  try {
    const response = await fetch('http://localhost:8000/api/networks/discover');
    const data = await response.json();
    setAvailableNetworks(data.networks || []);
  } catch (error) {
    console.error('Network discovery failed:', error);
  } finally {
    setLoadingNetworks(false);
  }
};

const handleNetworkSelect = (network) => {
  setSubnet(network.subnet);
  setShowNetworkModal(false);
  setResults([]);
};

const closeNetworkModal = () => {
  setShowNetworkModal(false);
};
```

**Add the Network Modal** (after other modals):

```jsx
{showNetworkModal && (
  <div className="modal-overlay show" onClick={closeNetworkModal}>
    <div className="modal glass network-modal" onClick={(e) => e.stopPropagation()}>
      <button className="modal-close" onClick={closeNetworkModal}>
        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
          <path d="M18 6L6 18M6 6l12 12"/>
        </svg>
      </button>
      
      <div className="modal-header">
        <h2>🌐 Available Networks</h2>
        <p style={{color: 'var(--text-secondary)', fontSize: '1rem', marginTop: '10px'}}>
          Select a network to scan
        </p>
      </div>

      <div className="modal-body">
        {loadingNetworks ? (
          <div style={{textAlign: 'center', padding: '40px'}}>
            <span className="spinner"></span>
            <p style={{marginTop: '20px'}}>Discovering networks...</p>
          </div>
        ) : availableNetworks.length > 0 ? (
          <div className="network-list">
            {availableNetworks.map((network, index) => (
              <div 
                key={index} 
                className={`network-item ${network.is_primary ? 'primary' : ''}`}
                onClick={() => handleNetworkSelect(network)}
              >
                <div className="network-icon">
                  {network.network_type === 'Local' ? '🌐' : '🔌'}
                </div>
                <div className="network-info">
                  <div className="network-name">
                    {network.subnet}.0/24
                    {network.is_primary && <span className="primary-badge">Primary</span>}
                  </div>
                  <div className="network-details">
                    {network.interface} • {network.ip_address}
                    {network.gateway && ` • Gateway: ${network.gateway}`}
                  </div>
                  <div className="network-meta">
                    {network.total_ips} addressable IPs
                  </div>
                </div>
                <div className="network-arrow">→</div>
              </div>
            ))}
          </div>
        ) : (
          <div className="empty-state">
            <p>No networks detected</p>
          </div>
        )}
      </div>
    </div>
  </div>
)}
```

### Step 3: Add CSS

Download: **[network-styles.css](computer:///mnt/user-data/outputs/network-styles.css)**

Add this to your App.css or import separately.

### Step 4: Restart Services

```bash
cd ~/ipmanager

# Restart backend
docker compose restart ipam-backend

# Restart frontend
docker compose restart ipam-frontend

# Wait 30 seconds
sleep 30
```

## 🎨 How It Looks

**Network Button (🌐)**
- Small globe icon next to subnet input
- Hover shows "Discover Networks"
- Click to open network selector

**Network Selector Modal**
- Shows all detected networks
- Primary network has green "PRIMARY" badge
- Each network shows:
  - Subnet (e.g., 192.168.1.0/24)
  - Interface (eth0, wlan0, etc.)
  - IP address
  - Gateway (if primary)
  - Total IPs
- Click any network to select it

## 📊 Example Output

```
🌐 Available Networks

🌐 192.168.1.0/24 [PRIMARY]
   eth0 • 192.168.1.100 • Gateway: 192.168.1.1
   254 addressable IPs

🔌 192.168.2.0/24
   wlan0 • 192.168.2.50
   254 addressable IPs

🔌 172.17.0.0/24
   docker0 • 172.17.0.1
   254 addressable IPs
```

## 🎯 Usage

1. **Open IP Manager** in browser
2. **Page loads** - auto-discovers networks
3. **Click 🌐 button** next to subnet field
4. **See all networks** - primary highlighted
5. **Click network** to select
6. **Scan automatically** uses new subnet

## 💡 Tips

- Primary network is your main internet connection
- Virtual interfaces (docker0, veth) are usually internal
- VPN connections appear as separate networks
- Click refresh if you connect to a new network

## 🔍 Troubleshooting

**No networks detected:**
```bash
# Check interfaces manually
ip addr show

# Check if backend has permission
docker exec ipam-backend ip addr show
```

**Can't scan selected network:**
- Make sure it's actually reachable
- Try pinging gateway first
- Check firewall rules

This feature makes it super easy to manage multiple networks! 🚀
