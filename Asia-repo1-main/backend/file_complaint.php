<?php
header("Content-Type: application/json");
require_once 'db_config.php';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $resident_id = $_POST['resident_id'] ?? null;
    $category = $_POST['category'] ?? null;
    $description = $_POST['description'] ?? null;

    if ($resident_id && $category && $description) {
        try {
            $query = "INSERT INTO complaints (resident_id, category, description, status)
                      VALUES (?, ?, ?, 'pending')";
            $stmt = $conn->prepare($query);
            $stmt->execute([$resident_id, $category, $description]);

            echo json_encode(["success" => true, "message" => "Complaint filed successfully"]);
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
