<?php
/**
 * This script handles automatic daily backups.
 * It can be triggered by a Cron Job or called from other scripts.
 */
include_once 'db_config.php';

if (!function_exists('generate_sql_dump_auto')) {
    function generate_sql_dump_auto($conn) {
        $sql = "-- Garbage Sis Automatic Daily Backup\n";
        $sql .= "-- Generated: " . date('Y-m-d H:i:s') . "\n";
        $sql .= "SET FOREIGN_KEY_CHECKS=0;\n\n";

        $tables = array();
        $result = $conn->query("SHOW TABLES");
        while ($row = $result->fetch(PDO::FETCH_NUM)) {
            $tables[] = $row[0];
        }

        foreach ($tables as $table) {
            $sql .= "DROP TABLE IF EXISTS `$table`;\n";
            $row2 = $conn->query("SHOW CREATE TABLE `$table`")->fetch(PDO::FETCH_NUM);
            $sql .= $row2[1] . ";\n\n";

            $result = $conn->query("SELECT * FROM `$table`");
            while ($row = $result->fetch(PDO::FETCH_NUM)) {
                $sql .= "INSERT INTO `$table` VALUES(";
                $values = array();
                foreach ($row as $val) {
                    if (isset($val)) {
                        $values[] = $conn->quote($val);
                    } else {
                        $values[] = "NULL";
                    }
                }
                $sql .= implode(",", $values);
                $sql .= ");\n";
            }
            $sql .= "\n\n";
        }
        $sql .= "SET FOREIGN_KEY_CHECKS=1;";
        return $sql;
    }
}

function check_and_perform_auto_backup($conn) {
    try {
        // 1. Check if auto-backup is enabled
        $stmt = $conn->prepare("SELECT COUNT(*) FROM users WHERE role = 'admin' AND auto_backup = 1");
        $stmt->execute();
        if ($stmt->fetchColumn() == 0) {
            return ["success" => false, "message" => "Auto-backup feature is disabled in settings."];
        }

        $backup_dir = 'backups/';
        if (!file_exists($backup_dir)) {
            mkdir($backup_dir, 0777, true);
        }

        $today = date('Y-m-d');
        $last_backup_file = $backup_dir . 'last_auto_backup.txt';

        // 2. Check if already backed up today
        if (file_exists($last_backup_file)) {
            $last_date = trim(file_get_contents($last_backup_file));
            if ($last_date === $today) {
                return ["success" => true, "message" => "Backup already performed today.", "date" => $today];
            }
        }

        // 3. Perform backup
        $filename = 'auto_backup_' . $today . '.sql';
        $filepath = $backup_dir . $filename;
        $sql_content = generate_sql_dump_auto($conn);

        if (file_put_contents($filepath, $sql_content)) {
            file_put_contents($last_backup_file, $today);

            $protocol = isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? "https" : "http";
            $host = $_SERVER['HTTP_HOST'];
            $path = dirname($_SERVER['PHP_SELF']);
            $url = "$protocol://$host$path/$filepath";

            return [
                "success" => true,
                "message" => "Automatic daily backup generated successfully",
                "filename" => $filename,
                "url" => $url
            ];
        } else {
            throw new Exception("Could not write backup file.");
        }
    } catch (Exception $e) {
        return ["success" => false, "message" => "Error: " . $e->getMessage()];
    }
}

// If run directly (from Task Scheduler or URL)
if (basename(__FILE__) == basename($_SERVER['SCRIPT_FILENAME'])) {
    header("Content-Type: application/json");
    $result = check_and_perform_auto_backup($conn);
    echo json_encode($result);
}
?>
