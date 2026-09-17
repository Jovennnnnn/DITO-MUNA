<?php
header("Content-Type: application/json");
require_once 'db_config.php';

try {
    // We alias complaint_id as id and resident_id as user_id to match Kotlin models
    // We check if the residents table has the info, otherwise we use the complaints table
    $query = "SELECT
                c.complaint_id as id,
                c.resident_id as user_id,
                c.category,
                c.description,
                c.status,
                c.admin_response,
                c.created_at,
                COALESCE(r.name, 'Unknown Resident') as full_name,
                COALESCE(r.purok, 'Unknown') as purok
              FROM complaints c
              LEFT JOIN residents r ON c.resident_id = r.resident_id
              ORDER BY c.created_at DESC";

    $stmt = $conn->prepare($query);
    $stmt->execute();
    $complaints = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode(["success" => true, "data" => $complaints]);
} catch (PDOException $e) {
    echo json_encode(["success" => false, "message" => "Database Error: " . $e->getMessage()]);
}
?>
