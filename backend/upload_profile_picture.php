<?php
/**
 * PROFILE PICTURE UPLOAD HANDLER
 * Supports Flutter Web (CORS) and XAMPP Localhost
 */

// 1. Core Config & CORS (Already handled in db_config but explicit for safety)
require_once 'db_config.php';
header("Content-Type: application/json");

// 2. Setup Directories
$uploadDir = 'uploads/profile_pictures/';
if (!is_dir($uploadDir)) {
    mkdir($uploadDir, 0777, true);
}

// 3. Get Data
$user_id = $_POST['user_id'] ?? null;
$role = $_POST['role'] ?? null;

if (empty($user_id) || empty($role)) {
    echo json_encode(["success" => false, "message" => "Missing User ID or Role."]);
    exit;
}

if (!isset($_FILES['profile_picture'])) {
    echo json_encode(["success" => false, "message" => "No image file detected."]);
    exit;
}

// 4. File Validation
$file = $_FILES['profile_picture'];
$ext = strtolower(pathinfo($file['name'], PATHINFO_EXTENSION));
$allowed = ['jpg', 'jpeg', 'png'];

if (!in_array($ext, $allowed)) {
    echo json_encode(["success" => false, "message" => "Invalid file type. Only JPG and PNG allowed."]);
    exit;
}

// 5. Save File
$newFileName = "profile_" . $user_id . "_" . time() . "." . $ext;
$targetPath = $uploadDir . $newFileName;

if (move_uploaded_file($file['tmp_name'], $targetPath)) {
    try {
        $table = ($role === 'resident') ? "residents" : "users";
        $id_col = ($role === 'resident') ? "resident_id" : "user_id";

        // Generate the EXACT URL that the browser can reach
        $fullUrl = get_absolute_url($targetPath);

        // Update MySQL
        $sql = "UPDATE $table SET profile_picture = ? WHERE $id_col = ?";
        $stmt = $conn->prepare($sql);

        if ($stmt->execute([$fullUrl, $user_id])) {
            echo json_encode([
                "success" => true,
                "message" => "Upload successful",
                "url" => $fullUrl
            ]);
        } else {
            echo json_encode(["success" => false, "message" => "DB Update Failed"]);
        }
    } catch (PDOException $e) {
        echo json_encode(["success" => false, "message" => "Database Error: " . $e->getMessage()]);
    }
} else {
    echo json_encode(["success" => false, "message" => "Failed to save file to disk."]);
}
?>
