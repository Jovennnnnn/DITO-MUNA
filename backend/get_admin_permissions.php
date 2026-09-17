<?php
header("Content-Type: application/json");
require_once 'db_config.php';

$user_id = $_GET['user_id'] ?? null;

if ($user_id) {
    try {
        $stmt = $conn->prepare("SELECT two_factor_enabled, can_manage_db, can_view_analytics FROM users WHERE user_id = ?");
        $stmt->execute([$user_id]);
        $permissions = $stmt->fetch(PDO::FETCH_ASSOC);

        if ($permissions) {
            echo json_encode([
                "success" => true,
                "data" => $permissions
            ]);
        } else {
            echo json_encode(["success" => false, "message" => "User not found"]);
        }
    } catch (PDOException $e) {
        echo json_encode(["success" => false, "message" => "Database Error: " . $e->getMessage()]);
    }
} else {
    echo json_encode(["success" => false, "message" => "User ID required"]);
}
?>