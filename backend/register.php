<?php
header("Content-Type: application/json");
require_once 'db_config.php';

function trigger_firebase_notification($type, $title, $message) {
    $url = "https://garbagesis-78d39-default-rtdb.asia-southeast1.firebasedatabase.app/notifications.json";
    $data = [
        "type" => $type,
        "title" => $title,
        "message" => $message,
        "timestamp" => round(microtime(true) * 1000),
        "isRead" => false
    ];

    $ch = curl_init($url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data));
    curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
    curl_setopt($ch, CURLOPT_TIMEOUT, 5); // 5 seconds timeout
    curl_exec($ch);
    curl_close($ch);
}

$data = json_decode(file_get_contents("php://input"));

if (!$data) {
    echo json_encode(["success" => false, "message" => "No data received"]);
    exit;
}

if (!empty($data->username) && !empty($data->password) && !empty($data->role)) {
    try {
        $hashed_password = password_hash($data->password, PASSWORD_BCRYPT);
        $name = !empty($data->name) ? $data->name : $data->username;

        if ($data->role === 'resident') {
            // Residents are inserted with is_archived = 1 (Pending Approval)
            $query = "INSERT INTO residents (username, name, password_hash, email, phone, purok, complete_address, is_archived)
                      VALUES (?, ?, ?, ?, ?, ?, ?, ?)";
            $stmt = $conn->prepare($query);

            $email = !empty($data->email) ? $data->email : "";
            $phone = !empty($data->phone) ? $data->phone : null;
            $purok = !empty($data->purok) ? $data->purok : "";
            $address = !empty($data->complete_address) ? $data->complete_address : "";

            $stmt->execute([$data->username, $name, $hashed_password, $email, $phone, $purok, $address, 1]);

            trigger_firebase_notification(
                'NEW_REGISTRATION',
                'New Registration Request',
                "$name has requested to join as a Resident in $purok"
            );

            echo json_encode(["success" => true, "message" => "Resident Registration Sent! Please wait for admin approval."]);
            exit;
        }

        // For drivers/admins
        else if ($data->role === 'admin' || $data->role === 'driver') {
            $query = "INSERT INTO users (username, name, email, password_hash, phone, license_number, preferred_truck, role, is_archived)
                      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";
            $stmt = $conn->prepare($query);

            $email = !empty($data->email) ? $data->email : "";
            $phone = !empty($data->phone) ? $data->phone : null;
            $license = !empty($data->license_number) ? $data->license_number : "";
            $truck = !empty($data->preferred_truck) ? $data->preferred_truck : null;

            // Drivers are archived by default (pending approval)
            $is_archived = ($data->role === 'driver') ? 1 : 0;

            $stmt->execute([$data->username, $name, $email, $hashed_password, $phone, $license, $truck, $data->role, $is_archived]);

            if ($data->role === 'driver') {
                trigger_firebase_notification(
                    'NEW_REGISTRATION',
                    'New Driver Application',
                    "$name has applied for a Driver role"
                );
            }

            $msg = ($data->role === 'driver')
                ? "Registration sent! Please wait for admin approval."
                : "Registration successful!";

            echo json_encode(["success" => true, "message" => $msg]);
            exit;
        }

    } catch (PDOException $e) {
        echo json_encode(["success" => false, "message" => "Database Error: " . $e->getMessage()]);
    }
} else {
    echo json_encode(["success" => false, "message" => "Incomplete data"]);
}
?>
