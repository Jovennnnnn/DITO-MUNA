<?php
header("Content-Type: application/json");
require_once 'db_config.php';

$data = json_decode(file_get_contents("php://input"));

if (!empty($data->user_id) && isset($data->can_manage_db) && isset($data->can_view_analytics)) {
    try {
        $can_manage = $data->can_manage_db ? 1 : 0;
        $can_view = $data->can_view_analytics ? 1 : 0;

        $stmt = $conn->prepare("UPDATE users SET can_manage_db = ?, can_view_analytics = ? WHERE user_id = ?");
        $stmt->execute([$can_manage, $can_view, $data->user_id]);

        echo json_encode([
            "success" => true,
            "message" => "Permissions updated successfully"
        ]);
    } catch (PDOException $e) {
        echo json_encode(["success" => false, "message" => "Database Error: " . $e->getMessage()]);
    }
} else {
    echo json_encode(["success" => false, "message" => "Incomplete data"]);
}
?>