<?php
header("Content-Type: application/json");
require_once 'db_config.php';

try {
    // 1. Add 2FA columns to users
    $conn->exec("ALTER TABLE `users` ADD COLUMN IF NOT EXISTS `two_factor_enabled` TINYINT(1) DEFAULT 0");
    $conn->exec("ALTER TABLE `users` ADD COLUMN IF NOT EXISTS `can_manage_db` TINYINT(1) DEFAULT 1");
    $conn->exec("ALTER TABLE `users` ADD COLUMN IF NOT EXISTS `can_view_analytics` TINYINT(1) DEFAULT 1");
    $conn->exec("ALTER TABLE `users` ADD COLUMN IF NOT EXISTS `otp_code` VARCHAR(10) DEFAULT NULL");
    $conn->exec("ALTER TABLE `users` ADD COLUMN IF NOT EXISTS `otp_expiry` DATETIME DEFAULT NULL");

    // 2. Add OTP columns to residents
    $conn->exec("ALTER TABLE `residents` ADD COLUMN IF NOT EXISTS `otp_code` VARCHAR(10) DEFAULT NULL");
    $conn->exec("ALTER TABLE `residents` ADD COLUMN IF NOT EXISTS `otp_expiry` DATETIME DEFAULT NULL");

    // 3. Create access_logs table
    $conn->exec("CREATE TABLE IF NOT EXISTS `access_logs` (
      `id` int(11) NOT NULL AUTO_INCREMENT,
      `user_id` int(11) DEFAULT NULL,
      `username` varchar(100) NOT NULL,
      `action` varchar(255) NOT NULL,
      `ip_address` varchar(45) DEFAULT NULL,
      `timestamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    // 4. Create password_resets table if not exists (often used for OTP storage)
    $conn->exec("CREATE TABLE IF NOT EXISTS `password_resets` (
      `id` int(11) NOT NULL AUTO_INCREMENT,
      `email` varchar(255) NOT NULL,
      `token` varchar(255) NOT NULL,
      `expiry` datetime NOT NULL,
      PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    echo json_encode(["success" => true, "message" => "Database schema updated successfully!"]);
} catch (PDOException $e) {
    echo json_encode(["success" => false, "message" => "Error updating database: " . $e->getMessage()]);
}
?>