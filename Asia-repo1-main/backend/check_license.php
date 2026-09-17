<?php
header("Content-Type: application/json");
require_once 'db_config.php';

$license = $_POST['license_number'] ?? null;

if ($license) {
    try {
        $query = "SELECT 1 FROM users WHERE license_number = ?";
        $stmt = $conn->prepare($query);
        $stmt->execute([$license]);

        if ($stmt->fetch()) {
            echo json_encode(["success" => true, "message" => "License exists"]);
        } else {
            echo json_encode(["success" => false, "message" => "License available"]);
        }
    } catch (PDOException $e) {
        echo json_encode(["success" => false, "message" => "Error: " . $e->getMessage()]);
    }
} else {
    echo json_encode(["success" => false, "message" => "No license provided"]);
}
?>
