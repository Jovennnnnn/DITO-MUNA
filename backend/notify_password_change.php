<?php
use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception;

require 'PHPMailer/src/Exception.php';
require 'PHPMailer/src/PHPMailer.php';
require 'PHPMailer/src/SMTP.php';
require_once 'email_config.php';

function send_password_change_notification($email) {
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
        $mail->addAddress($email);

        $mail->isHTML(true);
        $mail->Subject = 'Security Notice: Password Changed Successfully';

        $mail->Body = "
            <div style='font-family: \"Segoe UI\", Tahoma, Geneva, Verdana, sans-serif; max-width: 500px; margin: 0 auto; border: 1px solid #e0f2f1; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 12px rgba(0,0,0,0.05);'>
                <div style='background-color: #00796B; padding: 25px; text-align: center;'>
                    <h1 style='color: #ffffff; margin: 0; font-size: 24px; letter-spacing: 1px;'>Garbage Tracker</h1>
                    <p style='color: #b2dfdb; margin: 5px 0 0 0; font-size: 14px;'>Security Notification | Abiso sa Seguridad</p>
                </div>
                <div style='padding: 30px; background-color: #ffffff;'>
                    <div style='text-align: center; margin-bottom: 20px;'>
                        <div style='background-color: #e8f5e9; color: #2e7d32; display: inline-block; padding: 10px 20px; border-radius: 50px; font-weight: bold; font-size: 13px;'>
                            ✓ Password Reset Successful | Tagumpay na Pag-reset
                        </div>
                    </div>

                    <!-- English Section -->
                    <p style='color: #1a1a1a; font-weight: bold; font-size: 15px;'>Hello,</p>
                    <p style='color: #757575; line-height: 1.6; font-size: 14px;'>This is an automated notification to confirm that your account password has been successfully updated.</p>

                    <!-- Tagalog Section -->
                    <hr style='border: 0; border-top: 1px dashed #e0e0e0; margin: 20px 0;'>
                    <p style='color: #1a1a1a; font-weight: bold; font-size: 15px;'>Kumusta,</p>
                    <p style='color: #757575; line-height: 1.6; font-size: 14px;'>Ito ay isang awtomatikong abiso upang kumpirmahin na matagumpay na na-update ang password ng iyong account.</p>

                    <div style='background-color: #f5f5f5; border-radius: 8px; padding: 20px; margin: 25px 0;'>
                        <p style='color: #1a1a1a; margin: 0; font-size: 14px;'><strong>If you performed this action:</strong></p>
                        <p style='color: #757575; margin: 5px 0 15px 0; font-size: 13px;'>You can safely ignore this email. No further action is required.</p>

                        <p style='color: #1a1a1a; margin: 0; font-size: 14px;'><strong>Kung ikaw ang gumawa nito:</strong></p>
                        <p style='color: #757575; margin: 5px 0 0 0; font-size: 13px;'>Maaari mong balewalain ang email na ito. Wala nang kailangang gawin pa.</p>

                        <div style='margin-top: 15px; border-top: 1px solid #e0e0e0; padding-top: 15px;'>
                            <p style='color: #d32f2f; margin: 0; font-size: 14px;'><strong>If you did NOT request this change:</strong></p>
                            <p style='color: #757575; margin: 5px 0 15px 0; font-size: 13px;'>Please contact our support team or visit the <strong>Brgy. Balintawak Hall</strong> immediately to secure your account.</p>

                            <p style='color: #d32f2f; margin: 0; font-size: 14px;'><strong>Kung HINDI mo hiniling ang pagbabagong ito:</strong></p>
                            <p style='color: #757575; margin: 5px 0 0 0; font-size: 13px;'>Mangyaring makipag-ugnayan sa aming support team o pumunta agad sa <strong>Brgy. Balintawak Hall</strong> para ma-secure ang iyong account.</p>
                        </div>
                    </div>

                    <p style='color: #757575; font-size: 13px;'>Thank you for keeping your account secure. | Salamat sa pagpapanatiling secure ng iyong account.</p>
                </div>
                <div style='background-color: #fafafa; padding: 20px; text-align: center; border-top: 1px solid #eeeeee;'>
                    <p style='color: #00796B; margin: 0; font-size: 12px; font-weight: bold;'>Brgy. Balintawak, Lipa City</p>
                    <p style='color: #9e9e9e; margin: 5px 0 0 0; font-size: 11px;'>&copy; 2026 Garbage Tracker System. All rights reserved.</p>
                </div>
            </div>
        ";

        $mail->send();
        return true;
    } catch (Exception $e) {
        error_log(\"Email Notification Error: {$mail->ErrorInfo}\");
        return false;
    }
}
?>
