<?php
/**
 * DATABASE SNAPSHOT ENGINE (SQL DUMP)
 * Matches the user's provided SQL structure.
 */
header("Content-Type: application/json");
require_once 'db_config.php';
require_once 'cleanup_logic.php';

$backup_dir = 'backups/';
// Perform automatic cleanup before creating a new one
perform_snapshot_cleanup($backup_dir);

if (!file_exists($backup_dir)) {
    mkdir($backup_dir, 0777, true);
}

$filename = 'backup_' . date('Y-m-d_H-i-s') . '.sql';
$filepath = $backup_dir . $filename;

function generate_full_sql($conn, $db_name) {
    $sql = "-- Garbage Sis Database Backup\n";
    $sql .= "-- Generated: " . date('Y-m-d H:i:s') . "\n";
    $sql .= "SET FOREIGN_KEY_CHECKS=0;\n\n";

    $tables = $conn->query("SHOW TABLES")->fetchAll(PDO::FETCH_COLUMN);

    foreach ($tables as $table) {
        $sql .= "DROP TABLE IF EXISTS `$table`;\n";
        $create_table = $conn->query("SHOW CREATE TABLE `$table`")->fetch(PDO::FETCH_NUM);
        $sql .= $create_table[1] . ";\n\n";

        $rows = $conn->query("SELECT * FROM `$table`")->fetchAll(PDO::FETCH_NUM);
        foreach ($rows as $row) {
            $sql .= "INSERT INTO `$table` VALUES(";
            $vals = array_map(function($v) use ($conn) {
                return $v === null ? "NULL" : $conn->quote($v);
            }, $row);
            $sql .= implode(",", $vals) . ");\n";
        }
        $sql .= "\n\n";
    }
    $sql .= "SET FOREIGN_KEY_CHECKS=1;";
    return $sql;
}

try {
    $content = generate_full_sql($conn, $db_name);
    if (file_put_contents($filepath, $content)) {
        echo json_encode([
            "success" => true,
            "filename" => $filename,
            "url" => get_absolute_url($filepath)
        ]);
    } else {
        throw new Exception("Write Failed");
    }
} catch (Exception $e) {
    echo json_encode(["success" => false, "message" => $e->getMessage()]);
}
?>
