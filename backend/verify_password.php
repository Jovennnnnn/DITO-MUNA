<?php
header("Content-Type: application/json");
require_once 'db_config.php';

// Support both JSON (Retrofit) and Form-Data (POST)
$data = json_decode(file_get_contents("php://input"), true);
$id = $_POST['id'] ?? $data['id'] ?? null;
$role = $_POST['role'] ?? $data['role'] ?? null;
$password = $_POST['password'] ?? $data['password'] ?? null;

if (empty($id) || empty($role) || empty($password)) {
    echo json_encode(["success" => false, "message" => "Missing fields"]);
    exit;
}

try {
    if ($role === 'resident') {
        $table = "residents";
        $id_col = "resident_id";
    } else {
        $table = "users";
        $id_col = "user_id";
    }

    $stmt = $conn->prepare("SELECT password_hash FROM $table WHERE $id_col = ?");
    $stmt->execute([$id]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    if ($user && password_verify($password, $user['password_hash'])) {
        echo json_encode(["success" => true]);
    } else {
        echo json_encode(["success" => false, "message" => "Incorrect password"]);
    }
} catch (PDOException $e) {
    echo json_encode(["success" => false, "message" => "Database Error: " . $e->getMessage()]);
}
?>