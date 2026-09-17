<?php
require_once 'db_config.php';
$truck_id = $_POST['truck_id'] ?? null;
$zone_name = $_POST['zone_name'] ?? null;
$type = $_POST['type'] ?? null;
if (!$truck_id || !$zone_name || !$type) { echo json_encode(["success" => false]); exit; }
try {
    $stmt = $conn->prepare("INSERT INTO collection_logs (truck_id, zone_name, type, timestamp) VALUES (?, ?, ?, NOW())");
    $stmt->execute([$truck_id, $zone_name, $type]);
    echo json_encode(["success" => true]);
} catch (Exception $e) { echo json_encode(["success" => false, "message" => $e->getMessage()]); }
?>
