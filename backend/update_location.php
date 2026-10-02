<?php
require_once 'db_config.php';
$user_id = $_POST['user_id'] ?? null;
$lat = $_POST['latitude'] ?? null;
$lng = $_POST['longitude'] ?? null;
$truck_id = $_POST['truck_id'] ?? null;
$speed = $_POST['speed'] ?? 0;
$status = $_POST['status'] ?? 'active';
$is_full = (isset($_POST['is_full']) && $_POST['is_full'] == 'true') ? 1 : 0;
if (!$user_id || !$lat || !$lng || !$truck_id) { echo json_encode(["success" => false]); exit; }
try {
    $stmt = $conn->prepare("SELECT name FROM users WHERE user_id = ?");
    $stmt->execute([$user_id]);
    $driver_name = $stmt->fetchColumn() ?: "Unknown Driver";
    $stmt = $conn->prepare("INSERT INTO truck_locations (truck_id, driver_name, latitude, longitude, speed, status, is_full, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, NOW()) ON DUPLICATE KEY UPDATE driver_name = VALUES(driver_name), latitude = VALUES(latitude), longitude = VALUES(longitude), speed = VALUES(speed), status = VALUES(status), is_full = VALUES(is_full), updated_at = NOW()");
    $stmt->execute([$truck_id, $driver_name, $lat, $lng, $speed, $status, $is_full]);
    echo json_encode(["success" => true]);
} catch (Exception $e) { echo json_encode(["success" => false, "message" => $e->getMessage()]); }
?>
