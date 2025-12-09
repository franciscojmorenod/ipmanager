-- IP Manager Database Schema
-- Creates tables for tracking IP addresses and node history

CREATE TABLE IF NOT EXISTS nodes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    ip_address VARCHAR(15) NOT NULL UNIQUE,
    subnet VARCHAR(15) NOT NULL,
    last_octet INT NOT NULL,
    status ENUM('up', 'down', 'previously_used', 'reserved') DEFAULT 'down',
    hostname VARCHAR(255),
    mac_address VARCHAR(17),
    vendor VARCHAR(255),
    first_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    last_scanned TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    times_seen INT DEFAULT 1,
    notes TEXT,
    is_reserved BOOLEAN DEFAULT FALSE,
    reserved_by VARCHAR(100),
    reserved_at TIMESTAMP NULL,
    INDEX idx_ip (ip_address),
    INDEX idx_subnet (subnet),
    INDEX idx_status (status),
    INDEX idx_last_seen (last_seen)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS scan_history (
    id INT AUTO_INCREMENT PRIMARY KEY,
    subnet VARCHAR(15) NOT NULL,
    start_ip INT NOT NULL,
    end_ip INT NOT NULL,
    total_ips INT NOT NULL,
    active_ips INT NOT NULL,
    scan_duration FLOAT NOT NULL,
    scanned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_subnet (subnet),
    INDEX idx_scanned_at (scanned_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS ip_reservations (
    id INT AUTO_INCREMENT PRIMARY KEY,
    ip_address VARCHAR(15) NOT NULL,
    reserved_for VARCHAR(255) NOT NULL,
    description TEXT,
    reserved_by VARCHAR(100),
    reserved_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP NULL,
    is_active BOOLEAN DEFAULT TRUE,
    INDEX idx_ip (ip_address),
    INDEX idx_active (is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS node_history (
    id INT AUTO_INCREMENT PRIMARY KEY,
    node_id INT NOT NULL,
    ip_address VARCHAR(15) NOT NULL,
    status ENUM('up', 'down') NOT NULL,
    hostname VARCHAR(255),
    mac_address VARCHAR(17),
    vendor VARCHAR(255),
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (node_id) REFERENCES nodes(id) ON DELETE CASCADE,
    INDEX idx_node (node_id),
    INDEX idx_recorded_at (recorded_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Insert some example data for testing
INSERT INTO nodes (ip_address, subnet, last_octet, status, hostname, notes) 
VALUES 
    ('192.168.1.1', '192.168.1', 1, 'reserved', 'Gateway', 'Network Gateway - Do Not Use')
ON DUPLICATE KEY UPDATE status=status;
