<?php
header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
require_once 'db_config.php';

try {
    // Select the latest non-zero location entry per truck/driver
    $query = "SELECT
                tl.id,
                tl.truck_id,
                tl.latitude,
                tl.longitude,
                tl.speed,
                tl.status,
                tl.updated_at,
                u.id as driver_id,
                u.plate_number,
                COALESCE(u.name, tl.driver_name, 'Driver') as driver_name,
                TIMESTAMPDIFF(SECOND, tl.updated_at, NOW()) as seconds_ago,
                IF(TIMESTAMPDIFF(SECOND, tl.updated_at, NOW()) <= 60 AND LOWER(tl.status) != 'offline', 1, 0) as is_online
              FROM truck_locations tl
              INNER JOIN (
                  SELECT truck_id, MAX(updated_at) as max_updated
                  FROM truck_locations
                  WHERE latitude IS NOT NULL AND latitude != 0 AND longitude IS NOT NULL AND longitude != 0
                  GROUP BY truck_id
              ) latest ON tl.truck_id = latest.truck_id AND tl.updated_at = latest.max_updated
              LEFT JOIN users u ON (tl.truck_id = u.preferred_truck OR u.id = tl.driver_id) AND u.role = 'driver' AND (u.is_archived IS NULL OR u.is_archived = 0)
              WHERE tl.latitude IS NOT NULL
                AND tl.latitude != 0
                AND tl.longitude IS NOT NULL
                AND tl.longitude != 0
              ORDER BY tl.updated_at DESC";

    $stmt = $conn->prepare($query);
    $stmt->execute();
    $locations = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // Format types properly
    foreach ($locations as &$loc) {
        $loc['id'] = (int)$loc['id'];
        $loc['latitude'] = (double)$loc['latitude'];
        $loc['longitude'] = (double)$loc['longitude'];
        $loc['speed'] = (double)$loc['speed'];
        $loc['is_online'] = (bool)$loc['is_online'];
        $loc['isOnline'] = (bool)$loc['is_online'];
        $loc['lastSeen'] = strtotime($loc['updated_at']) * 1000;
    }

    echo json_encode([
        "success" => true,
        "locations" => $locations,
        "data" => $locations
    ]);

} catch (PDOException $e) {
    echo json_encode([
        "success" => false,
        "message" => "Database Error: " . $e->getMessage(),
        "locations" => [],
        "data" => []
    ]);
}
?>
