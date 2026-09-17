-- SQL to create access logs table and update users table for 2FA and permissions
CREATE TABLE IF NOT EXISTS `access_logs` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) DEFAULT NULL,
  `username` varchar(100) NOT NULL,
  `action` varchar(255) NOT NULL,
  `ip_address` varchar(45) DEFAULT NULL,
  `timestamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Add 2FA and Permissions columns to users table if they don't exist
-- Note: In a real migration we'd check existence, but for a setup script:
ALTER TABLE `users` ADD COLUMN IF NOT EXISTS `two_factor_enabled` tinyint(1) DEFAULT 0;
ALTER TABLE `users` ADD COLUMN IF NOT EXISTS `can_manage_db` tinyint(1) DEFAULT 1;
ALTER TABLE `users` ADD COLUMN IF NOT EXISTS `can_view_analytics` tinyint(1) DEFAULT 1;
