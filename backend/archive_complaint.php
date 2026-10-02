<?php
header("Content-Type: application/json");
require_once 'db_config.php';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // Check both POST and JSON input
    $json = json_decode(file_get_contents('php://input'), true);
    $complaint_id = $_POST['complaint_id'] ?? $json['complaint_id'] ?? $_REQUEST['complaint_id'] ?? null;
    $is_archived = isset($_POST['is_archived']) ? $_POST['is_archived'] : ($json['is_archived'] ?? $_REQUEST['is_archived'] ?? null);

    if ($complaint_id !== null && $is_archived !== null) {
        try {
            // First, ensure the column exists
            $conn->exec("ALTER TABLE complaints ADD COLUMN IF NOT EXISTS is_archived TINYINT(1) DEFAULT 0");

            // Standardize ID column check
            $columns = $conn->query("DESCRIBE complaints")->fetchAll(PDO::FETCH_COLUMN);
            $id_col = in_array('complaint_id', $columns) ? 'complaint_id' : 'id';

            $query = "UPDATE complaints SET is_archived = ? WHERE $id_col = ?";
            $stmt = $conn->prepare($query);
            $stmt->execute([(int)$is_archived, $complaint_id]);

            echo json_encode(["success" => true, "message" => "Archive status updated"]);
        } catch (PDOException $e) {
            echo json_encode(["success" => false, "message" => "Database Error: " . $e->getMessage()]);
        }
    } else {
        echo json_encode(["success" => false, "message" => "Missing data: complaint_id=$complaint_id, is_archived=$is_archived"]);
    }
} else {
    echo json_encode(["success" => false, "message" => "Invalid request method"]);
}
?>
