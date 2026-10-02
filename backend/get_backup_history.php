<?php
header("Content-Type: application/json");
require_once 'db_config.php';
require_once 'cleanup_logic.php';

$backup_dir = 'backups/';
// Perform cleanup to keep history fresh
perform_snapshot_cleanup($backup_dir);

$backups = [];

if (file_exists($backup_dir)) {
    $files = scandir($backup_dir, SCANDIR_SORT_DESCENDING);
    foreach ($files as $file) {
        if (strpos($file, '.sql') !== false) {
            $path = $backup_dir . $file;
            $backups[] = [
                "filename" => $file,
                "size" => round(filesize($path) / 1024, 2) . " KB",
                "date" => date("Y-m-d H:i:s", filemtime($path)),
                "url" => get_absolute_url($path)
            ];
        }
    }
}

echo json_encode([
    "success" => true,
    "backups" => $backups
]);
?>
