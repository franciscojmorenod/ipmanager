import React, { useState, useEffect } from 'react';
import './App.css';
import './network-styles.css'


function App() {

  const [showTrafficModal, setShowTrafficModal] = useState(false);
  const [trafficSource, setTrafficSource] = useState(null);
  const [trafficTarget, setTrafficTarget] = useState('');
  const [trafficConfig, setTrafficConfig] = useState({
    protocol: 'tcp',
    duration: 60,
    bandwidth: '100M',
    parallel: 1,
    reverse: false
  });
  const [activeTests, setActiveTests] = useState([]);
  const [testResults, setTestResults] = useState(null);
  const [showResults, setShowResults] = useState(false);


  const [subnet, setSubnet] = useState('192.168.1');
  const [scanning, setScanning] = useState(false);
  const [results, setResults] = useState([]);
  const [selectedIP, setSelectedIP] = useState(null);
  const [showDetails, setShowDetails] = useState(false);
  const [showReserveModal, setShowReserveModal] = useState(false);
  const [showNotesModal, setShowNotesModal] = useState(false);
  const [reserveForm, setReserveForm] = useState({
    reservedFor: '',
    description: '',
    reservedBy: ''
  });
  const [notesForm, setNotesForm] = useState('');
  const [scanProgress, setScanProgress] = useState(0);
  const [filter, setFilter] = useState('all');

  const [showNetworkModal, setShowNetworkModal] = useState(false);
  const [availableNetworks, setAvailableNetworks] = useState([]);
  const [loadingNetworks, setLoadingNetworks] = useState(false);

  const [showProxmoxModal, setShowProxmoxModal] = useState(false);
  const [proxmoxConnected, setProxmoxConnected] = useState(false);
  const [proxmoxTemplates, setProxmoxTemplates] = useState([]);
  const [proxmoxForm, setProxmoxForm] = useState({
    vm_name: '',
    cores: 2,
    memory: 2048,
    disk_size: 32,
    template_id: null,
    start_vm: true,
    gateway: '192.168.0.1',
    nameserver: '8.8.8.8'
  });

  useEffect(() => {
  discoverNetworks();
  }, []);

  useEffect(() => {
  checkProxmoxStatus();
  }, []);

  // Load active tests on mount
  useEffect(() => {
    loadActiveTests();
    const interval = setInterval(loadActiveTests, 10000); // Refresh every 10 seconds
    return () => clearInterval(interval);
  }, []);

  const isLocalhostIP = (octet) => {
    const ip = `${subnet}.${octet}`;

    // Gateway
    // if (octet === 1) return true;

    // Your laptop's IP from network discovery
    const matchingNetwork = availableNetworks.find(net => net.ip_address === ip);
    if (matchingNetwork) return true;

    return false;
  };


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


  const handleScan = async () => {
    setScanning(true);
    setResults([]);
    setScanProgress(0);
    
    const progressInterval = setInterval(() => {
      setScanProgress(prev => Math.min(prev + 10, 90));
    }, 200);
    
    try {
      const response = await fetch('http://localhost:8000/api/scan', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          subnet: subnet,
          start_ip: 0,
          end_ip: 255
        })
      });
      
      const data = await response.json();
      setResults(data.results);
      setScanProgress(100);
      clearInterval(progressInterval);
    } catch (error) {
      console.error('Scan failed:', error);
      alert('Scan failed: ' + error.message);
      clearInterval(progressInterval);
    } finally {
      setTimeout(() => {
        setScanning(false);
        setScanProgress(0);
      }, 500);
    }
  };

  const getIPStatus = (octet) => {
    const ip = `${subnet}.${octet}`;
    const result = results.find(r => r.ip === ip);
    return result ? result.status : 'unknown';
  };

  const getIPDetails = (octet) => {
    const ip = `${subnet}.${octet}`;
    return results.find(r => r.ip === ip);
  };

  const handleCellClick = async (octet) => {
    const details = getIPDetails(octet);
    if (details && details.status !== 'unknown') {
      // Fetch detailed info with history
      try {
        const response = await fetch(`http://localhost:8000/api/node/${details.ip}`);
        const data = await response.json();
        setSelectedIP({...details, history: data.history, node: data.node});
      } catch (error) {
        setSelectedIP(details);
      }
      setShowDetails(true);
    }
  };

  const handleReserveClick = (details) => {
    setSelectedIP(details);
    setShowDetails(false);
    setShowReserveModal(true);
  };

  const handleEditNotesClick = (details) => {
    setNotesForm(details.notes || '');
    setShowDetails(false);
    setShowNotesModal(true);
  };

  const handleReserveSubmit = async () => {
    try {
      await fetch('http://localhost:8000/api/reserve', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          ip: selectedIP.ip,
          reserved_for: reserveForm.reservedFor,
          description: reserveForm.description,
          reserved_by: reserveForm.reservedBy
        })
      });
      
      setShowReserveModal(false);
      setReserveForm({ reservedFor: '', description: '', reservedBy: '' });
      alert(`IP ${selectedIP.ip} reserved successfully!`);
      handleScan(); // Refresh
    } catch (error) {
      alert('Reservation failed: ' + error.message);
    }
  };

  const handleNotesSubmit = async () => {
    try {
      await fetch('http://localhost:8000/api/node/update', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          ip: selectedIP.ip,
          notes: notesForm
        })
      });
      
      setShowNotesModal(false);
      alert(`Notes updated for ${selectedIP.ip}`);
      handleScan(); // Refresh
    } catch (error) {
      alert('Update failed: ' + error.message);
    }
  };

  const handleReleaseIP = async (ip) => {
    if (window.confirm(`Release IP ${ip}?`)) {
      try {
        await fetch(`http://localhost:8000/api/release/${ip}`, {
          method: 'POST'
        });
        alert(`IP ${ip} released`);
        setShowDetails(false);
        handleScan(); // Refresh
      } catch (error) {
        alert('Release failed: ' + error.message);
      }
    }
  };

