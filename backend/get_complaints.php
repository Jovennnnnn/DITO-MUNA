<?php
header("Content-Type: application/json");
require_once 'db_config.php';

try {
    // 1. First, check which columns actually exist to avoid "Column not found" errors
    $columns_check = $conn->query("DESCRIBE complaints")->fetchAll(PDO::FETCH_COLUMN);

    // 2. Build the query dynamically or use fallbacks for missing columns
    $has_archived = in_array('is_archived', $columns_check);
    $has_deleted = in_array('deleted_by_resident', $columns_check);
    $has_response = in_array('admin_response', $columns_check);

    // Standardize IDs for both Mobile and Web
    // We check for 'complaint_id' first, fallback to 'id'
    $id_col = in_array('complaint_id', $columns_check) ? 'c.complaint_id' : 'c.id';
    $res_id_col = in_array('resident_id', $columns_check) ? 'c.resident_id' : 'c.user_id';

    $archived_val = $has_archived ? 'c.is_archived' : '0 as is_archived';
    $deleted_val = $has_deleted ? 'c.deleted_by_resident' : '0 as deleted_by_resident';
    $response_val = $has_response ? 'c.admin_response' : "'' as admin_response";

    $query = "SELECT
                $id_col as id,
                $id_col as complaint_id,
                $res_id_col as user_id,
                $res_id_col as resident_id,
                c.category,
                c.description,
                c.status,
                $response_val,
                c.created_at,
                $archived_val,
                $deleted_val,
                COALESCE(r.name, 'Unknown Resident') as full_name,
                COALESCE(r.purok, 'Unknown') as purok
              FROM complaints c
              LEFT JOIN residents r ON $res_id_col = r.resident_id
              ORDER BY c.created_at DESC";

    $stmt = $conn->prepare($query);
    $stmt->execute();
    $complaints = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        "success" => true,
        "data" => $complaints,
        "debug_info" => [
            "has_archived" => $has_archived,
            "has_deleted" => $has_deleted
        ]
    ]);
} catch (PDOException $e) {
    echo json_encode(["success" => false, "message" => "Database Error: " . $e->getMessage()]);
}
?>
