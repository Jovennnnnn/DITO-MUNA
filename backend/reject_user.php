<?php
header("Content-Type: application/json");
require_once 'db_config.php';

$data = json_decode(file_get_contents("php://input"));

if (!$data) {
    echo json_encode(["success" => false, "message" => "No data received"]);
    exit;
}

if (!empty($data->user_id) && !empty($data->role)) {
    try {
        $user_id = $data->user_id;
        $role = strtolower($data->role);

        // Permanently delete the rejected registration since it was never approved
        if ($role === 'resident') {
            $query = "DELETE FROM residents WHERE resident_id = ? AND is_archived = 1";
        } else {
            $query = "DELETE FROM users WHERE user_id = ? AND is_archived = 1";
        }

        $stmt = $conn->prepare($query);
        $stmt->execute([$user_id]);

        if ($stmt->rowCount() > 0) {
            echo json_encode(["success" => true, "message" => "Registration rejected and removed successfully."]);
        } else {
            echo json_encode(["success" => false, "message" => "User not found, already approved, or already removed."]);
        }

    } catch (PDOException $e) {
        echo json_encode(["success" => false, "message" => "Database Error: " . $e->getMessage()]);
    }
} else {
    echo json_encode(["success" => false, "message" => "Incomplete data"]);
}
?>
