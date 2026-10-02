<?php
header("Content-Type: application/json");
require_once 'db_config.php';

// Support both JSON (Retrofit) and Form-Data (POST)
$data = json_decode(file_get_contents("php://input"), true);
$id = $_POST['id'] ?? $data['id'] ?? null;
$role = $_POST['role'] ?? $data['role'] ?? null;
$old_password = $_POST['old_password'] ?? $data['old_password'] ?? null;
$new_password = $_POST['new_password'] ?? $data['new_password'] ?? null;

if (empty($id) || empty($role) || empty($old_password) || empty($new_password)) {
    echo json_encode([
        "success" => false,
        "message" => "Fields are missing. Received ID: $id, Role: $role"
    ]);
    exit;
}

try {
    // Determine table and ID column based on role
    if ($role === 'resident') {
        $table = "residents";
        $id_column = "resident_id";
    } else {
        $table = "users";
        $id_column = "user_id";
    }

    // 1. Check if the user exists
    $stmt = $conn->prepare("SELECT password_hash FROM $table WHERE $id_column = :id");
    $stmt->bindParam(':id', $id);
    $stmt->execute();
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    if ($user) {
        // 2. Verify the old password
        if (password_verify($old_password, $user['password_hash'])) {
            // 3. Hash the new password
            $new_hashed_password = password_hash($new_password, PASSWORD_BCRYPT);

            // 4. Update the database
            $update_stmt = $conn->prepare("UPDATE $table SET password_hash = :new_pass WHERE $id_column = :id");
            $update_stmt->bindParam(':new_pass', $new_hashed_password);
            $update_stmt->bindParam(':id', $id);

            if ($update_stmt->execute()) {
                echo json_encode(["success" => true, "message" => "Password updated successfully"]);
            } else {
                echo json_encode(["success" => false, "message" => "Database update failed"]);
            }
        } else {
            echo json_encode(["success" => false, "message" => "Incorrect old password (Mali ang lumang password)"]);
        }
    } else {
        echo json_encode(["success" => false, "message" => "User ID $id not found in $table table"]);
    }
} catch (PDOException $e) {
    echo json_encode(["success" => false, "message" => "Database Error: " . $e->getMessage()]);
}
?>