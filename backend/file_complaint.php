<?php
header("Content-Type: application/json");
require_once 'db_config.php';
require_once 'email_config.php';

// PHPMailer Includes
use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception;

require 'PHPMailer/Exception.php';
require 'PHPMailer/PHPMailer.php';
require 'PHPMailer/SMTP.php';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $resident_id = $_POST['resident_id'] ?? null;
    $category = $_POST['category'] ?? null;
    $description = $_POST['description'] ?? null;

    if ($resident_id && $category && $description) {
        try {
            // Get resident info
            $resStmt = $conn->prepare("SELECT name, purok FROM residents WHERE resident_id = ?");
            $resStmt->execute([$resident_id]);
            $resident = $resStmt->fetch();
            $resident_name = $resident['name'] ?? "Resident";
            $purok = $resident['purok'] ?? "Unknown";

            $query = "INSERT INTO complaints (resident_id, category, description, status)
                      VALUES (?, ?, ?, 'pending')";
            $stmt = $conn->prepare($query);
            $stmt->execute([$resident_id, $category, $description]);

            // EMAIL NOTIFICATION TO ADMIN
            try {
                $adminStmt = $conn->prepare("SELECT email, email_notifications FROM users WHERE role = 'admin' LIMIT 1");
                $adminStmt->execute();
                $admin = $adminStmt->fetch();

                if ($admin && $admin['email_notifications'] == 1) {
                    $mail = new PHPMailer(true);
                    $mail->isSMTP();
                    $mail->Host       = SMTP_HOST;
                    $mail->SMTPAuth   = true;
                    $mail->Username   = SMTP_USER;
                    $mail->Password   = SMTP_PASS;
                    $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
                    $mail->Port       = SMTP_PORT;

                    $mail->setFrom(SMTP_FROM, SMTP_NAME);
                    $mail->addAddress($admin['email']);

                    $mail->isHTML(true);
                    $mail->Subject = 'New Resident Complaint Filed - Garbage Tracker';
                    $mail->Body    = "
                        <div style='font-family: Arial, sans-serif; padding: 20px; border: 1px solid #ddd;'>
                            <h2 style='color: #d32f2f;'>New Complaint Received</h2>
                            <p>Hello Admin,</p>
                            <p>A resident has filed a new complaint. Here are the details:</p>
                            <ul>
                                <li><strong>Resident:</strong> $resident_name</li>
                                <li><strong>Purok:</strong> $purok</li>
                                <li><strong>Category:</strong> $category</li>
                                <li><strong>Description:</strong> $description</li>
                            </ul>
                            <p>Please log in to the system to address this issue.</p>
                        </div>
                    ";
                    $mail->send();
                }
            } catch (Exception $e) {}

            echo json_encode(["success" => true, "message" => "Complaint filed successfully"]);
        } catch (PDOException $e) {
            echo json_encode(["success" => false, "message" => "Database Error: " . $e->getMessage()]);
        }
    } else {
        echo json_encode(["success" => false, "message" => "Missing data"]);
    }
} else {
    echo json_encode(["success" => false, "message" => "Invalid request method"]);
}
?>
