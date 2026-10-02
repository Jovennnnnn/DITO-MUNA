<?php
header("Content-Type: application/json");
require_once 'db_config.php';

// Support both JSON (Retrofit/Flutter) and Form-Data (POST)
$json_data = json_decode(file_get_contents("php://input"), true);
$user_id = $_POST['user_id'] ?? $json_data['user_id'] ?? null;
$role = $_POST['role'] ?? $json_data['role'] ?? null;
$name = $_POST['name'] ?? $json_data['name'] ?? null;
$phone = $_POST['phone'] ?? $json_data['phone'] ?? null;
$email = $_POST['email'] ?? $json_data['email'] ?? null;
$username = $_POST['username'] ?? $json_data['username'] ?? null;
$purok = $_POST['purok'] ?? $json_data['purok'] ?? null;
$complete_address = $_POST['complete_address'] ?? $json_data['complete_address'] ?? null;
$preferred_truck = $_POST['preferred_truck'] ?? $json_data['preferred_truck'] ?? null;
$license_number = $_POST['license_number'] ?? $json_data['license_number'] ?? null;

if (!empty($user_id) && !empty($role) && !empty($name)) {
    try {
        $table = ($role === 'resident') ? "residents" : "users";
        $id_col = ($role === 'resident') ? "resident_id" : "user_id";

        $updateFields = [];
        $params = [];

        $updateFields[] = "name = ?";
        $params[] = $name;

        if ($phone !== null) {
            $updateFields[] = "phone = ?";
            $params[] = $phone;
        }

        if ($email !== null) {
            $updateFields[] = "email = ?";
            $params[] = $email;
        }

        if ($username !== null) {
            $updateFields[] = "username = ?";
            $params[] = $username;
        }

        if ($role !== 'resident') {
            if ($preferred_truck !== null) {
                $updateFields[] = "preferred_truck = ?";
                $params[] = $preferred_truck;
            }
            if ($license_number !== null) {
                $updateFields[] = "license_number = ?";
                $params[] = $license_number;
            }
        } else {
            if ($complete_address !== null) {
                $updateFields[] = "complete_address = ?";
                $params[] = $complete_address;
            }
            if ($purok !== null) {
                $updateFields[] = "purok = ?";
                $params[] = $purok;
            }
        }

        $sql = "UPDATE $table SET " . implode(", ", $updateFields) . " WHERE $id_col = ?";
        $params[] = $user_id;

        $stmt = $conn->prepare($sql);
        $stmt->execute($params);

        // Fetch updated user data to return
        $query = "SELECT * FROM $table WHERE $id_col = ?";
        $stmt = $conn->prepare($query);
        $stmt->execute([$user_id]);
        $updatedUser = $stmt->fetch(PDO::FETCH_ASSOC);

        echo json_encode([
            "success" => true,
            "message" => "Profile updated successfully",
            "user" => $updatedUser
        ]);
    } catch (PDOException $e) {
        echo json_encode(["success" => false, "message" => "Database Error: " . $e->getMessage()]);
    }
} else {
    echo json_encode(["success" => false, "message" => "Required data missing. Received ID: $user_id, Role: $role, Name: $name"]);
}
?>
