<?php
header("Content-Type: application/json");
require_once 'db_config.php';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $json = json_decode(file_get_contents('php://input'), true);
    $complaint_id = $_POST['complaint_id'] ?? $json['complaint_id'] ?? $_REQUEST['complaint_id'] ?? null;
    $status = $_POST['status'] ?? $json['status'] ?? $_REQUEST['status'] ?? null;
    $admin_response = $_POST['admin_response'] ?? $json['admin_response'] ?? $_REQUEST['admin_response'] ?? null;

    if ($complaint_id && $status) {
        try {
            $columns = $conn->query("DESCRIBE complaints")->fetchAll(PDO::FETCH_COLUMN);
            $id_col = in_array('complaint_id', $columns) ? 'complaint_id' : 'id';

            $query = "UPDATE complaints SET status = ?, admin_response = ? WHERE $id_col = ?";
            $stmt = $conn->prepare($query);
            $stmt->execute([$status, $admin_response, $complaint_id]);

            echo json_encode(["success" => true, "message" => "Update successful"]);
        } catch (PDOException $e) {
            echo json_encode(["success" => false, "message" => "Database Error: " . $e->getMessage()]);
        }
    } else {
        echo json_encode(["success" => false, "message" => "Missing data: id=$complaint_id, status=$status"]);
    }
} else {
    echo json_encode(["success" => false, "message" => "Invalid request method"]);
}
?>
