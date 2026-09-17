<?php
header("Content-Type: application/json");
require_once 'db_config.php';

try {
    $stmt = $conn->prepare("SELECT * FROM access_logs ORDER BY timestamp DESC LIMIT 50");
    $stmt->execute();
    $logs = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        "success" => true,
        "logs" => $logs
    ]);
} catch (PDOException $e) {
    echo json_encode(["success" => false, "message" => "Database Error: " . $e->getMessage()]);
}
?>