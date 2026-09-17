<?php
header("Content-Type: application/json");
require_once 'db_config.php';

try {
    // Fetch only trucks whose drivers are NOT archived
    $query = "SELECT tl.*, u.plate_number, u.name as driver_name, u.is_archived
              FROM truck_locations tl
              JOIN users u ON tl.truck_id = u.preferred_truck
              WHERE u.is_archived = 0
              AND tl.updated_at >= DATE_SUB(NOW(), INTERVAL 24 HOUR)";

    $stmt = $conn->prepare($query);
    $stmt->execute();
    $locations = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // Convert numeric strings to proper types
    foreach ($locations as &$loc) {
        $loc['id'] = (int)$loc['id'];
        $loc['latitude'] = (double)$loc['latitude'];
        $loc['longitude'] = (double)$loc['longitude'];
        $loc['speed'] = (double)$loc['speed'];
        $loc['is_full'] = (bool)$loc['is_full'];
    }

    echo json_encode([
        "success" => true,
        "data" => $locations
    ]);

} catch (PDOException $e) {
    echo json_encode(["success" => false, "message" => "Database Error: " . $e->getMessage()]);
}
?>
