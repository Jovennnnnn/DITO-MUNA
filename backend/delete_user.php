<?php
header("Content-Type: application/json");
require_once 'db_config.php';

$data = json_decode(file_get_contents("php://input"));

if (!$data || !isset($data->user_id) || !isset($data->role)) {
    echo json_encode(["success" => false, "message" => "Invalid parameters"]);
    exit;
}

$user_id = $data->user_id;
$role = $data->role;

try {
    if ($role === 'resident') {
        $query = "DELETE FROM residents WHERE resident_id = ?";
    } else {
        $query = "DELETE FROM users WHERE user_id = ?";
    }

    $stmt = $conn->prepare($query);
    $stmt->execute([$user_id]);

    if ($stmt->rowCount() > 0) {
        echo json_encode(["success" => true, "message" => "User deleted permanently"]);
    } else {
        echo json_encode(["success" => false, "message" => "User not found"]);
    }

} catch (PDOException $e) {
    echo json_encode(["success" => false, "message" => "Database Error: " . $e->getMessage()]);
}
?>
