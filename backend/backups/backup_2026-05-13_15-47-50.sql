-- Garbage Sis Database Backup
-- Generated: 2026-05-13 15:47:50
SET FOREIGN_KEY_CHECKS=0;

DROP TABLE IF EXISTS `alerts`;
CREATE TABLE `alerts` (
  `alert_id` int(11) NOT NULL AUTO_INCREMENT,
  `message` text DEFAULT NULL,
  `alert_type` varchar(50) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`alert_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



DROP TABLE IF EXISTS `areas`;
CREATE TABLE `areas` (
  `area_id` int(11) NOT NULL AUTO_INCREMENT,
  `area_name` varchar(100) DEFAULT NULL,
  `latitude` decimal(10,7) DEFAULT NULL,
  `longitude` decimal(10,7) DEFAULT NULL,
  `radius` int(11) DEFAULT NULL,
  PRIMARY KEY (`area_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



DROP TABLE IF EXISTS `collection_logs`;
CREATE TABLE `collection_logs` (
  `log_id` int(11) NOT NULL AUTO_INCREMENT,
  `truck_id` int(11) DEFAULT NULL,
  `area_id` int(11) DEFAULT NULL,
  `status` enum('collected','missed') DEFAULT NULL,
  `timestamp` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`log_id`),
  KEY `truck_id` (`truck_id`),
  KEY `area_id` (`area_id`),
  CONSTRAINT `collection_logs_ibfk_1` FOREIGN KEY (`truck_id`) REFERENCES `trucks` (`truck_id`),
  CONSTRAINT `collection_logs_ibfk_2` FOREIGN KEY (`area_id`) REFERENCES `areas` (`area_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



DROP TABLE IF EXISTS `complaints`;
CREATE TABLE `complaints` (
  `complaint_id` int(11) NOT NULL AUTO_INCREMENT,
  `resident_id` int(11) DEFAULT NULL,
  `category` varchar(50) DEFAULT NULL,
  `description` text DEFAULT NULL,
  `status` enum('pending','in_progress','resolved') DEFAULT 'pending',
  `admin_response` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`complaint_id`),
  KEY `resident_id` (`resident_id`),
  CONSTRAINT `complaints_ibfk_1` FOREIGN KEY (`resident_id`) REFERENCES `residents` (`resident_id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=9 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT INTO `complaints` VALUES('1','1','Missed Collection','bobo ang driver','resolved','wag kang matinggera bakla','2026-05-04 08:44:55');
INSERT INTO `complaints` VALUES('2','1','Spilled Waste','banana','resolved','banana','2026-05-08 09:04:15');
INSERT INTO `complaints` VALUES('3','3','Schedule Issue','hdbsjxhbdsh','resolved','ggvffg','2026-05-08 09:20:32');
INSERT INTO `complaints` VALUES('4','2','Driver Behavior','very maldita ang driver','resolved','di ka maganda wag kang mag inarte','2026-05-10 21:25:02');
INSERT INTO `complaints` VALUES('5','2','Driver Behavior','bastoe','pending',NULL,'2026-05-11 21:15:00');
INSERT INTO `complaints` VALUES('6','2','Schedule Issue','di dumaan','pending',NULL,'2026-05-13 08:53:49');
INSERT INTO `complaints` VALUES('7','2','Driver Behavior','bastos','pending',NULL,'2026-05-13 08:54:05');
INSERT INTO `complaints` VALUES('8','2','Uncollected Garbage','dapat ayusin ang pag collect','resolved','okay na','2026-05-13 08:54:18');


DROP TABLE IF EXISTS `driver_alert_history`;
CREATE TABLE `driver_alert_history` (
  `alert_id` int(11) NOT NULL AUTO_INCREMENT,
  `driver_id` int(11) NOT NULL,
  `alert_type` varchar(100) DEFAULT NULL,
  `alert_message` text DEFAULT NULL,
  `alert_status` varchar(20) DEFAULT 'UNREAD',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`alert_id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT INTO `driver_alert_history` VALUES('1','1','Route Alert','Route updated due to road closure.','UNREAD','2026-05-09 00:33:03');


DROP TABLE IF EXISTS `driver_logs`;
CREATE TABLE `driver_logs` (
  `driver_log_id` int(11) NOT NULL AUTO_INCREMENT,
  `driver_id` int(11) DEFAULT NULL,
  `action` text DEFAULT NULL,
  `timestamp` timestamp NOT NULL DEFAULT current_timestamp(),
  `status` varchar(20) NOT NULL DEFAULT 'ACTIVE',
  `started_at` datetime DEFAULT NULL,
  `paused_at` datetime DEFAULT NULL,
  `completed_at` datetime DEFAULT NULL,
  PRIMARY KEY (`driver_log_id`),
  KEY `driver_id` (`driver_id`),
  CONSTRAINT `driver_logs_ibfk_1` FOREIGN KEY (`driver_id`) REFERENCES `users` (`user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT INTO `driver_logs` VALUES('1','1','Driver started collection','2026-05-09 00:26:30','ACTIVE','2026-05-09 00:26:30',NULL,NULL);
INSERT INTO `driver_logs` VALUES('2','1','Driver paused collection','2026-05-09 00:26:43','PAUSED',NULL,'2026-05-09 00:26:43',NULL);
INSERT INTO `driver_logs` VALUES('3','1','Driver completed collection','2026-05-09 00:26:55','COMPLETED',NULL,NULL,'2026-05-09 00:26:55');


DROP TABLE IF EXISTS `driver_notification_settings`;
CREATE TABLE `driver_notification_settings` (
  `notification_setting_id` int(11) NOT NULL AUTO_INCREMENT,
  `driver_id` int(11) NOT NULL,
  `push_notifications` tinyint(1) DEFAULT 1,
  `route_notifications` tinyint(1) DEFAULT 1,
  `maintenance_notifications` tinyint(1) DEFAULT 1,
  `emergency_alerts` tinyint(1) DEFAULT 1,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`notification_setting_id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT INTO `driver_notification_settings` VALUES('1','1','1','1','1','1','2026-05-09 00:33:03');


DROP TABLE IF EXISTS `driver_performance`;
CREATE TABLE `driver_performance` (
  `performance_id` int(11) NOT NULL AUTO_INCREMENT,
  `driver_id` int(11) NOT NULL,
  `completed_routes` int(11) DEFAULT 0,
  `missed_routes` int(11) DEFAULT 0,
  `total_distance_km` decimal(10,2) DEFAULT 0.00,
  `average_speed` decimal(10,2) DEFAULT 0.00,
  `performance_rating` decimal(3,2) DEFAULT 0.00,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`performance_id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT INTO `driver_performance` VALUES('1','1','25','1','350.75','18.50','4.80','2026-05-09 00:33:03');


DROP TABLE IF EXISTS `driver_reports`;
CREATE TABLE `driver_reports` (
  `report_id` int(11) NOT NULL AUTO_INCREMENT,
  `driver_id` int(11) NOT NULL,
  `issue_title` varchar(255) DEFAULT NULL,
  `issue_description` text DEFAULT NULL,
  `issue_status` varchar(20) DEFAULT 'PENDING',
  `reported_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`report_id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT INTO `driver_reports` VALUES('1','1','GPS Signal Weak','GPS signal becomes unstable near remote areas.','PENDING','2026-05-09 00:33:03');


DROP TABLE IF EXISTS `driver_routes`;
CREATE TABLE `driver_routes` (
  `route_id` int(11) NOT NULL AUTO_INCREMENT,
  `driver_id` int(11) NOT NULL,
  `route_name` varchar(100) DEFAULT NULL,
  `route_date` date DEFAULT NULL,
  `start_location` varchar(255) DEFAULT NULL,
  `end_location` varchar(255) DEFAULT NULL,
  `total_distance_km` decimal(10,2) DEFAULT 0.00,
  `total_stops` int(11) DEFAULT 0,
  `route_status` varchar(20) DEFAULT 'PENDING',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`route_id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT INTO `driver_routes` VALUES('1','1','Morning Collection Route','2026-05-09','Purok 1','Landfill Site','12.50','6','ACTIVE','2026-05-09 00:33:03');


DROP TABLE IF EXISTS `driver_settings`;
CREATE TABLE `driver_settings` (
  `setting_id` int(11) NOT NULL AUTO_INCREMENT,
  `driver_id` int(11) NOT NULL,
  `gps_tracking` tinyint(1) NOT NULL DEFAULT 1,
  `voice_navigation` tinyint(1) NOT NULL DEFAULT 1,
  `route_alerts` tinyint(1) NOT NULL DEFAULT 1,
  `full_name` varchar(100) DEFAULT NULL,
  `contact_number` varchar(20) DEFAULT NULL,
  `assigned_truck` varchar(50) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`setting_id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT INTO `driver_settings` VALUES('1','1','0','0','0','Ricardo Dalisay','09191234567','Truck-01','2026-05-09 00:29:52','2026-05-09 00:31:24');


DROP TABLE IF EXISTS `eta_predictions`;
CREATE TABLE `eta_predictions` (
  `prediction_id` int(11) NOT NULL AUTO_INCREMENT,
  `truck_id` int(11) DEFAULT NULL,
  `area_id` int(11) DEFAULT NULL,
  `estimated_time` datetime DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`prediction_id`),
  KEY `truck_id` (`truck_id`),
  KEY `area_id` (`area_id`),
  CONSTRAINT `eta_predictions_ibfk_1` FOREIGN KEY (`truck_id`) REFERENCES `trucks` (`truck_id`),
  CONSTRAINT `eta_predictions_ibfk_2` FOREIGN KEY (`area_id`) REFERENCES `areas` (`area_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



DROP TABLE IF EXISTS `gps_logs`;
CREATE TABLE `gps_logs` (
  `gps_id` int(11) NOT NULL AUTO_INCREMENT,
  `truck_id` int(11) DEFAULT NULL,
  `latitude` decimal(10,7) DEFAULT NULL,
  `longitude` decimal(10,7) DEFAULT NULL,
  `speed` float DEFAULT NULL,
  `recorded_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`gps_id`),
  KEY `truck_id` (`truck_id`),
  CONSTRAINT `gps_logs_ibfk_1` FOREIGN KEY (`truck_id`) REFERENCES `trucks` (`truck_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



DROP TABLE IF EXISTS `notifications`;
CREATE TABLE `notifications` (
  `notification_id` int(11) NOT NULL AUTO_INCREMENT,
  `resident_id` int(11) DEFAULT NULL,
  `message` text DEFAULT NULL,
  `status` enum('pending','sent','failed') DEFAULT 'pending',
  `sent_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`notification_id`),
  KEY `resident_id` (`resident_id`),
  CONSTRAINT `notifications_ibfk_1` FOREIGN KEY (`resident_id`) REFERENCES `residents` (`resident_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



DROP TABLE IF EXISTS `residents`;
CREATE TABLE `residents` (
  `resident_id` int(11) NOT NULL AUTO_INCREMENT,
  `username` varchar(50) NOT NULL,
  `name` varchar(255) DEFAULT NULL,
  `password_hash` varchar(255) NOT NULL,
  `email` varchar(255) DEFAULT NULL,
  `phone` varchar(20) DEFAULT NULL,
  `purok` varchar(50) DEFAULT NULL,
  `complete_address` text NOT NULL,
  `area_id` int(11) DEFAULT NULL,
  `subscribed` tinyint(1) DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `is_archived` tinyint(1) DEFAULT 0,
  PRIMARY KEY (`resident_id`),
  UNIQUE KEY `username` (`username`),
  UNIQUE KEY `email` (`email`),
  KEY `area_id` (`area_id`),
  CONSTRAINT `residents_ibfk_1` FOREIGN KEY (`area_id`) REFERENCES `areas` (`area_id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT INTO `residents` VALUES('1','resident1','Juan Dela Cruz','$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi','resident@email.com',NULL,'Purok 1','Brgy. Balintawak, Lipa City',NULL,'1','2026-05-04 07:58:05','0');
INSERT INTO `residents` VALUES('2','resident','Shibuli Apple','$2y$10$8ZPioago56G25kCvoyVzEuhSuByPEbK6oAq0vtAphFmwqbdOqJ69m','shibuli@gmail.com','09221543697','Purok 2','purok 2 balintawak',NULL,'1','2026-05-08 09:11:02','0');
INSERT INTO `residents` VALUES('3','resi','resi buli','$2y$10$kMF4Xvxu1qsBG6y79BrM0e7hs5xki6XqxsZz.xo6vtPX2IK6Iu2..','resi@shibuli.com','09675582593','Purok 2','pablitos dormitory balintawak road',NULL,'1','2026-05-08 09:20:03','0');
INSERT INTO `residents` VALUES('4','Joven Espaldon','Joven Espaldon','$2y$10$wm7TzIRMSiXd4EV.hvfg9OouEA7cnorphg9VWBDHOdBuBDQyJLGYi','joven@gmail.com','+6391234567','Purok 3','Balintawal Lipa city',NULL,'1','2026-05-10 21:37:03','0');


DROP TABLE IF EXISTS `route_areas`;
CREATE TABLE `route_areas` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `route_id` int(11) DEFAULT NULL,
  `area_id` int(11) DEFAULT NULL,
  `sequence_order` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `route_id` (`route_id`),
  KEY `area_id` (`area_id`),
  CONSTRAINT `route_areas_ibfk_1` FOREIGN KEY (`route_id`) REFERENCES `routes` (`route_id`) ON DELETE CASCADE,
  CONSTRAINT `route_areas_ibfk_2` FOREIGN KEY (`area_id`) REFERENCES `areas` (`area_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



DROP TABLE IF EXISTS `routes`;
CREATE TABLE `routes` (
  `route_id` int(11) NOT NULL AUTO_INCREMENT,
  `route_name` varchar(100) DEFAULT NULL,
  PRIMARY KEY (`route_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



DROP TABLE IF EXISTS `truck_information`;
CREATE TABLE `truck_information` (
  `truck_info_id` int(11) NOT NULL AUTO_INCREMENT,
  `truck_number` varchar(50) DEFAULT NULL,
  `truck_model` varchar(100) DEFAULT NULL,
  `plate_number` varchar(50) DEFAULT NULL,
  `fuel_type` varchar(50) DEFAULT NULL,
  `capacity` varchar(50) DEFAULT NULL,
  `assigned_driver_id` int(11) DEFAULT NULL,
  `truck_status` varchar(20) DEFAULT 'ACTIVE',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`truck_info_id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT INTO `truck_information` VALUES('1','Truck-01','Isuzu Garbage Truck','ABC-1234','Diesel','10 Tons','1','ACTIVE','2026-05-09 00:33:03');


DROP TABLE IF EXISTS `truck_maintenance`;
CREATE TABLE `truck_maintenance` (
  `maintenance_id` int(11) NOT NULL AUTO_INCREMENT,
  `truck_id` int(11) NOT NULL,
  `maintenance_type` varchar(100) DEFAULT NULL,
  `maintenance_date` date DEFAULT NULL,
  `next_maintenance` date DEFAULT NULL,
  `remarks` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`maintenance_id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT INTO `truck_maintenance` VALUES('1','1','Oil Change','2026-05-09','2026-06-08','Routine maintenance','2026-05-09 00:33:03');


DROP TABLE IF EXISTS `trucks`;
CREATE TABLE `trucks` (
  `truck_id` int(11) NOT NULL AUTO_INCREMENT,
  `plate_number` varchar(50) DEFAULT NULL,
  `driver_id` int(11) DEFAULT NULL,
  `status` enum('active','collecting','full','inactive') DEFAULT 'inactive',
  PRIMARY KEY (`truck_id`),
  KEY `driver_id` (`driver_id`),
  CONSTRAINT `trucks_ibfk_1` FOREIGN KEY (`driver_id`) REFERENCES `users` (`user_id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



DROP TABLE IF EXISTS `users`;
CREATE TABLE `users` (
  `user_id` int(11) NOT NULL AUTO_INCREMENT,
  `username` varchar(50) NOT NULL,
  `name` varchar(100) NOT NULL,
  `email` varchar(100) NOT NULL,
  `password_hash` varchar(255) NOT NULL,
  `phone` varchar(20) DEFAULT NULL,
  `license_number` varchar(50) NOT NULL,
  `preferred_truck` varchar(20) DEFAULT NULL,
  `role` enum('admin','driver') NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `is_archived` tinyint(1) DEFAULT 0,
  PRIMARY KEY (`user_id`),
  UNIQUE KEY `username` (`username`),
  UNIQUE KEY `email` (`email`)
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT INTO `users` VALUES('1','admin','System Admin','admin@email.com','$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi',NULL,'ADMIN-000',NULL,'admin','2026-05-04 07:58:05','0');
INSERT INTO `users` VALUES('2','driver1','Ricardo Dalisay','driver@email.com','$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi',NULL,'ABC-12345','Truck-01','driver','2026-05-04 07:58:05','0');
INSERT INTO `users` VALUES('3','Nato','Nato Nato','nato@gmail.com','$2y$10$U1WPs5ZWh/pVUgcXoKjeV.Ruw1zjn4mwAFwzR5Ig6AgqpRVs7AA8a','09686735520','',NULL,'driver','2026-05-10 20:36:10','0');
INSERT INTO `users` VALUES('4','Steven Noblefranca','Steven Noblefranca','steven@gmail.com','$2y$10$v3CDsYZ3mRutoUp6U/oHIuVMMlnuvaQuo7xp/IMUPq.le.j6aw5yy','09123456789','',NULL,'driver','2026-05-10 21:57:15','0');


SET FOREIGN_KEY_CHECKS=1;