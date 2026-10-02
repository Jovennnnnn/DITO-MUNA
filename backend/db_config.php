<?php
/**
 * UNIVERSAL DATABASE & CORS CONFIGURATION
 * This file is the core connection for BOTH Kotlin and Flutter Web.
 */

// 1. ABSOLUTE CORS PERMISSIONS
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Headers: *");
header("Access-Control-Allow-Methods: POST, GET, OPTIONS, DELETE, PUT");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    exit(0);
}

// 2. DATABASE SETTINGS (HOSTINGER)
$host = "localhost";
$db_name = "u767891388_garbage_system";
$username = "u767891388_garbage_system";
$password = "group2-NT";

try {
    $conn = new PDO("mysql:host=" . $host . ";dbname=" . $db_name, $username, $password);
    $conn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $conn->exec("SET time_zone = '+08:00'");
} catch(PDOException $exception) {
    header('Content-Type: application/json');
    echo json_encode(["success" => false, "message" => "DB Error: " . $exception->getMessage()]);
    exit;
}

/**
 * Helper to build an absolute URL to a file in the backend folder
 */
function get_absolute_url($relative_path) {
    $protocol = isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? "https" : "http";
    $host = $_SERVER['HTTP_HOST'];
    $current_path = $_SERVER['PHP_SELF'];
    $dir = dirname($current_path);
    // Ensure no double slashes and correct joining
    return $protocol . "://" . $host . rtrim($dir, '/') . "/" . ltrim($relative_path, '/');
}
?>
