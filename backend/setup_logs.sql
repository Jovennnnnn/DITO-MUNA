-- SQL Script to create necessary tables for Analytics and Reports
-- You can paste this into your phpMyAdmin or MySQL Workbench

CREATE TABLE IF NOT EXISTS `collection_logs` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `truck_id` varchar(50) NOT NULL,
  `zone_name` varchar(100) NOT NULL,
  `type` enum('ENTRY','EXIT') NOT NULL,
  `timestamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `truck_locations` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `truck_id` varchar(50) NOT NULL,
  `driver_name` varchar(100) DEFAULT NULL,
  `latitude` double NOT NULL,
  `longitude` double NOT NULL,
  `speed` double DEFAULT 0,
  `status` varchar(20) DEFAULT 'idle',
  `is_full` tinyint(1) DEFAULT 0,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Sample Data for testing
INSERT INTO `collection_logs` (truck_id, zone_name, type) VALUES
('GT-001', 'Purok 2', 'ENTRY'),
('GT-001', 'Purok 2', 'EXIT'),
('GT-001', 'Purok 3', 'ENTRY');
