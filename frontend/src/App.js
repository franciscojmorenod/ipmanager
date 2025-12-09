import React, { useState, useEffect } from 'react';
import './App.css';
import './network-styles.css'

function App() {
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

  useEffect(() => {
  discoverNetworks();
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
              {/* <input
                type="text"
                value={subnet}
                onChange={(e) => setSubnet(e.target.value)}
                placeholder="192.168.1"
                disabled={scanning}
                className="subnet-input"
              /> */}
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
    </div>
  );
}

export default App;
