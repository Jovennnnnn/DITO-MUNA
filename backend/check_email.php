<?php
header("Content-Type: application/json");
require_once 'db_config.php';

$email = $_POST['email'] ?? null;

if ($email) {
    try {
        // Check in both users and residents tables
        $query1 = "SELECT 1 FROM users WHERE email = ?";
        $stmt1 = $conn->prepare($query1);
        $stmt1->execute([$email]);

        $query2 = "SELECT 1 FROM residents WHERE email = ?";
        $stmt2 = $conn->prepare($query2);
        $stmt2->execute([$email]);

        if ($stmt1->fetch() || $stmt2->fetch()) {
            echo json_encode(["success" => true, "message" => "Email exists"]);
        } else {
            echo json_encode(["success" => false, "message" => "Email available"]);
        }
    } catch (PDOException $e) {
        echo json_encode(["success" => false, "message" => "Error: " . $e->getMessage()]);
    }
} else {
    echo json_encode(["success" => false, "message" => "No email provided"]);
}
?>
