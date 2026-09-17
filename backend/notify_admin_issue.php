<?php
header("Content-Type: application/json");
date_default_timezone_set('Asia/Manila');
require_once 'db_config.php';
require_once 'email_config.php';

// PHPMailer Includes
use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\SMTP;
use PHPMailer\PHPMailer\Exception;

require 'PHPMailer/Exception.php';
require 'PHPMailer/PHPMailer.php';
require 'PHPMailer/SMTP.php';

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
    curl_exec($ch);
    curl_close($ch);
}

$driver_name = $_POST['driver_name'] ?? 'Driver';
$issue_type = $_POST['issue_type'] ?? 'General Issue';
$description = $_POST['description'] ?? 'No description provided';
$admin_email = $_POST['admin_email'] ?? '';

if (empty($admin_email)) {
    // Try to get admin email and setting from database
    try {
        $stmt = $conn->prepare("SELECT email, email_notifications FROM users WHERE role = 'admin' LIMIT 1");
        $stmt->execute();
        $admin = $stmt->fetch();
        if ($admin) {
            if ($admin['email_notifications'] == 0) {
                echo json_encode(["success" => true, "message" => "Notification received (Email disabled by Admin)"]);
                exit;
            }
            $admin_email = $admin['email'];
        } else {
            echo json_encode(["success" => false, "message" => "Admin email not found"]);
            exit;
        }
    } catch (PDOException $e) {
        echo json_encode(["success" => false, "message" => "Database Error"]);
        exit;
    }
} else {
    // If email was provided, still check if that specific admin has email enabled
    try {
        $stmt = $conn->prepare("SELECT email_notifications FROM users WHERE email = ?");
        $stmt->execute([$admin_email]);
        $pref = $stmt->fetchColumn();
        if ($pref !== false && $pref == 0) {
             echo json_encode(["success" => true, "message" => "Notification received (Email disabled by Admin)"]);
             exit;
        }
    } catch (PDOException $e) {}
}

$mail = new PHPMailer(true);

try {
    // SMTP Server settings
    $mail->isSMTP();
    $mail->Host       = SMTP_HOST;
    $mail->SMTPAuth   = true;
    $mail->Username   = SMTP_USER;
    $mail->Password   = SMTP_PASS;
    $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
    $mail->Port       = SMTP_PORT;

    // Recipients
    $mail->setFrom(SMTP_FROM, SMTP_NAME);
    $mail->addAddress($admin_email);

    // Content
    $mail->isHTML(true);
    $mail->Subject = 'New Driver Issue Reported - Garbage Tracker';

    $timestamp = date("F j, Y, g:i a");

    $mail->Body    = "
        <div style='font-family: Arial, sans-serif; padding: 20px; border: 1px solid #ddd; border-radius: 8px;'>
            <h2 style='color: #e67e22;'>New Driver Issue Report</h2>
            <p>Hello Admin,</p>
            <p>A new issue has been reported by a driver. Here are the details:</p>
            <table style='width: 100%; border-collapse: collapse; margin-top: 10px;'>
                <tr>
                    <td style='padding: 8px; border: 1px solid #eee; font-weight: bold; width: 30%;'>Driver Name:</td>
                    <td style='padding: 8px; border: 1px solid #eee;'>$driver_name</td>
                </tr>
                <tr>
                    <td style='padding: 8px; border: 1px solid #eee; font-weight: bold;'>Issue Type:</td>
                    <td style='padding: 8px; border: 1px solid #eee;'>$issue_type</td>
                </tr>
                <tr>
                    <td style='padding: 8px; border: 1px solid #eee; font-weight: bold;'>Reported At:</td>
                    <td style='padding: 8px; border: 1px solid #eee;'>$timestamp</td>
                </tr>
                <tr>
                    <td style='padding: 8px; border: 1px solid #eee; font-weight: bold;'>Description:</td>
                    <td style='padding: 8px; border: 1px solid #eee;'>$description</td>
                </tr>
            </table>
            <p style='margin-top: 20px;'>Please log in to the Admin Dashboard to take action.</p>
            <hr style='border: 0; border-top: 1px solid #eee;'>
            <p style='font-size: 12px; color: #7f8c8d;'>This is an automated message from the Garbage Tracker System.</p>
        </div>
    ";

    $mail->send();

    trigger_firebase_notification(
        'DRIVER_ISSUE',
        'New Driver Issue Reported',
        "Driver $driver_name reported an issue: $issue_type"
    );

    echo json_encode(["success" => true, "message" => "Admin notified via email"]);

} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "message" => "Email could not be sent. Mailer Error: {$mail->ErrorInfo}"
    ]);
}
?>
