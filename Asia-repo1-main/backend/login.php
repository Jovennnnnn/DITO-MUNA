<?php
header("Content-Type: application/json");
require_once 'db_config.php';

$data = json_decode(file_get_contents("php://input"));

if (!$data) {
    echo json_encode(["success" => false, "message" => "No data received"]);
    exit;
}

if (!empty($data->username_or_email) && !empty($data->password)) {
    try {
        $username_or_email = $data->username_or_email;

        // 1. Search sa 'users' table (Admin/Driver) - Kasama na ang license at truck
        $query = "SELECT user_id, username, name, email, phone, license_number, preferred_truck, role, password_hash FROM users WHERE username = ? OR email = ?";
        $stmt = $conn->prepare($query);
        $stmt->execute([$username_or_email, $username_or_email]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);

        if ($user && password_verify($data->password, $user['password_hash'])) {
            unset($user['password_hash']);
            echo json_encode([
                "success" => true,
                "message" => "Login successful",
                "user" => $user
            ]);
            exit;
        }

            // 2. Search sa 'residents' table (Resident) - Kasama na ang purok at address
            $query = "SELECT resident_id as user_id, username, name, email, phone, purok, complete_address, 'resident' as role, password_hash FROM residents WHERE username = ? OR email = ?";
            $stmt = $conn->prepare($query);
            $stmt->execute([$username_or_email, $username_or_email]);
            $resident = $stmt->fetch(PDO::FETCH_ASSOC);

            if ($resident && password_verify($data->password, $resident['password_hash'])) {
                unset($resident['password_hash']);
                echo json_encode([
                    "success" => true,
                    "message" => "Login successful",
                    "user" => $resident
                ]);
                exit;
            }

        echo json_encode(["success" => false, "message" => "Invalid username/email or password"]);

    } catch (PDOException $e) {
        echo json_encode(["success" => false, "message" => "Database Error: " . $e->getMessage()]);
    }
} else {
    echo json_encode(["success" => false, "message" => "Incomplete data"]);
}
?>