<?php
/**
 * REUSABLE CLEANUP LOGIC for Database Snapshots
 * Rule 1: Delete files older than 30 days.
 * Rule 2: Keep only the most recent 150 files (delete older if limit exceeded).
 */

function perform_snapshot_cleanup($backup_dir) {
    if (!file_exists($backup_dir)) return;

    $files = [];
    $all_files = scandir($backup_dir);
    $now = time();
    $thirty_days_in_seconds = 30 * 24 * 60 * 60;

    // 1. Collect .sql files and handle 30-day age limit
    foreach ($all_files as $file) {
        if (strpos($file, '.sql') !== false) {
            $path = $backup_dir . $file;
            $file_age = filemtime($path);

            // Rule 1: Delete if older than 30 days
            if (($now - $file_age) > $thirty_days_in_seconds) {
                unlink($path);
            } else {
                $files[] = [
                    'path' => $path,
                    'time' => $file_age
                ];
            }
        }
    }

    // 2. Rule 2: Handle 150-file limit (Keep only the newest)
    if (count($files) > 150) {
        // Sort by time descending (newest first)
        usort($files, function($a, $b) {
            return $b['time'] - $a['time'];
        });

        // Get files to delete (everything after index 149)
        $to_delete = array_slice($files, 150);
        foreach ($to_delete as $file) {
            if (file_exists($file['path'])) {
                unlink($file['path']);
            }
        }
    }
}
?>
