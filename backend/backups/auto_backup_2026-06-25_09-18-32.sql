-- Garbage Sis Automatic Daily Backup
-- Generated: 2026-06-25 09:18:32
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
) ENGINE=InnoDB AUTO_INCREMENT=13 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT INTO `areas` VALUES('1','Purok 2','13.9402000','121.1638000','220');
INSERT INTO `areas` VALUES('2','Purok 3','13.9375000','121.1660000','230');
INSERT INTO `areas` VALUES('3','Purok 4','13.9430000','121.1625000','250');
INSERT INTO `areas` VALUES('4','Dos Riles','13.9358000','121.1595000','200');
INSERT INTO `areas` VALUES('5','Sentro','13.9388000','121.1645000','180');
INSERT INTO `areas` VALUES('6','San Isidro','13.9342000','121.1620000','210');
INSERT INTO `areas` VALUES('7','Paraiso','13.9325000','121.1602000','200');
INSERT INTO `areas` VALUES('8','Riverside','13.9365000','121.1678000','240');
INSERT INTO `areas` VALUES('9','Kalaw Street','13.9395000','121.1580000','150');
INSERT INTO `areas` VALUES('10','Home Subdivision','13.9415000','121.1565000','260');
INSERT INTO `areas` VALUES('11','Tanco Road / Ayala Highway','13.9312000','121.1705000','300');
INSERT INTO `areas` VALUES('12','Brixton Area','13.9382000','121.1552000','230');


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
  `deleted_by_resident` tinyint(1) DEFAULT 0,
  PRIMARY KEY (`complaint_id`),
  KEY `resident_id` (`resident_id`),
  CONSTRAINT `complaints_ibfk_1` FOREIGN KEY (`resident_id`) REFERENCES `residents` (`resident_id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=16 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT INTO `complaints` VALUES('1','1','Missed Collection','bobo ang driver','resolved','wag kang matinggera bakla','2026-05-04 00:44:55','0');
INSERT INTO `complaints` VALUES('2','1','Spilled Waste','banana','resolved','banana','2026-05-08 01:04:15','0');
INSERT INTO `complaints` VALUES('3','3','Schedule Issue','hdbsjxhbdsh','resolved','ggvffg','2026-05-08 01:20:32','0');
INSERT INTO `complaints` VALUES('4','2','Driver Behavior','very maldita ang driver','resolved','di ka maganda wag kang mag inarte','2026-05-10 13:25:02','0');
INSERT INTO `complaints` VALUES('5','2','Driver Behavior','bastoe','pending',NULL,'2026-05-11 13:15:00','1');
INSERT INTO `complaints` VALUES('6','2','Schedule Issue','di dumaan','resolved','padadaanin ko','2026-05-13 00:53:49','1');
INSERT INTO `complaints` VALUES('7','2','Driver Behavior','bastos','in_progress',NULL,'2026-05-13 00:54:05','1');
INSERT INTO `complaints` VALUES('8','2','Uncollected Garbage','dapat ayusin ang pag collect','resolved','okay na','2026-05-13 00:54:18','1');
INSERT INTO `complaints` VALUES('9','5','Driver Behavior','walang modo','resolved','ygv','2026-05-13 16:42:17','1');
INSERT INTO `complaints` VALUES('11','2','Driver Behavior','bastos po ang driver','resolved','ftvyby bytf','2026-05-14 11:40:24','0');
INSERT INTO `complaints` VALUES('12','6','Driver Behavior','Walang Kwenta','resolved','noted po','2026-05-16 02:51:50','1');
INSERT INTO `complaints` VALUES('13','8','Uncollected Garbage','ruamnaan dihti pero hindi naman nag notify','resolved','','2026-05-16 15:59:59','0');
INSERT INTO `complaints` VALUES('14','6','Schedule Issue','Hs7skwndjsmsnsbs','resolved','tfv','2026-05-17 01:33:34','1');
INSERT INTO `complaints` VALUES('15','8','Uncollected Garbage','di nakuha','pending',NULL,'2026-05-17 05:42:06','0');


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

INSERT INTO `driver_alert_history` VALUES('1','1','Route Alert','Route updated due to road closure.','UNREAD','2026-05-08 16:33:03');


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

INSERT INTO `driver_logs` VALUES('1','1','Driver started collection','2026-05-08 16:26:30','ACTIVE','2026-05-09 00:26:30',NULL,NULL);
INSERT INTO `driver_logs` VALUES('2','1','Driver paused collection','2026-05-08 16:26:43','PAUSED',NULL,'2026-05-09 00:26:43',NULL);
INSERT INTO `driver_logs` VALUES('3','1','Driver completed collection','2026-05-08 16:26:55','COMPLETED',NULL,NULL,'2026-05-09 00:26:55');


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

INSERT INTO `driver_notification_settings` VALUES('1','1','1','1','1','1','2026-05-08 16:33:03');


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

INSERT INTO `driver_performance` VALUES('1','1','25','1','350.75','18.50','4.80','2026-05-08 16:33:03');


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

INSERT INTO `driver_reports` VALUES('1','1','GPS Signal Weak','GPS signal becomes unstable near remote areas.','PENDING','2026-05-08 16:33:03');


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

INSERT INTO `driver_routes` VALUES('1','1','Morning Collection Route','2026-05-09','Purok 1','Landfill Site','12.50','6','ACTIVE','2026-05-08 16:33:03');


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

INSERT INTO `driver_settings` VALUES('1','1','0','0','0','Ricardo Dalisay','09191234567','Truck-01','2026-05-08 16:29:52','2026-05-08 16:31:24');


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



DROP TABLE IF EXISTS `password_resets`;
CREATE TABLE `password_resets` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `email` varchar(255) NOT NULL,
  `token` varchar(6) NOT NULL,
  `expiry` datetime NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `email` (`email`),
  KEY `token` (`token`)
) ENGINE=InnoDB AUTO_INCREMENT=12 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



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
) ENGINE=InnoDB AUTO_INCREMENT=9 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT INTO `residents` VALUES('1','resident1','Juan Dela Cruz','$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi','resident@email.com','09675552589','Purok 2','Brgy. Balintawak, Lipa City',NULL,'1','2026-05-03 23:58:05','1');
INSERT INTO `residents` VALUES('2','resident','Prince Barola','$2y$10$agl40dUKa9DSg4KFE4u.duS/ychHzQwLyP/NroSkcPkfANwNbPIky','princebarola191@gmail.com','09221543697','Purok 2','purok 2 balintawak',NULL,'1','2026-05-08 01:11:02','0');
INSERT INTO `residents` VALUES('3','resi','resi buli','$2y$10$kMF4Xvxu1qsBG6y79BrM0e7hs5xki6XqxsZz.xo6vtPX2IK6Iu2..','resi@shibuli.com','09675582593','Purok 2','pablitos dormitory balintawak road',NULL,'1','2026-05-08 01:20:03','1');
INSERT INTO `residents` VALUES('4','Joven Espaldon','Joven Espaldon','$2y$10$wm7TzIRMSiXd4EV.hvfg9OouEA7cnorphg9VWBDHOdBuBDQyJLGYi','joven@gmail.com','+6391234567','Purok 3','Balintawal Lipa city',NULL,'1','2026-05-10 13:37:03','1');
INSERT INTO `residents` VALUES('5','Althea','Althea Untalan','$2y$10$JfSQVXaygaKQW5ElAQKwxezl4Qc/WAQDKXVpZoRFhvCP3Yc66yxE6','Althea@gmail.com','12345678901','Purok 4','barangay balintawak purok dos',NULL,'1','2026-05-13 16:41:20','0');
INSERT INTO `residents` VALUES('6','Joven Noblefranca','Joven Noblefranca','$2y$10$WZB3wRFfsKQ2JUntJ0jGw.11TDEp0DGU6fFjg5rkBwpo9TBA73Avq','jovenoblefranca23@gmail.com','09123456789','Dos Riles','Balintawak',NULL,'1','2026-05-16 02:49:20','0');
INSERT INTO `residents` VALUES('8','Prince','Prince Barola','$2y$10$XvioiF12fZznJjapP1PQZ.hQhYlB5sb6NZS9UJK1.x9lfNKmUQht6','princebarola7@gmail.com','09231648270','Purok 2','barangray balintawak, pablitos dormitory',NULL,'1','2026-05-16 15:56:35','0');


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

INSERT INTO `truck_information` VALUES('1','Truck-01','Isuzu Garbage Truck','ABC-1234','Diesel','10 Tons','1','ACTIVE','2026-05-08 16:33:03');


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

INSERT INTO `truck_maintenance` VALUES('1','1','Oil Change','2026-05-09','2026-06-08','Routine maintenance','2026-05-08 16:33:03');


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
) ENGINE=InnoDB AUTO_INCREMENT=8 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT INTO `users` VALUES('1','admin','System Admin','princebarola191@gmail.com','$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi',NULL,'ADMIN-000',NULL,'admin','2026-05-03 23:58:05','0');
INSERT INTO `users` VALUES('6','Eman','Eman Masapol','Eman@gmail.com','$2y$10$HZ0pWwppnRCJ/aR7FIrubOlw/YsgcQetBshYHFH1.BMEWJgNjLG5.','09261345267','',NULL,'driver','2026-05-15 21:15:38','0');
INSERT INTO `users` VALUES('7','steve','Steve Espaldon','steve@gmail.com','$2y$10$qg5B5z3vJY.Le.Am3FqOEe365CUyPNhn5alEk8q9QZ99HV1vM7Hfa','09072759541','',NULL,'driver','2026-05-16 02:49:18','0');


SET FOREIGN_KEY_CHECKS=1;