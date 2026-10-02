<?php
header("Content-Type: application/json");
require_once 'db_config.php';

$data = json_decode(file_get_contents("php://input"));

if (!empty($data->user_id) && !empty($data->role)) {
    try {
        $table = ($data->role === 'resident') ? "residents" : "users";
        $id_col = ($data->role === 'resident') ? "resident_id" : "user_id";

        $updateFields = [];
        $params = [];

        if (isset($data->email_notifications)) {
            $updateFields[] = "email_notifications = ?";
            $params[] = $data->email_notifications ? 1 : 0;
        }

        if (isset($data->app_notifications)) {
            $updateFields[] = "app_notifications = ?";
            $params[] = $data->app_notifications ? 1 : 0;
        }

        if ($data->role !== 'resident' && isset($data->auto_backup)) {
            $updateFields[] = "auto_backup = ?";
            $params[] = $data->auto_backup ? 1 : 0;
        }

        if (empty($updateFields)) {
            echo json_encode(["success" => false, "message" => "No settings to update"]);
            exit;
        }

        $sql = "UPDATE $table SET " . implode(", ", $updateFields) . " WHERE $id_col = ?";
        $params[] = $data->user_id;

        $stmt = $conn->prepare($sql);
        $stmt->execute($params);

        echo json_encode([
            "success" => true,
            "message" => "Settings updated successfully"
        ]);
    } catch (PDOException $e) {
        echo json_encode(["success" => false, "message" => "Database Error: " . $e->getMessage()]);
    }
} else {
    echo json_encode(["success" => false, "message" => "User ID and Role required"]);
}
?>