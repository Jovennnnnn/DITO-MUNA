<?php
header("Content-Type: application/json");
date_default_timezone_set('Asia/Manila'); // Set to local timezone
require_once 'db_config.php';
require_once 'email_config.php';

// PHPMailer Includes
use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\SMTP;
use PHPMailer\PHPMailer\Exception;

require 'PHPMailer/Exception.php';
require 'PHPMailer/PHPMailer.php';
require 'PHPMailer/SMTP.php';

$data = json_decode(file_get_contents("php://input"));

if (!$data || empty($data->email)) {
    echo json_encode(["success" => false, "message" => "Email is required"]);
    exit;
}

$email = $data->email;

try {
    // 1. Check if email exists
    $query = "SELECT email FROM users WHERE email = ? UNION SELECT email FROM residents WHERE email = ?";
    $stmt = $conn->prepare($query);
    $stmt->execute([$email, $email]);
    $user = $stmt->fetch();

    if (!$user) {
        echo json_encode(["success" => false, "message" => "Email address not found"]);
        exit;
    }

    // 2. Generate 6-digit OTP
    $otp = sprintf("%06d", mt_rand(1, 999999));
    $expiry = date("Y-m-d H:i:s", strtotime("+3 minutes"));

    // 3. Save to password_resets table
    $deleteStmt = $conn->prepare("DELETE FROM password_resets WHERE email = ?");
    $deleteStmt->execute([$email]);

    $insertStmt = $conn->prepare("INSERT INTO password_resets (email, token, expiry) VALUES (?, ?, ?)");
    $insertStmt->execute([$email, $otp, $expiry]);

    // 4. Send Email using PHPMailer
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
        $mail->addAddress($email);

        // Content
        $mail->isHTML(true);
        $mail->Subject = 'Password Reset OTP - Garbage Tracker';
        $mail->Body    = "
            <div style='font-family: \"Segoe UI\", Tahoma, Geneva, Verdana, sans-serif; max-width: 500px; margin: 0 auto; border: 1px solid #e0f2f1; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 12px rgba(0,0,0,0.05);'>
                <div style='background-color: #00796B; padding: 25px; text-align: center;'>
                    <h1 style='color: #ffffff; margin: 0; font-size: 24px; letter-spacing: 1px;'>Garbage Tracker</h1>
                    <p style='color: #b2dfdb; margin: 5px 0 0 0; font-size: 14px;'>Security Verification | Pagpapatunay ng Seguridad</p>
                </div>
                <div style='padding: 30px; background-color: #ffffff;'>
                    <!-- English Section -->
                    <h2 style='color: #1a1a1a; margin-top: 0; font-size: 18px;'>Reset Your Password</h2>
                    <p style='color: #757575; line-height: 1.6; font-size: 14px;'>We received a request to access your account recovery. Please use the following One-Time Password (OTP) to proceed.</p>

                    <!-- Tagalog Section -->
                    <hr style='border: 0; border-top: 1px dashed #e0e0e0; margin: 20px 0;'>
                    <h2 style='color: #1a1a1a; margin-top: 0; font-size: 18px;'>I-reset ang Iyong Password</h2>
                    <p style='color: #757575; line-height: 1.6; font-size: 14px;'>Nakatanggap kami ng kahilingan para sa pagbawi ng iyong account. Gamitin ang sumusunod na One-Time Password (OTP) para magpatuloy.</p>

                    <div style='background-color: #f5f5f5; border-radius: 8px; padding: 20px; text-align: center; margin: 25px 0;'>
                        <span style='display: block; color: #757575; font-size: 11px; margin-bottom: 8px; text-transform: uppercase; font-weight: bold;'>Verification Code | Kodigo sa Pagpapatunay</span>
                        <span style='color: #00796B; font-size: 36px; font-weight: 900; letter-spacing: 8px; font-family: monospace;'>$otp</span>
                    </div>

                    <div style='background-color: #fff9c4; border-left: 4px solid #fbc02d; padding: 12px 15px; margin-bottom: 20px;'>
                        <p style='color: #5d4037; margin: 0; font-size: 13px;'><strong>Note:</strong> Valid for <strong>3 minutes</strong> only.</p>
                        <p style='color: #5d4037; margin: 5px 0 0 0; font-size: 13px;'><strong>Paalala:</strong> Valid ito sa loob ng <strong>3 minuto</strong> lamang.</p>
                    </div>

                    <p style='color: #9e9e9e; font-size: 12px; line-height: 1.5;'>If you did not request this, please ignore this email. | Kung hindi mo ito hiniling, pakibalewala ang email na ito.</p>
                </div>
                <div style='background-color: #fafafa; padding: 20px; text-align: center; border-top: 1px solid #eeeeee;'>
                    <p style='color: #00796B; margin: 0; font-size: 12px; font-weight: bold;'>Brgy. Balintawak, Lipa City</p>
                    <p style='color: #9e9e9e; margin: 5px 0 0 0; font-size: 11px;'>&copy; 2026 Garbage Tracker System. All rights reserved.</p>
                </div>
            </div>
        ";

        $mail->send();
        echo json_encode(["success" => true, "message" => "OTP sent to your email"]);

    } catch (Exception $e) {
        echo json_encode([
            "success" => false,
            "message" => "Email could not be sent. Mailer Error: {$mail->ErrorInfo}"
        ]);
    }

} catch (PDOException $e) {
    echo json_encode(["success" => false, "message" => "Database Error: " . $e->getMessage()]);
}
?>