<?php
header("Content-Type: application/json");
require_once 'db_config.php';

try {
    // Check complaints table structure
    $stmt = $conn->query("DESCRIBE complaints");
    $columns = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // Apply missing columns if they don't exist
    $columnNames = array_column($columns, 'Field');

    if (!in_array('is_archived', $columnNames)) {
        $conn->exec("ALTER TABLE complaints ADD COLUMN is_archived TINYINT(1) DEFAULT 0");
    }
    if (!in_array('deleted_by_resident', $columnNames)) {
        $conn->exec("ALTER TABLE complaints ADD COLUMN deleted_by_resident TINYINT(1) DEFAULT 0");
    }

    // Check users table structure
    $stmt = $conn->query("DESCRIBE users");
    $userColumns = array_column($stmt->fetchAll(PDO::FETCH_ASSOC), 'Field');

    if (!in_array('email_notifications', $userColumns)) {
        $conn->exec("ALTER TABLE users ADD COLUMN email_notifications TINYINT(1) DEFAULT 1");
    }
    if (!in_array('app_notifications', $userColumns)) {
        $conn->exec("ALTER TABLE users ADD COLUMN app_notifications TINYINT(1) DEFAULT 1");
    }
    if (!in_array('auto_backup', $userColumns)) {
        $conn->exec("ALTER TABLE users ADD COLUMN auto_backup TINYINT(1) DEFAULT 0");
    }

    // Check residents table structure
    $stmt = $conn->query("DESCRIBE residents");
    $residentColumns = array_column($stmt->fetchAll(PDO::FETCH_ASSOC), 'Field');

    if (!in_array('email_notifications', $residentColumns)) {
        $conn->exec("ALTER TABLE residents ADD COLUMN email_notifications TINYINT(1) DEFAULT 1");
    }
    if (!in_array('app_notifications', $residentColumns)) {
        $conn->exec("ALTER TABLE residents ADD COLUMN app_notifications TINYINT(1) DEFAULT 1");
    }

    // Check primary key name
    $stmt = $conn->query("SHOW KEYS FROM complaints WHERE Key_name = 'PRIMARY'");
    $pk = $stmt->fetch(PDO::FETCH_ASSOC);

    echo json_encode([
        "success" => true,
        "columns" => $columns,
        "primary_key" => $pk,
        "message" => "Database check/update complete."
    ]);
} catch (PDOException $e) {
    echo json_encode(["success" => false, "message" => "Error: " . $e->getMessage()]);
}
?>