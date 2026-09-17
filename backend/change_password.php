<?php
header("Content-Type: application/json");
require_once 'db_config.php';
require_once 'email_config.php';

use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception;

require 'PHPMailer/Exception.php';
require 'PHPMailer/PHPMailer.php';
require 'PHPMailer/SMTP.php';

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

    // 1. Check if the user exists and get email/name for notification
    $stmt = $conn->prepare("SELECT name, email, password_hash FROM $table WHERE $id_column = :id");
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
                // 5. Send Success Email Notification
                $mail = new PHPMailer(true);
                try {
                    $mail->isSMTP();
                    $mail->Host       = SMTP_HOST;
                    $mail->SMTPAuth   = true;
                    $mail->Username   = SMTP_USER;
                    $mail->Password   = SMTP_PASS;
                    $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
                    $mail->Port       = SMTP_PORT;

                    $mail->setFrom(SMTP_FROM, SMTP_NAME);
                    $mail->addAddress($user['email']);

                    $mail->isHTML(true);
                    $mail->Subject = 'Password Changed Successfully - Garbage Tracker';
                    $mail->Body    = "
                        <div style='font-family: Arial, sans-serif; padding: 20px; border: 1px solid #ddd;'>
                            <h2 style='color: #2e7d32;'>Security Alert</h2>
                            <p>Hello <strong>{$user['name']}</strong>,</p>
                            <p>This is to confirm that the password for your <strong>Garbage Tracker</strong> account has been successfully changed.</p>
                            <p>If you did not make this change, please contact support or an administrator immediately to secure your account.</p>
                            <hr style='border: 0; border-top: 1px solid #eee;'>
                            <p style='font-size: 12px; color: #7f8c8d;'>Date/Time: " . date("Y-m-d H:i:s") . " (Asia/Manila)</p>
                        </div>
                    ";

                    $mail->send();
                } catch (Exception $e) {
                    // We don't exit here because the password was already updated in DB
                }

                echo json_encode(["success" => true, "message" => "Password updated successfully"]);
            } else {
                echo json_encode(["success" => false, "message" => "Database update failed"]);
            }
        } else {
            echo json_encode(["success" => false, "message" => "Incorrect current password"]);
        }
    } else {
        echo json_encode(["success" => false, "message" => "User not found"]);
    }
} catch (PDOException $e) {
    echo json_encode(["success" => false, "message" => "Database Error: " . $e->getMessage()]);
}
?>