const handleClearNetwork = async () => {
  if (!window.confirm(`⚠️ Clear all data for ${subnet}.x network?\n\nThis will:\n- Delete all node history\n- Delete scan history\n- Delete reservations\n- Cannot be undone!\n\nContinue?`)) {
    return;
  }
  
  try {
    const response = await fetch(`http://localhost:8000/api/network/clear/${subnet}`, {
      method: 'DELETE'
    });
    
    const data = await response.json();
    
    if (response.ok) {
      alert(`✓ Network Cleared!\n\n${data.message}\nDeleted ${data.nodes_deleted} nodes`);
      setResults([]);
    } else {
      alert(`Failed to clear network: ${data.detail}`);
    }
  } catch (error) {
    alert('Failed to clear network: ' + error.message);
  }
};

const handleResetStatus = async () => {
  if (!window.confirm(`Reset all nodes in ${subnet}.x to "available" status?\n\nThis will:\n- Mark all non-reserved IPs as available\n- Preserve node history\n- Keep reservations\n\nContinue?`)) {
    return;
  }
  
  try {
    const response = await fetch(`http://localhost:8000/api/network/reset-status/${subnet}`, {
      method: 'POST'
    });
    
    const data = await response.json();
    
    if (response.ok) {
      alert(`✓ Status Reset!\n\n${data.message}`);
      handleScan();
    } else {
      alert(`Failed to reset status: ${data.detail}`);
    }
  } catch (error) {
    alert('Failed to reset status: ' + error.message);
  }
};


  const getStatusColor = (status) => {
    switch(status) {
      case 'up':
        return 'status-up';
      case 'down':
        return 'status-down';
      case 'previously_used':
        return 'status-previously-used';
      case 'reserved':
        return 'status-reserved';
      case 'unknown':
      default:
        return 'status-unknown';
    }
  };

  // ---------------------------------
  const checkProxmoxStatus = async () => {
    try {
      const response = await fetch('http://localhost:8000/api/proxmox/status');
      const data = await response.json();
      setProxmoxConnected(data.connected);
      if (data.connected) {
        loadProxmoxTemplates();
      }
    } catch (error) {
      console.error('Proxmox status check failed:', error);
      setProxmoxConnected(false);
    }
  };  

  const loadProxmoxTemplates = async () => {
    try {
      const response = await fetch('http://localhost:8000/api/proxmox/templates');
      const data = await response.json();
      setProxmoxTemplates(data.templates || []);
    } catch (error) {
      console.error('Failed to load templates:', error);
    }
  };  

  const handleCreateVMClick = (details) => {
    if (!proxmoxConnected) {
      alert('Proxmox is not connected. Please check configuration.');
      return;
    }
    setProxmoxForm({
      ...proxmoxForm,
      vm_name: `vm-${details.ip.replace(/\./g, '-')}`
    });
    setSelectedIP(details);
    setShowDetails(false);
    setShowProxmoxModal(true);
  };  

  const handleProxmoxSubmit = async () => {
    if (!proxmoxForm.vm_name) {
      alert('Please enter a VM name');
      return;
    }

    try {
      const response = await fetch('http://localhost:8000/api/proxmox/create-vm', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          ip_address: selectedIP.ip,
          vm_name: proxmoxForm.vm_name,
          cores: proxmoxForm.cores,
          memory: proxmoxForm.memory,
          disk_size: proxmoxForm.disk_size,
          template_id: proxmoxForm.template_id,
          start_vm: proxmoxForm.start_vm,
          gateway: proxmoxForm.gateway,
          nameserver: proxmoxForm.nameserver
        })
      });

      const data = await response.json();

      if (response.ok) {
        alert(`✓ VM Created!\n\nName: ${data.vm_name}\nVMID: ${data.vmid}\nIP: ${data.ip_address}`);
        setShowProxmoxModal(false);
        setProxmoxForm({
          vm_name: '',
          cores: 2,
          memory: 2048,
          disk_size: 32,
          template_id: null,
          start_vm: true,
          gateway: '192.168.0.1',
          nameserver: '8.8.8.8'
        });
        handleScan();
      } else {
        alert(`Failed to create VM: ${data.detail || 'Unknown error'}`);
      }
    } catch (error) {
      alert('Failed to create VM: ' + error.message);
    }
  };  

  const closeProxmoxModal = () => {
    setShowProxmoxModal(false);
  };
  // ---------------------------------
  
  const shouldShowCell = (status) => {
    if (filter === 'all') return true;
    return status === filter;
  };

  const renderGrid = () => {
    const grid = [];
    for (let row = 0; row < 16; row++) {
      const cells = [];
      for (let col = 0; col < 16; col++) {
        const octet = row * 16 + col;
        const status = getIPStatus(octet);
        const statusClass = getStatusColor(status);
        const details = getIPDetails(octet);
        const shouldShow = shouldShowCell(status);
        const hasNotes = details?.notes && details.notes.trim() !== '';
        const isLocalhost = isLocalhostIP(octet);
        cells.push(
          <div
            key={octet}
            // className={`grid-cell ${statusClass} ${!shouldShow ? 'cell-hidden' : ''} ${status === 'up' ? 'cell-active' : ''} ${hasNotes ? 'has-notes' : ''}`}
            className={`grid-cell ${statusClass} ${!shouldShow ? 'cell-hidden' : ''} ${status === 'up' ? 'cell-active' : ''} ${hasNotes ? 'has-notes' : ''} ${isLocalhost ? 'cell-localhost' : ''}`}
            onClick={() => handleCellClick(octet)}
            title={`${subnet}.${octet}\n${status.toUpperCase()}${details?.vendor ? '\n' + details.vendor : ''}${hasNotes ? '\n📝 Has notes' : ''}`}
          >
            <span className="cell-number">{octet}</span>
            {details?.vendor && status === 'up' && (
              <span className="cell-indicator">●</span>
            )}
            {status === 'reserved' && (
              <span className="cell-reserved-icon">🔒</span>
            )}
            {hasNotes && (
              <span className="cell-notes-icon">📝</span>
            )}
          </div>
        );
      }
      grid.push(
        <div key={row} className="grid-row">
          {cells}
        </div>
      );
    }
    return grid;
  };

  const closeDetails = () => {
    setShowDetails(false);
    setTimeout(() => setSelectedIP(null), 300);
  };

  const closeReserve = () => {
    setShowReserveModal(false);
    setReserveForm({ reservedFor: '', description: '', reservedBy: '' });
  };

  const closeNotes = () => {
    setShowNotesModal(false);
    setNotesForm('');
  };

  const stats = {
    total: results.length,
    up: results.filter(r => r.status === 'up').length,
    down: results.filter(r => r.status === 'down').length,
    previously_used: results.filter(r => r.status === 'previously_used').length,
    reserved: results.filter(r => r.status === 'reserved').length,
    with_notes: results.filter(r => r.notes && r.notes.trim() !== '').length,
    unknown: results.filter(r => r.status === 'unknown').length
  };

  // =======================================================

  // Traffic monitoring functions

  const handleTrafficTest = (ipDetails) => {
    setTrafficSource(ipDetails);
    setTrafficTarget('');
    setShowTrafficModal(true);
  };

  const handleStartTraffic = async () => {
    if (!trafficTarget) {
      alert('Please select a target VM');
      return;
    }

    try {
      const response = await fetch('http://localhost:8000/api/traffic/start', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          source_ip: trafficSource.ip,
          target_ip: trafficTarget,
          protocol: trafficConfig.protocol,
          duration: trafficConfig.duration,
          bandwidth: trafficConfig.bandwidth,
          parallel: trafficConfig.parallel,
          reverse: trafficConfig.reverse
        })
      });

      const data = await response.json();

      if (response.ok) {
        alert(`✓ Traffic test started!\n\nTest ID: ${data.test_id}\nDuration: ${trafficConfig.duration}s\n\nMonitor progress in Grafana:\nhttp://192.168.0.100:3001`);
        setShowTrafficModal(false);

        // Poll for results
        pollTestResults(data.test_id);

        // Refresh active tests
        loadActiveTests();
      } else {
        alert(`Failed to start test: ${data.detail || 'Unknown error'}`);
      }
    } catch (error) {
      alert('Failed to start traffic test: ' + error.message);
    }
  };

  const pollTestResults = async (testId) => {
    const maxAttempts = 120; // Poll for up to 2 minutes after test should complete
    let attempts = 0;

    const pollInterval = setInterval(async () => {
      attempts++;

      try {
        const response = await fetch(`http://localhost:8000/api/traffic/status/${testId}`);
        const data = await response.json();

        if (data.status === 'completed' || data.status === 'failed') {
          clearInterval(pollInterval);

          // Get detailed results
          const resultsResponse = await fetch(`http://localhost:8000/api/traffic/results/${testId}`);
          const resultsData = await resultsResponse.json();

          setTestResults(resultsData);
          setShowResults(true);
          loadActiveTests();
        }

        if (attempts >= maxAttempts) {
          clearInterval(pollInterval);
        }
      } catch (error) {
        console.error('Error polling test results:', error);
      }
    }, 5000); // Poll every 5 seconds
  };

  const loadActiveTests = async () => {
    try {
      const response = await fetch('http://localhost:8000/api/traffic/active');
      const data = await response.json();
      setActiveTests([...data.active, ...data.completed.slice(0, 3)]);
    } catch (error) {
      console.error('Failed to load active tests:', error);
    }
  };

  const checkVMMonitoring = async (ip) => {
    try {
      const response = await fetch('http://localhost:8000/api/traffic/vm/check', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ip })
      });

      const data = await response.json();

      if (data.ready) {
        alert(`✓ VM ${ip} is ready for monitoring!\n\n✓ node_exporter running\n✓ iperf3 server running\n✓ Metrics available (${data.metrics_count} metrics)`);
      } else {
        alert(`⚠ VM ${ip} needs setup\n\nnode_exporter: ${data.node_exporter_running ? '✓' : '✗'}\niperf3: ${data.iperf3_running ? '✓' : '✗'}\nmetrics: ${data.metrics_available ? '✓' : '✗'}\n\nRun prepare-vm.sh on the VM first.`);
      }
    } catch (error) {
      alert('Failed to check VM monitoring: ' + error.message);
    }
  };

  const openGrafana = () => {
    window.open('http://192.168.0.100:3001', '_blank');
  };

  const openPrometheus = () => {
    window.open('http://192.168.0.100:9090', '_blank');
  };

  
  // =======================================================
  return (
    <div className="App">
      <div className="background-animation">
        <div className="glow glow-1"></div>
        <div className="glow glow-2"></div>
        <div className="glow glow-3"></div>
      </div>

      <div className="container">
        <header className="header">
          <div className="logo">
            <svg width="50" height="50" viewBox="0 0 50 50" fill="none">
              <circle cx="25" cy="25" r="20" stroke="url(#grad1)" strokeWidth="3"/>
              <circle cx="25" cy="25" r="12" fill="url(#grad1)"/>
              <defs>
                <linearGradient id="grad1" x1="0%" y1="0%" x2="100%" y2="100%">
                  <stop offset="0%" stopColor="#6366f1" />
                  <stop offset="100%" stopColor="#a855f7" />
                </linearGradient>
              </defs>
            </svg>
          </div>
          <h1 className="title">IP Address Manager</h1>
          <p className="subtitle">Network Visualization & Tracking System</p>
        </header>

        <div className="control-panel glass">
          <div className="scan-controls">
            <div className="input-wrapper">
              <label>Network Subnet</label>

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
            </div>
            <button 
              onClick={handleScan} 
              disabled={scanning}
              className="scan-btn"
            >
              {scanning ? (
                <>
                  <span className="spinner"></span>
                  Scanning...
                </>
              ) : (
                <>
                  <svg width="20" height="20" viewBox="0 0 20 20" fill="currentColor">
                    <path d="M10 3a7 7 0 100 14 7 7 0 000-14zm-9 7a9 9 0 1118 0 9 9 0 01-18 0z"/>
                    <path d="M10 7a3 3 0 100 6 3 3 0 000-6z"/>
                  </svg>
                  Start Scan
                </>
              )}
            </button>

              <button 
                onClick={handleResetStatus}
                className="action-btn btn-warning"
                title="Reset all nodes to available (keeps history)"
                disabled={scanning}
              >
                🔄 Reset Status
              </button>

              <button 
                onClick={handleClearNetwork}
                className="action-btn btn-danger"
                title="Clear all data for this network"
                disabled={scanning}
              >
                🗑️ Clear Network
              </button>            
              <div className="monitoring-links">
                <button className="action-btn btn-grafana" onClick={openGrafana}>
                  📈 Open Grafana
                </button>
                <button className="action-btn btn-prometheus" onClick={openPrometheus}>
                  🔍 Open Prometheus
                </button>
              </div>

          </div>

          {scanning && (
            <div className="progress-bar">
              <div className="progress-fill" style={{ width: `${scanProgress}%` }}></div>
            </div>
          )}
        </div>

        {results.length > 0 && (
          <>
            <div className="stats-grid">
              <div className="stat-card glass stat-active">
                <div className="stat-icon">🟢</div>
                <div className="stat-content">
                  <div className="stat-value">{stats.up}</div>
                  <div className="stat-label">Active</div>
                </div>
              </div>
              <div className="stat-card glass stat-available">
                <div className="stat-icon">⚪</div>
                <div className="stat-content">
                  <div className="stat-value">{stats.down}</div>
                  <div className="stat-label">Available</div>
                </div>
              </div>
              <div className="stat-card glass stat-previous">
                <div className="stat-icon">🟡</div>
                <div className="stat-content">
                  <div className="stat-value">{stats.previously_used}</div>
                  <div className="stat-label">Previously Used</div>
                </div>
              </div>
              <div className="stat-card glass stat-reserved">
                <div className="stat-icon">🔒</div>
                <div className="stat-content">
                  <div className="stat-value">{stats.reserved}</div>
                  <div className="stat-label">Reserved</div>
                </div>
              </div>
              <div className="stat-card glass stat-notes">
                <div className="stat-icon">📝</div>
                <div className="stat-content">
                  <div className="stat-value">{stats.with_notes}</div>
                  <div className="stat-label">With Notes</div>
                </div>
              </div>
            </div>

            <div className="legend-bar glass">
              <div className="legend-item">
                <div className="legend-dot status-up"></div>
                <span>Active (Online Now)</span>
              </div>
              <div className="legend-item">
                <div className="legend-dot status-down"></div>
                <span>Available (Never Used)</span>
              </div>
              <div className="legend-item">
                <div className="legend-dot status-previously-used"></div>
                <span>Previously Used (Offline)</span>
              </div>
              <div className="legend-item">
                <div className="legend-dot status-reserved"></div>
                <span>Reserved</span>
              </div>
              <div className="legend-item">
                <span style={{marginLeft: '10px'}}>📝 Has Custom Notes</span>
              </div>
            </div>

            <div className="filter-bar glass">
              <button 
                className={`filter-btn ${filter === 'all' ? 'active' : ''}`}
                onClick={() => setFilter('all')}
              >
                All ({stats.total})
              </button>
              <button 
                className={`filter-btn ${filter === 'up' ? 'active' : ''}`}
                onClick={() => setFilter('up')}
              >
                Active ({stats.up})
              </button>
              <button 
                className={`filter-btn ${filter === 'down' ? 'active' : ''}`}
                onClick={() => setFilter('down')}
              >
                Available ({stats.down})
              </button>
              <button 
                className={`filter-btn ${filter === 'previously_used' ? 'active' : ''}`}
                onClick={() => setFilter('previously_used')}
              >
                Previously Used ({stats.previously_used})
              </button>
            </div>
          </>
        )}

        <div className="grid-panel glass">
          {results.length > 0 ? (
            <div className="grid-container">
              {renderGrid()}
            </div>
          ) : (
            <div className="empty-state">
              <svg width="100" height="100" viewBox="0 0 100 100" fill="none">
                <circle cx="50" cy="50" r="40" stroke="currentColor" strokeWidth="2" strokeDasharray="5,5"/>
                <path d="M50 30v40M30 50h40" stroke="currentColor" strokeWidth="2"/>
              </svg>
              <h3>No Scan Results</h3>
              <p>Click "Start Scan" to discover devices on your network</p>
            </div>
          )}
        </div>
      </div>

      {/* Details Modal */}
      {showDetails && selectedIP && (
        <div className={`modal-overlay ${showDetails ? 'show' : ''}`} onClick={closeDetails}>
          <div className="modal glass" onClick={(e) => e.stopPropagation()}>
            <button className="modal-close" onClick={closeDetails}>
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M18 6L6 18M6 6l12 12"/>
              </svg>
            </button>
            
            <div className="modal-header">
              <div className={`status-badge ${getStatusColor(selectedIP.status)}`}>
                {selectedIP.status === 'up' && '🟢'}
                {selectedIP.status === 'down' && '⚪'}
                {selectedIP.status === 'previously_used' && '🟡'}
                {selectedIP.status === 'reserved' && '🔒'}
                {' '}{selectedIP.status.toUpperCase().replace('_', ' ')}
              </div>
              <h2>{selectedIP.ip}</h2>
            </div>

            <div className="modal-body">
              {selectedIP.hostname && (
                <div className="detail-item">
                  <div className="detail-icon">🏷️</div>
                  <div className="detail-content">
                    <div className="detail-label">Hostname</div>
                    <div className="detail-value">{selectedIP.hostname}</div>
                  </div>
                </div>
              )}
              
              {selectedIP.mac_address && (
                <div className="detail-item">
                  <div className="detail-icon">🔌</div>
                  <div className="detail-content">
                    <div className="detail-label">MAC Address</div>
                    <div className="detail-value mono">{selectedIP.mac_address}</div>
                  </div>
                </div>
              )}
              
              {selectedIP.vendor && (
                <div className="detail-item">
                  <div className="detail-icon">🏢</div>
                  <div className="detail-content">
                    <div className="detail-label">Vendor</div>
                    <div className="detail-value">{selectedIP.vendor}</div>
                  </div>
                </div>
              )}
              
              {selectedIP.first_seen && (
                <div className="detail-item">
                  <div className="detail-icon">📅</div>
                  <div className="detail-content">
                    <div className="detail-label">First Seen</div>
                    <div className="detail-value">
                      {new Date(selectedIP.first_seen).toLocaleString()}
                    </div>
                  </div>
                </div>
              )}
              
              {selectedIP.last_seen && (
                <div className="detail-item">
                  <div className="detail-icon">🕒</div>
                  <div className="detail-content">
                    <div className="detail-label">Last Seen Online</div>
                    <div className="detail-value">
                      {new Date(selectedIP.last_seen).toLocaleString()}
                    </div>
                  </div>
                </div>
              )}
              
              {selectedIP.times_seen > 0 && (
                <div className="detail-item">
                  <div className="detail-icon">📊</div>
                  <div className="detail-content">
                    <div className="detail-label">Times Detected</div>
                    <div className="detail-value">{selectedIP.times_seen}</div>
                  </div>
                </div>
              )}
              
              <div className="detail-item notes-section">
                <div className="detail-icon">📝</div>
                <div className="detail-content">
                  <div className="detail-label">Custom Notes</div>
                  <div className="detail-value notes-value">
                    {selectedIP.notes || <em style={{color: 'var(--text-secondary)'}}>No notes added</em>}
                  </div>
                </div>
              </div>

              <div className="modal-actions">
                <button 
                  className="action-btn btn-notes"
                  onClick={() => handleEditNotesClick(selectedIP)}
                >
                  📝 Edit Notes
                </button>
                {selectedIP.status === 'reserved' ? (
                  <button 
                    className="action-btn btn-release"
                    onClick={() => handleReleaseIP(selectedIP.ip)}
                  >
                    🔓 Release IP
                  </button>
                ) : (
                  <button 
                    className="action-btn btn-reserve"
                    onClick={() => handleReserveClick(selectedIP)}
                  >
                    🔒 Reserve IP
                  </button>
                )}
                {selectedIP.status === 'down' && proxmoxConnected && (
                  <button 
                    className="action-btn btn-proxmox"
                    onClick={() => handleCreateVMClick(selectedIP)}
                  >
                    🖥️ Create Proxmox VM
                  </button>
                )}
                {selectedIP.status === 'up' && (
                  <>
                    <button 
                      className="action-btn btn-traffic"
                      onClick={() => handleTrafficTest(selectedIP)}
                    >
                      📊 Traffic Test
                    </button>

                    <button 
                      className="action-btn btn-check"
                      onClick={() => checkVMMonitoring(selectedIP.ip)}
                    >
                      🔍 Check Monitoring
                    </button>
                  </>
                )}

              </div>
            </div>
          </div>
        </div>
      )}

      {/* Reserve Modal */}
      {showReserveModal && (
        <div className="modal-overlay show" onClick={closeReserve}>
          <div className="modal glass" onClick={(e) => e.stopPropagation()}>
            <button className="modal-close" onClick={closeReserve}>
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M18 6L6 18M6 6l12 12"/>
              </svg>
            </button>
            
            <div className="modal-header">
              <h2>Reserve IP Address</h2>
              <p style={{color: 'var(--text-secondary)', fontSize: '1.1rem', marginTop: '10px'}}>
                {selectedIP?.ip}
              </p>
            </div>

            <div className="modal-body">
              <div className="form-group">
                <label>Reserved For *</label>
                <input
                  type="text"
                  value={reserveForm.reservedFor}
                  onChange={(e) => setReserveForm({...reserveForm, reservedFor: e.target.value})}
                  placeholder="Device name or purpose"
                  className="form-input"
                />
              </div>
              
              <div className="form-group">
                <label>Description</label>
                <textarea
                  value={reserveForm.description}
                  onChange={(e) => setReserveForm({...reserveForm, description: e.target.value})}
                  placeholder="Additional notes or reason for reservation"
                  className="form-input"
                  rows="3"
                />
              </div>
              
              <div className="form-group">
                <label>Reserved By</label>
                <input
                  type="text"
                  value={reserveForm.reservedBy}
                  onChange={(e) => setReserveForm({...reserveForm, reservedBy: e.target.value})}
                  placeholder="Your name or team"
                  className="form-input"
                />
              </div>

              <div className="modal-actions">
                <button 
                  className="action-btn btn-cancel"
                  onClick={closeReserve}
                >
                  Cancel
                </button>
                <button 
                  className="action-btn btn-confirm"
                  onClick={handleReserveSubmit}
                  disabled={!reserveForm.reservedFor}
                >
                  🔒 Confirm Reservation
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
      {/* Network Modal */}
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

      {/* Notes Modal */}
      {showNotesModal && selectedIP && (
        <div className="modal-overlay show" onClick={closeNotes}>
          <div className="modal glass" onClick={(e) => e.stopPropagation()}>
            <button className="modal-close" onClick={closeNotes}>
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M18 6L6 18M6 6l12 12"/>
              </svg>
            </button>
            
            <div className="modal-header">
              <h2>📝 Custom Notes</h2>
              <p style={{color: 'var(--text-secondary)', fontSize: '1.1rem', marginTop: '10px'}}>
                {selectedIP?.ip}
              </p>
            </div>

            <div className="modal-body">
              <div className="form-group">
                <label>Add Your Custom Comments</label>
                <textarea
                  value={notesForm}
                  onChange={(e) => setNotesForm(e.target.value)}
                  placeholder="Add any notes about this IP address...
Examples:
• Device description
• Owner/department
• Purpose or function
• Configuration details
• Contact information
• Maintenance notes"
                  className="form-input notes-textarea"
                  rows="8"
                  autoFocus
                />
              </div>

              <div className="notes-help">
                <strong>💡 Tip:</strong> Notes are saved permanently and visible with a 📝 icon on the grid
              </div>

              <div className="modal-actions">
                <button 
                  className="action-btn btn-cancel"
                  onClick={closeNotes}
                >
                  Cancel
                </button>
                <button 
                  className="action-btn btn-confirm"
                  onClick={handleNotesSubmit}
                >
                  💾 Save Notes
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Proxmox Modal */}
      {showProxmoxModal && selectedIP && (
        <div className="modal-overlay show" onClick={closeProxmoxModal}>
          <div className="modal glass proxmox-modal" onClick={(e) => e.stopPropagation()}>
            <button className="modal-close" onClick={closeProxmoxModal}>
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M18 6L6 18M6 6l12 12"/>
              </svg>
            </button>

            <div className="modal-header">
              <h2>🖥️ Create Proxmox VM</h2>
              <p style={{color: 'var(--text-secondary)', fontSize: '1.1rem', marginTop: '10px'}}>
                IP Address: {selectedIP?.ip}
              </p>
            </div>
      
            <div className="modal-body">
              <div className="form-group">
                <label>VM Name *</label>
                <input
                  type="text"
                  value={proxmoxForm.vm_name}
                  onChange={(e) => setProxmoxForm({...proxmoxForm, vm_name: e.target.value})}
                  placeholder="my-ubuntu-vm"
                  className="form-input"
                  autoFocus
                />
              </div>

              {proxmoxTemplates.length > 0 && (
                <div className="form-group">
                  <label>Template (Optional)</label>
                  <select
                    value={proxmoxForm.template_id || ''}
                    onChange={(e) => setProxmoxForm({...proxmoxForm, template_id: e.target.value ? parseInt(e.target.value) : null})}
                    className="form-input"
                  >
                    <option value="">Create from scratch</option>
                    {proxmoxTemplates.map(template => (
                      <option key={template.vmid} value={template.vmid}>
                        {template.name} (ID: {template.vmid})
                      </option>
                    ))}
                  </select>
                </div>
              )}

              <div className="form-row">
                <div className="form-group">
                  <label>CPU Cores</label>
                  <input
                    type="number"
                    min="1"
                    max="32"
                    value={proxmoxForm.cores}
                    onChange={(e) => setProxmoxForm({...proxmoxForm, cores: parseInt(e.target.value)})}
                    className="form-input"
                  />
                </div>

                <div className="form-group">
                  <label>Memory (MB)</label>
                  <input
                    type="number"
                    min="512"
                    step="512"
                    value={proxmoxForm.memory}
                    onChange={(e) => setProxmoxForm({...proxmoxForm, memory: parseInt(e.target.value)})}
                    className="form-input"
                  />
                </div>
              </div>

              <div className="form-group">
                <label>Disk Size (GB)</label>
                <input
                  type="number"
                  min="8"
                  value={proxmoxForm.disk_size}
                  onChange={(e) => setProxmoxForm({...proxmoxForm, disk_size: parseInt(e.target.value)})}
                  className="form-input"
                />
              </div>

              <div className="form-row">
                <div className="form-group">
                  <label>Gateway</label>
                  <input
                    type="text"
                    value={proxmoxForm.gateway}
                    onChange={(e) => setProxmoxForm({...proxmoxForm, gateway: e.target.value})}
                    className="form-input"
                  />
                </div>

                <div className="form-group">
                  <label>DNS Server</label>
                  <input
                    type="text"
                    value={proxmoxForm.nameserver}
                    onChange={(e) => setProxmoxForm({...proxmoxForm, nameserver: e.target.value})}
                    className="form-input"
                  />
                </div>
              </div>

              <div className="form-group">
                <label className="checkbox-label">
                  <input
                    type="checkbox"
                    checked={proxmoxForm.start_vm}
                    onChange={(e) => setProxmoxForm({...proxmoxForm, start_vm: e.target.checked})}
                  />
                  <span>Start VM after creation</span>
                </label>
              </div>
            
              <div className="proxmox-info">
                <strong>💡 What happens:</strong>
                <ul>
                  <li>VM will be created on Proxmox with the specified configuration</li>
                  <li>Static IP {selectedIP?.ip} will be assigned to the VM</li>
                  <li>IP will be automatically reserved in IP Manager</li>
                </ul>
              </div>
            
              <div className="modal-actions">
                <button 
                  className="action-btn btn-cancel"
                  onClick={closeProxmoxModal}
                >
                  Cancel
                </button>
                <button 
                  className="action-btn btn-confirm"
                  onClick={handleProxmoxSubmit}
                  disabled={!proxmoxForm.vm_name}
                >
                  🖥️ Create VM
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Traffic Test Modal */}
      {showTrafficModal && trafficSource && (
        <div className="modal-overlay show" onClick={() => setShowTrafficModal(false)}>
          <div className="modal glass traffic-modal" onClick={(e) => e.stopPropagation()}>
            <button className="modal-close" onClick={() => setShowTrafficModal(false)}>
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M18 6L6 18M6 6l12 12"/>
              </svg>
            </button>

            <div className="modal-header">
              <h2>📊 Network Traffic Test</h2>
              <p style={{color: 'var(--text-secondary)', fontSize: '1rem', marginTop: '10px'}}>
                Source: {trafficSource.ip} {trafficSource.hostname && `(${trafficSource.hostname})`}
              </p>
            </div>

            <div className="modal-body">
              <div className="form-group">
                <label>Target VM *</label>
                <select 
                  value={trafficTarget}
                  onChange={(e) => setTrafficTarget(e.target.value)}
                  className="form-input"
                >
                  <option value="">Select target VM...</option>
                  {results.filter(r => r.status === 'up' && r.ip !== trafficSource.ip).map(vm => (
                    <option key={vm.ip} value={vm.ip}>
                      {vm.ip} {vm.hostname ? `- ${vm.hostname}` : ''} {vm.vendor ? `(${vm.vendor})` : ''}
                    </option>
                  ))}
                </select>
              </div>

              <div className="form-group">
                <label>Protocol</label>
                <div className="protocol-selector">
                  <button
                    className={`protocol-btn ${trafficConfig.protocol === 'tcp' ? 'active' : ''}`}
                    onClick={() => setTrafficConfig({...trafficConfig, protocol: 'tcp'})}
                  >
                    TCP
                  </button>
                  <button
                    className={`protocol-btn ${trafficConfig.protocol === 'udp' ? 'active' : ''}`}
                    onClick={() => setTrafficConfig({...trafficConfig, protocol: 'udp'})}
                  >
                    UDP
                  </button>
                </div>
              </div>

              <div className="form-row">
                <div className="form-group">
                  <label>Duration (seconds)</label>
                  <input
                    type="number"
                    min="10"
                    max="300"
                    value={trafficConfig.duration}
                    onChange={(e) => setTrafficConfig({...trafficConfig, duration: parseInt(e.target.value)})}
                    className="form-input"
                  />
                </div>

                <div className="form-group">
                  <label>Bandwidth</label>
                  <select
                    value={trafficConfig.bandwidth}
                    onChange={(e) => setTrafficConfig({...trafficConfig, bandwidth: e.target.value})}
                    className="form-input"
                  >
                    <option value="10M">10 Mbps</option>
                    <option value="100M">100 Mbps</option>
                    <option value="500M">500 Mbps</option>
                    <option value="1G">1 Gbps</option>
                    <option value="10G">10 Gbps</option>
                  </select>
                </div>
              </div>

              <div className="form-row">
                <div className="form-group">
                  <label>Parallel Streams</label>
                  <input
                    type="number"
                    min="1"
                    max="10"
                    value={trafficConfig.parallel}
                    onChange={(e) => setTrafficConfig({...trafficConfig, parallel: parseInt(e.target.value)})}
                    className="form-input"
                  />
                </div>

                <div className="form-group">
                  <label className="checkbox-label">
                    <input
                      type="checkbox"
                      checked={trafficConfig.reverse}
                      onChange={(e) => setTrafficConfig({...trafficConfig, reverse: e.target.checked})}
                    />
                    <span>Reverse (server sends)</span>
                  </label>
                </div>
              </div>

              <div className="traffic-info">
                <strong>💡 What will happen:</strong>
                <ul>
                  <li>iperf3 client runs on {trafficSource.ip}</li>
                  <li>Sends {trafficConfig.protocol.toUpperCase()} traffic to {trafficTarget || 'target'}</li>
                  <li>Test runs for {trafficConfig.duration} seconds</li>
                  <li>Results shown in Grafana dashboard</li>
                  <li>Metrics collected by Prometheus</li>
                </ul>
              </div>

              <div className="modal-actions">
                <button 
                  className="action-btn btn-cancel"
                  onClick={() => setShowTrafficModal(false)}
                >
                  Cancel
                </button>
                <button 
                  className="action-btn btn-confirm"
                  onClick={handleStartTraffic}
                  disabled={!trafficTarget}
                >
                  🚀 Start Test
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Test Results Modal */}
      {showResults && testResults && (
        <div className="modal-overlay show" onClick={() => setShowResults(false)}>
          <div className="modal glass results-modal" onClick={(e) => e.stopPropagation()}>
            <button className="modal-close" onClick={() => setShowResults(false)}>
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M18 6L6 18M6 6l12 12"/>
              </svg>
            </button>

            <div className="modal-header">
              <h2>📊 Test Results</h2>
              <p>Test ID: {testResults.test_id}</p>
            </div>

            <div className="modal-body">
              {testResults.status === 'completed' ? (
                <div className="results-content">
                  <div className="result-summary">
                    <div className="result-item">
                      <div className="result-label">Source</div>
                      <div className="result-value">{testResults.source}</div>
                    </div>
                    <div className="result-item">
                      <div className="result-label">Target</div>
                      <div className="result-value">{testResults.target}</div>
                    </div>
                    <div className="result-item">
                      <div className="result-label">Protocol</div>
                      <div className="result-value">{testResults.protocol.toUpperCase()}</div>
                    </div>
                  </div>

                  <div className="result-metrics">
                    <div className="metric-card">
                      <div className="metric-value">{testResults.bandwidth_mbps} Mbps</div>
                      <div className="metric-label">Average Bandwidth</div>
                    </div>

                    <div className="metric-card">
                      <div className="metric-value">{(testResults.bytes_transferred / 1048576).toFixed(2)} MB</div>
                      <div className="metric-label">Data Transferred</div>
                    </div>

                    {testResults.protocol === 'tcp' && (
                      <div className="metric-card">
                        <div className="metric-value">{testResults.retransmits || 0}</div>
                        <div className="metric-label">Retransmits</div>
                      </div>
                    )}

                    {testResults.protocol === 'udp' && (
                      <>
                        <div className="metric-card">
                          <div className="metric-value">{testResults.jitter_ms?.toFixed(2) || 0} ms</div>
                          <div className="metric-label">Jitter</div>
                        </div>

                        <div className="metric-card">
                          <div className="metric-value">{testResults.lost_percent?.toFixed(2) || 0}%</div>
                          <div className="metric-label">Packet Loss</div>
                        </div>
                      </>
                    )}
                  </div>

                  <button 
                    className="action-btn btn-primary"
                    onClick={openGrafana}
                    style={{width: '100%', marginTop: '20px'}}
                  >
                    📈 View Detailed Graphs in Grafana
                  </button>
                </div>
              ) : (
                <div className="results-error">
                  <p>Test failed: {testResults.error}</p>
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Active Tests Sidebar */}
      {activeTests.length > 0 && (
        <div className="active-tests-sidebar">
          <h3>Active Tests</h3>
          {activeTests.map(test => (
            <div key={test.test_id} className={`test-item test-${test.status}`}>
              <div className="test-header">
                {test.source_ip} → {test.target_ip}
              </div>
              <div className="test-details">
                {test.protocol.toUpperCase()} • {test.status}
              </div>
            </div>
          ))}
        </div>
      )}

    </div>
  );
}

export default App;
