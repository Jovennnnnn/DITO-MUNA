<?php
header("Content-Type: application/json");
require_once 'db_config.php';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $userId = $_POST['user_id'] ?? null;
    $name = $_POST['name'] ?? null;
    $email = $_POST['email'] ?? null;
    $phone = $_POST['phone'] ?? null;
    $purok = $_POST['purok'] ?? null;

    if (!$userId || !$name || !$email || !$phone || !$purok) {
        echo json_encode(["success" => false, "message" => "Incomplete data"]);
        exit;
    }

    try {
        // We assume 'user_id' sent from app corresponds to 'resident_id' in residents table
        $query = "UPDATE residents SET name = ?, email = ?, phone = ?, purok = ? WHERE resident_id = ?";
        $stmt = $conn->prepare($query);
        $result = $stmt->execute([$name, $email, $phone, $purok, $userId]);

        if ($result) {
            echo json_encode(["success" => true, "message" => "Profile updated successfully"]);
        } else {
            echo json_encode(["success" => false, "message" => "Failed to update profile"]);
        }
    } catch (PDOException $e) {
        echo json_encode(["success" => false, "message" => "Database Error: " . $e->getMessage()]);
    }
} else {
    echo json_encode(["success" => false, "message" => "Invalid request method"]);
}
?>