<?php
header("Content-Type: application/json");
require_once 'db_config.php';

$phone = $_POST['phone'] ?? null;

if ($phone) {
    try {
        $query1 = "SELECT 1 FROM users WHERE phone = ?";
        $stmt1 = $conn->prepare($query1);
        $stmt1->execute([$phone]);

        $query2 = "SELECT 1 FROM residents WHERE phone = ?";
        $stmt2 = $conn->prepare($query2);
        $stmt2->execute([$phone]);

        if ($stmt1->fetch() || $stmt2->fetch()) {
            echo json_encode(["success" => true, "message" => "Phone number exists"]);
        } else {
            echo json_encode(["success" => false, "message" => "Phone number available"]);
        }
    } catch (PDOException $e) {
        echo json_encode(["success" => false, "message" => "Error: " . $e->getMessage()]);
    }
} else {
    echo json_encode(["success" => false, "message" => "No phone provided"]);
}
?>
