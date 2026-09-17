<?php
header("Content-Type: application/json");
require_once 'db_config.php';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $complaint_id = $_POST['complaint_id'] ?? null;
    $status = $_POST['status'] ?? null;
    $admin_response = $_POST['admin_response'] ?? null;

    if ($complaint_id && $status) {
        try {
            $query = "UPDATE complaints SET status = ?, admin_response = ? WHERE complaint_id = ?";
            $stmt = $conn->prepare($query);
            $stmt->execute([$status, $admin_response, $complaint_id]);

            echo json_encode(["success" => true, "message" => "Complaint updated successfully"]);
        } catch (PDOException $e) {
            echo json_encode(["success" => false, "message" => "Database Error: " . $e->getMessage()]);
        }
    } else {
        echo json_encode(["success" => false, "message" => "Missing data"]);
    }
} else {
    echo json_encode(["success" => false, "message" => "Invalid request method"]);
}
?>
