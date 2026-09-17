<?php
header("Content-Type: application/json");
require_once 'db_config.php';

$truck_id = $_POST['truck_id'] ?? null;

if ($truck_id) {
    try {
        // Check if truck is already assigned in users table
        $query = "SELECT 1 FROM users WHERE preferred_truck = ?";
        $stmt = $conn->prepare($query);
        $stmt->execute([$truck_id]);

        if ($stmt->fetch()) {
            echo json_encode(["success" => true, "message" => "Truck is already assigned"]);
        } else {
            echo json_encode(["success" => false, "message" => "Truck is available"]);
        }
    } catch (PDOException $e) {
        echo json_encode(["success" => false, "message" => "Error: " . $e->getMessage()]);
    }
} else {
    echo json_encode(["success" => false, "message" => "No truck ID provided"]);
}
?>
