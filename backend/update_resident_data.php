<?php
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Headers: *");
header("Access-Control-Allow-Methods: POST, GET, OPTIONS");
header("Content-Type: application/json");

require_once 'db_config.php';

// Check OPTIONS request for CORS preflight
if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    exit(0);
}

// SWITCH TO STANDARD FORM DATA ($_POST) - High compatibility with browser security
$user_id = $_POST['user_id'] ?? null;
$role = $_POST['role'] ?? null;
$name = $_POST['name'] ?? null;
$phone = $_POST['phone'] ?? null;
$email = $_POST['email'] ?? null;
$username = $_POST['username'] ?? null;
$purok = $_POST['purok'] ?? null;

// Fallback to JSON if POST is empty (to be safe)
if (empty($user_id)) {
    $json_data = json_decode(file_get_contents("php://input"), true);
    $user_id = $json_data['user_id'] ?? null;
    $role = $json_data['role'] ?? null;
    $name = $json_data['name'] ?? null;
    $phone = $json_data['phone'] ?? null;
    $email = $json_data['email'] ?? null;
    $username = $json_data['username'] ?? null;
    $purok = $json_data['purok'] ?? null;
}

if (!empty($user_id) && !empty($role) && !empty($name)) {
    try {
        $table = "residents";
        $id_col = "resident_id";

        $updateFields = [];
        $params = [];

        $updateFields[] = "name = :name";
        $params[':name'] = $name;

        if ($phone !== null) {
            $updateFields[] = "phone = :phone";
            $params[':phone'] = $phone;
        }
        if ($email !== null) {
            $updateFields[] = "email = :email";
            $params[':email'] = $email;
        }
        if ($username !== null) {
            $updateFields[] = "username = :username";
            $params[':username'] = $username;
        }
        if ($purok !== null) {
            $updateFields[] = "purok = :purok";
            $params[':purok'] = $purok;
        }

        $sql = "UPDATE $table SET " . implode(", ", $updateFields) . " WHERE $id_col = :id";
        $params[':id'] = $user_id;

        $stmt = $conn->prepare($sql);
        $stmt->execute($params);

        // Fetch updated data
        $query = "SELECT * FROM $table WHERE $id_col = :id";
        $stmt = $conn->prepare($query);
        $stmt->execute([':id' => $user_id]);
        $updatedUser = $stmt->fetch(PDO::FETCH_ASSOC);

        echo json_encode([
            "success" => true,
            "message" => "Resident data saved successfully",
            "user" => $updatedUser
        ]);
    } catch (PDOException $e) {
        echo json_encode(["success" => false, "message" => "Database Error: " . $e->getMessage()]);
    }
} else {
    echo json_encode([
        "success" => false,
        "message" => "Incomplete form data. User ID or Name is missing.",
        "received_id" => $user_id
    ]);
}
?>
