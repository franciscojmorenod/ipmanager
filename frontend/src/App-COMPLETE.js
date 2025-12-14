import React, { useState, useEffect } from 'react';
import './App.css';

function App() {
  // Network and scanning state
  const [networks, setNetworks] = useState(['192.168.0']);
  const [currentNetwork, setCurrentNetwork] = useState('192.168.0');
  const [ipData, setIpData] = useState({});
  const [scanning, setScanning] = useState(false);
  
  // IP details and modals
  const [selectedIP, setSelectedIP] = useState(null);
  const [showReserveModal, setShowReserveModal] = useState(false);
  const [reserveDescription, setReserveDescription] = useState('');
  const [editingNote, setEditingNote] = useState(null);
  const [noteText, setNoteText] = useState('');
  
  // VM creation state
  const [showVMModal, setShowVMModal] = useState(false);
  const [vmConfig, setVmConfig] = useState({
    name: '',
    template: 'ubuntu-22-template',
    cores: 2,
    memory: 2048,
    disk_size: 32
  });
  
  // Traffic monitoring state
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

  // Auto-scan on load and network change
  useEffect(() => {
    scanNetwork(currentNetwork);
    const interval = setInterval(() => scanNetwork(currentNetwork), 30000);
    return () => clearInterval(interval);
  }, [currentNetwork]);

  // Load active tests periodically
  useEffect(() => {
    loadActiveTests();
    const interval = setInterval(loadActiveTests, 5000);
    return () => clearInterval(interval);
  }, []);

  const scanNetwork = async (network) => {
    setScanning(true);
    try {
      const response = await fetch(`http://localhost:8000/api/scan/${network}`);
      const data = await response.json();
      setIpData(data);
    } catch (error) {
      console.error('Scan failed:', error);
    }
    setScanning(false);
  };

  const loadActiveTests = async () => {
    try {
      const response = await fetch('http://localhost:8000/api/traffic/active');
      const data = await response.json();
      setActiveTests(data.active || []);
    } catch (error) {
      console.error('Failed to load active tests:', error);
    }
  };

  const handleIPClick = async (ip) => {
    try {
      const response = await fetch(`http://localhost:8000/api/ip/${ip}`);
      const data = await response.json();
      setSelectedIP(data);
    } catch (error) {
      console.error('Failed to fetch IP details:', error);
    }
  };

  const handleReserve = async () => {
    try {
      await fetch(`http://localhost:8000/api/reserve/${selectedIP.ip}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ description: reserveDescription })
      });
      setShowReserveModal(false);
      setReserveDescription('');
      scanNetwork(currentNetwork);
      setSelectedIP(null);
    } catch (error) {
      console.error('Reservation failed:', error);
    }
  };

  const handleRelease = async (ip) => {
    try {
      await fetch(`http://localhost:8000/api/release/${ip}`, { method: 'POST' });
      scanNetwork(currentNetwork);
      setSelectedIP(null);
    } catch (error) {
      console.error('Release failed:', error);
    }
  };

  const handleSaveNote = async () => {
    try {
      await fetch(`http://localhost:8000/api/note/${editingNote}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ note: noteText })
      });
      setEditingNote(null);
      setNoteText('');
      scanNetwork(currentNetwork);
      if (selectedIP && selectedIP.ip === editingNote) {
        handleIPClick(editingNote);
      }
    } catch (error) {
      console.error('Failed to save note:', error);
    }
  };

  const handleCreateVM = async () => {
    try {
      const response = await fetch(`http://localhost:8000/api/proxmox/create-vm`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          ip: selectedIP.ip,
          ...vmConfig
        })
      });
      
      if (response.ok) {
        const result = await response.json();
        alert(`VM created successfully!\nVMID: ${result.vmid}\nIP: ${result.ip}`);
        setShowVMModal(false);
        scanNetwork(currentNetwork);
        setSelectedIP(null);
      } else {
        const error = await response.json();
        alert(`Failed to create VM: ${error.detail}`);
      }
    } catch (error) {
      console.error('VM creation failed:', error);
      alert('Failed to create VM. Check console for details.');
    }
  };

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
        setShowTrafficModal(false);
        alert(`Traffic test started!\nTest ID: ${data.test_id}\nDuration: ${trafficConfig.duration}s\n\nWatch progress in the sidebar and Grafana!`);
        pollTestResults(data.test_id);
      } else {
        alert(`Failed to start test: ${data.detail || 'Unknown error'}`);
      }
    } catch (error) {
      console.error('Traffic test failed:', error);
      alert('Failed to start traffic test. Check backend logs.');
    }
  };

  const pollTestResults = async (testId) => {
    const maxAttempts = 120;
    let attempts = 0;
    
    const poll = setInterval(async () => {
      attempts++;
      
      try {
        const response = await fetch(`http://localhost:8000/api/traffic/status/${testId}`);
        const data = await response.json();
        
        if (data.status === 'completed' || data.status === 'failed') {
          clearInterval(poll);
          
          const resultsResponse = await fetch(`http://localhost:8000/api/traffic/results/${testId}`);
          const results = await resultsResponse.json();
          
          setTestResults(results);
          setShowResults(true);
        }
        
        if (attempts >= maxAttempts) {
          clearInterval(poll);
        }
      } catch (error) {
        console.error('Failed to poll test results:', error);
        clearInterval(poll);
      }
    }, 5000);
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
        alert(`✓ VM ${ip} is ready for monitoring!\n\n` +
              `✓ node_exporter running\n` +
              `✓ iperf3 server running\n` +
              `✓ Metrics available (${data.metrics_count || 0} metrics)`);
      } else {
        alert(`⚠ VM ${ip} needs setup\n\n` +
              `node_exporter: ${data.node_exporter_running ? '✓' : '✗'}\n` +
              `iperf3: ${data.iperf3_running ? '✓' : '✗'}\n` +
              `metrics: ${data.metrics_available ? '✓' : '✗'}\n\n` +
              `Run prepare-vm.sh on the VM first.`);
      }
    } catch (error) {
      console.error('Failed to check VM:', error);
      alert('Failed to check VM monitoring status.');
    }
  };

  const getStatusColor = (status) => {
    switch(status) {
      case 'up': return '#4ade80';
      case 'down': return '#6b7280';
      case 'previously_used': return '#fbbf24';
      case 'reserved': return '#60a5fa';
      default: return '#6b7280';
    }
  };

  const getAvailableTargets = () => {
    return Object.entries(ipData)
      .filter(([ip, data]) => data.status === 'up' && ip !== trafficSource?.ip)
      .map(([ip]) => ip);
  };

  const openGrafana = () => {
    window.open('http://192.168.0.100:3001', '_blank');
  };

  const openPrometheus = () => {
    window.open('http://192.168.0.100:9090', '_blank');
  };

  return (
    <div className="App">
      <header className="app-header">
        <h1>🌐 IP Manager</h1>
        <div className="header-controls">
          <select 
            value={currentNetwork} 
            onChange={(e) => setCurrentNetwork(e.target.value)}
            className="network-select"
          >
            {networks.map(net => (
              <option key={net} value={net}>{net}.0/24</option>
            ))}
          </select>
          <button 
            onClick={() => scanNetwork(currentNetwork)} 
            disabled={scanning}
            className="scan-btn"
          >
            {scanning ? '⏳ Scanning...' : '🔄 Scan'}
          </button>
          <button onClick={openGrafana} className="monitoring-btn grafana-btn">
            📈 Grafana
          </button>
          <button onClick={openPrometheus} className="monitoring-btn prometheus-btn">
            🔍 Prometheus
          </button>
        </div>
      </header>

      <div className="main-container">
        <div className="ip-grid-container">
          <div className="ip-grid">
            {Object.entries(ipData).map(([ip, data]) => (
              <div 
                key={ip}
                className={`ip-cell ${data.is_localhost ? 'localhost' : ''}`}
                style={{ backgroundColor: getStatusColor(data.status) }}
                onClick={() => handleIPClick(ip)}
              >
                <div className="ip-number">.{ip.split('.')[3]}</div>
                {data.hostname && <div className="hostname">{data.hostname}</div>}
                {data.description && <div className="description">{data.description}</div>}
              </div>
            ))}
          </div>
        </div>

        {activeTests.length > 0 && (
          <div className="active-tests-sidebar">
            <h3>Active Traffic Tests</h3>
            {activeTests.map(test => (
              <div key={test.test_id} className="active-test-item">
                <div className="test-route">
                  {test.source_ip} → {test.target_ip}
                </div>
                <div className="test-protocol">{test.protocol.toUpperCase()}</div>
                <div className="test-spinner">⏳</div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* IP Details Modal */}
      {selectedIP && (
        <div className="modal-overlay" onClick={() => setSelectedIP(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <h2>IP Details: {selectedIP.ip}</h2>
            
            <div className="detail-section">
              <p><strong>Status:</strong> {selectedIP.status}</p>
              <p><strong>Hostname:</strong> {selectedIP.hostname || 'N/A'}</p>
              <p><strong>MAC Address:</strong> {selectedIP.mac_address || 'N/A'}</p>
              <p><strong>Times Seen:</strong> {selectedIP.times_seen}</p>
              <p><strong>First Seen:</strong> {selectedIP.first_seen ? new Date(selectedIP.first_seen).toLocaleString() : 'N/A'}</p>
              <p><strong>Last Seen:</strong> {selectedIP.last_seen ? new Date(selectedIP.last_seen).toLocaleString() : 'N/A'}</p>
              {selectedIP.description && <p><strong>Description:</strong> {selectedIP.description}</p>}
            </div>

            <div className="note-section">
              <h3>Notes</h3>
              {editingNote === selectedIP.ip ? (
                <div>
                  <textarea 
                    value={noteText} 
                    onChange={(e) => setNoteText(e.target.value)}
                    className="note-input"
                    placeholder="Enter notes..."
                  />
                  <button onClick={handleSaveNote} className="action-btn">💾 Save</button>
                  <button onClick={() => setEditingNote(null)} className="action-btn">❌ Cancel</button>
                </div>
              ) : (
                <div>
                  <p>{selectedIP.note || 'No notes'}</p>
                  <button 
                    onClick={() => {
                      setEditingNote(selectedIP.ip);
                      setNoteText(selectedIP.note || '');
                    }}
                    className="action-btn"
                  >
                    ✏️ Edit Note
                  </button>
                </div>
              )}
            </div>

            <div className="action-buttons">
              {selectedIP.status === 'available' && (
                <>
                  <button 
                    onClick={() => setShowReserveModal(true)}
                    className="action-btn btn-reserve"
                  >
                    📌 Reserve
                  </button>
                  <button 
                    onClick={() => setShowVMModal(true)}
                    className="action-btn btn-vm"
                  >
                    🖥️ Create Proxmox VM
                  </button>
                </>
              )}
              
              {selectedIP.status === 'reserved' && (
                <button 
                  onClick={() => handleRelease(selectedIP.ip)}
                  className="action-btn btn-release"
                >
                  🔓 Release
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
              
              <button 
                onClick={() => setSelectedIP(null)}
                className="action-btn btn-close"
              >
                ❌ Close
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Reserve Modal */}
      {showReserveModal && (
        <div className="modal-overlay" onClick={() => setShowReserveModal(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <h2>Reserve IP: {selectedIP.ip}</h2>
            <input 
              type="text"
              value={reserveDescription}
              onChange={(e) => setReserveDescription(e.target.value)}
              placeholder="Enter description (e.g., 'Web Server')"
              className="reserve-input"
            />
            <div className="action-buttons">
              <button onClick={handleReserve} className="action-btn">✓ Reserve</button>
              <button onClick={() => setShowReserveModal(false)} className="action-btn">✗ Cancel</button>
            </div>
          </div>
        </div>
      )}

      {/* VM Creation Modal */}
      {showVMModal && (
        <div className="modal-overlay" onClick={() => setShowVMModal(false)}>
          <div className="modal vm-modal" onClick={(e) => e.stopPropagation()}>
            <h2>Create Proxmox VM: {selectedIP.ip}</h2>
            
            <div className="vm-config-form">
              <label>
                VM Name:
                <input 
                  type="text"
                  value={vmConfig.name}
                  onChange={(e) => setVmConfig({...vmConfig, name: e.target.value})}
                  placeholder="e.g., web-server-01"
                  className="vm-input"
                />
              </label>

              <label>
                Template:
                <select 
                  value={vmConfig.template}
                  onChange={(e) => setVmConfig({...vmConfig, template: e.target.value})}
                  className="vm-select"
                >
                  <option value="ubuntu-22-template">Ubuntu 22.04</option>
                  <option value="ubuntu-24-template">Ubuntu 24.04</option>
                </select>
              </label>

              <label>
                CPU Cores:
                <input 
                  type="number"
                  value={vmConfig.cores}
                  onChange={(e) => setVmConfig({...vmConfig, cores: parseInt(e.target.value)})}
                  min="1"
                  max="8"
                  className="vm-input"
                />
              </label>

              <label>
                Memory (MB):
                <input 
                  type="number"
                  value={vmConfig.memory}
                  onChange={(e) => setVmConfig({...vmConfig, memory: parseInt(e.target.value)})}
                  min="512"
                  max="8192"
                  step="512"
                  className="vm-input"
                />
              </label>

              <label>
                Disk Size (GB):
                <input 
                  type="number"
                  value={vmConfig.disk_size}
                  onChange={(e) => setVmConfig({...vmConfig, disk_size: parseInt(e.target.value)})}
                  min="10"
                  max="500"
                  className="vm-input"
                />
              </label>
            </div>

            <div className="action-buttons">
              <button onClick={handleCreateVM} className="action-btn btn-create">🚀 Create VM</button>
              <button onClick={() => setShowVMModal(false)} className="action-btn btn-cancel">❌ Cancel</button>
            </div>
          </div>
        </div>
      )}

      {/* Traffic Test Modal */}
      {showTrafficModal && (
        <div className="modal-overlay" onClick={() => setShowTrafficModal(false)}>
          <div className="modal traffic-modal" onClick={(e) => e.stopPropagation()}>
            <h2>🚀 Network Traffic Test</h2>
            
            <div className="traffic-config">
              <div className="traffic-route">
                <div className="route-box source">
                  <div className="route-label">Source</div>
                  <div className="route-ip">{trafficSource?.ip}</div>
                </div>
                <div className="route-arrow">→</div>
                <div className="route-box target">
                  <div className="route-label">Target</div>
                  <select 
                    value={trafficTarget}
                    onChange={(e) => setTrafficTarget(e.target.value)}
                    className="target-select"
                  >
                    <option value="">Select target VM...</option>
                    {getAvailableTargets().map(ip => (
                      <option key={ip} value={ip}>{ip}</option>
                    ))}
                  </select>
                </div>
              </div>

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

              <label>
                Duration (seconds):
                <input 
                  type="number"
                  value={trafficConfig.duration}
                  onChange={(e) => setTrafficConfig({...trafficConfig, duration: parseInt(e.target.value)})}
                  min="10"
                  max="300"
                  className="traffic-input"
                />
              </label>

              <label>
                Bandwidth:
                <select 
                  value={trafficConfig.bandwidth}
                  onChange={(e) => setTrafficConfig({...trafficConfig, bandwidth: e.target.value})}
                  className="traffic-select"
                >
                  <option value="10M">10 Mbps</option>
                  <option value="100M">100 Mbps</option>
                  <option value="1G">1 Gbps</option>
                  <option value="10G">10 Gbps</option>
                </select>
              </label>

              <label>
                Parallel Streams:
                <input 
                  type="number"
                  value={trafficConfig.parallel}
                  onChange={(e) => setTrafficConfig({...trafficConfig, parallel: parseInt(e.target.value)})}
                  min="1"
                  max="10"
                  className="traffic-input"
                />
              </label>

              <label className="checkbox-label">
                <input 
                  type="checkbox"
                  checked={trafficConfig.reverse}
                  onChange={(e) => setTrafficConfig({...trafficConfig, reverse: e.target.checked})}
                />
                Reverse direction (server sends)
              </label>
            </div>

            <div className="action-buttons">
              <button 
                onClick={handleStartTraffic} 
                className="action-btn btn-start-traffic"
                disabled={!trafficTarget}
              >
                🚀 Start Test
              </button>
              <button 
                onClick={() => setShowTrafficModal(false)} 
                className="action-btn btn-cancel"
              >
                ❌ Cancel
              </button>
            </div>

            <div className="traffic-help">
              <p>💡 <strong>Tip:</strong> Open Grafana to watch live network graphs during the test!</p>
            </div>
          </div>
        </div>
      )}

      {/* Test Results Modal */}
      {showResults && testResults && (
        <div className="modal-overlay" onClick={() => setShowResults(false)}>
          <div className="modal results-modal" onClick={(e) => e.stopPropagation()}>
            <h2>📊 Traffic Test Results</h2>
            
            <div className="results-header">
              <div className="result-route">
                <span className="result-ip">{testResults.source}</span>
                <span className="result-arrow">→</span>
                <span className="result-ip">{testResults.target}</span>
              </div>
              <div className="result-protocol">{testResults.protocol?.toUpperCase()}</div>
            </div>

            <div className="results-grid">
              <div className="result-card">
                <div className="result-label">Bandwidth</div>
                <div className="result-value">{testResults.bandwidth_mbps || 0} Mbps</div>
              </div>

              <div className="result-card">
                <div className="result-label">Data Transferred</div>
                <div className="result-value">
                  {((testResults.bytes_transferred || 0) / 1024 / 1024).toFixed(2)} MB
                </div>
              </div>

              {testResults.protocol === 'tcp' && (
                <div className="result-card">
                  <div className="result-label">Retransmits</div>
                  <div className="result-value">{testResults.retransmits || 0}</div>
                </div>
              )}

              {testResults.protocol === 'udp' && (
                <>
                  <div className="result-card">
                    <div className="result-label">Jitter</div>
                    <div className="result-value">{(testResults.jitter_ms || 0).toFixed(2)} ms</div>
                  </div>

                  <div className="result-card">
                    <div className="result-label">Packet Loss</div>
                    <div className="result-value">{(testResults.lost_percent || 0).toFixed(2)}%</div>
                  </div>
                </>
              )}
            </div>

            <div className="action-buttons">
              <button onClick={openGrafana} className="action-btn btn-grafana">
                📈 View in Grafana
              </button>
              <button onClick={() => setShowResults(false)} className="action-btn btn-close">
                ✓ Close
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default App;
