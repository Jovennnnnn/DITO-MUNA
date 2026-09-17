<?php
header("Content-Type: application/json");
require_once 'db_config.php';

$username = $_POST['username'] ?? null;

if ($username) {
    try {
        // Check in both users and residents tables
        $query1 = "SELECT 1 FROM users WHERE username = ?";
        $stmt1 = $conn->prepare($query1);
        $stmt1->execute([$username]);

        $query2 = "SELECT 1 FROM residents WHERE username = ?";
        $stmt2 = $conn->prepare($query2);
        $stmt2->execute([$username]);

        if ($stmt1->fetch() || $stmt2->fetch()) {
            echo json_encode(["success" => true, "message" => "Username exists"]);
        } else {
            echo json_encode(["success" => false, "message" => "Username available"]);
        }
    } catch (PDOException $e) {
        echo json_encode(["success" => false, "message" => "Error: " . $e->getMessage()]);
    }
} else {
    echo json_encode(["success" => false, "message" => "No username provided"]);
}
?>
