<?php
header("Content-Type: application/json");
require_once 'db_config.php';

$user_id = $_GET['user_id'] ?? null;
$role = $_GET['role'] ?? 'admin';

if ($user_id) {
    try {
        $table = ($role === 'resident') ? "residents" : "users";
        $id_col = ($role === 'resident') ? "resident_id" : "user_id";

        $sql = "SELECT email_notifications, app_notifications" . ($role !== 'resident' ? ", auto_backup" : "") . " FROM $table WHERE $id_col = ?";
        $stmt = $conn->prepare($sql);
        $stmt->execute([$user_id]);
        $settings = $stmt->fetch(PDO::FETCH_ASSOC);

        if ($settings) {
            $data = [
                "email_notifications" => (bool)$settings['email_notifications'],
                "app_notifications" => (bool)$settings['app_notifications']
            ];
            if (isset($settings['auto_backup'])) {
                $data["auto_backup"] = (bool)$settings['auto_backup'];
            }

            echo json_encode([
                "success" => true,
                "data" => $data
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