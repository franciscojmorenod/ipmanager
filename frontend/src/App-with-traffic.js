import React, { useState, useEffect } from 'react';
import './App.css';

function App() {
  const [networks, setNetworks] = useState(['192.168.0']);
  const [currentNetwork, setCurrentNetwork] = useState('192.168.0');
  const [ipData, setIpData] = useState({});
  const [scanning, setScanning] = useState(false);
  const [selectedIP, setSelectedIP] = useState(null);
  const [showReserveModal, setShowReserveModal] = useState(false);
  const [reserveDescription, setReserveDescription] = useState('');
  const [editingNote, setEditingNote] = useState(null);
  const [noteText, setNoteText] = useState('');
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

  useEffect(() => {
    scanNetwork(currentNetwork);
    const interval = setInterval(() => scanNetwork(currentNetwork), 30000);
    return () => clearInterval(interval);
  }, [currentNetwork]);

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
      const response = await fetch('http://localhost:8000/api/traffic/active