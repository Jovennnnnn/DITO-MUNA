<?php
header("Content-Type: application/json");
require_once 'db_config.php';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // Support both JSON and Form-Data
    $json = json_decode(file_get_contents('php://input'), true);
    $ids_raw = $_POST['complaint_ids'] ?? $json['complaint_ids'] ?? '';

    if (!empty($ids_raw)) {
        // Handle both Array and Comma-separated String
        $idArray = is_array($ids_raw) ? $ids_raw : explode(',', $ids_raw);
        $idArray = array_filter(array_map('trim', $idArray)); // Clean up

        if (empty($idArray)) {
            echo json_encode(["success" => false, "message" => "No valid IDs provided"]);
            exit;
        }

        try {
            // Determine ID column name (id or complaint_id)
            $columns = $conn->query("DESCRIBE complaints")->fetchAll(PDO::FETCH_COLUMN);
            $id_col = in_array('complaint_id', $columns) ? 'complaint_id' : 'id';

            // Create placeholders (?, ?, ?)
            $placeholders = str_repeat('?,', count($idArray) - 1) . '?';

            // PERMANENT BULK HARD DELETE
            $query = "DELETE FROM complaints WHERE $id_col IN ($placeholders)";
            $stmt = $conn->prepare($query);
            $stmt->execute($idArray);

            echo json_encode([
                "success" => true,
                "message" => count($idArray) . " complaints permanently deleted from database"
            ]);
        } catch (PDOException $e) {
            echo json_encode(["success" => false, "message" => "Database Error: " . $e->getMessage()]);
        }
    } else {
        echo json_encode(["success" => false, "message" => "No complaints selected for deletion"]);
    }
} else {
    echo json_encode(["success" => false, "message" => "Invalid request method"]);
}
?>
