<?php
header("Content-Type: application/json");
date_default_timezone_set('Asia/Manila');
require_once 'db_config.php';

$data = json_decode(file_get_contents("php://input"));

if (!$data || empty($data->email) || empty($data->otp) || empty($data->password)) {
    echo json_encode(["success" => false, "message" => "Missing required data"]);
    exit;
}

$email = $data->email;
$otp = $data->otp;
$new_password = password_hash($data->password, PASSWORD_BCRYPT);

try {
    // 1. Double check the OTP one last time
    $now = date("Y-m-d H:i:s");
    $query = "SELECT * FROM password_resets WHERE email = ? AND token = ? AND expiry > ?";
    $stmt = $conn->prepare($query);
    $stmt->execute([$email, $otp, $now]);
    $reset = $stmt->fetch();

    if (!$reset) {
        echo json_encode(["success" => false, "message" => "Security verification failed. Please try again."]);
        exit;
    }

    // 2. Update password in 'users' table
    $updateUsers = $conn->prepare("UPDATE users SET password_hash = ? WHERE email = ?");
    $updateUsers->execute([$new_password, $email]);

    // 3. Update password in 'residents' table
    $updateResidents = $conn->prepare("UPDATE residents SET password_hash = ? WHERE email = ?");
    $updateResidents->execute([$new_password, $email]);

    // 4. Clear the token
    $deleteStmt = $conn->prepare("DELETE FROM password_resets WHERE email = ?");
    $deleteStmt->execute([$email]);

    // 5. Send Notification Email
    require_once 'notify_password_change.php';
    send_password_change_notification($email);

    echo json_encode(["success" => true, "message" => "Password updated successfully"]);

} catch (PDOException $e) {
    echo json_encode(["success" => false, "message" => "Database Error: " . $e->getMessage()]);
}
?>