<?php
header("Content-Type: application/json");
require_once 'db_config.php';

try {
    $sql = file_get_contents('update_schema.sql');

    // Split SQL by semicolon, but handle cases where semicolon is inside strings (simple split for this case)
    $queries = array_filter(array_map('trim', explode(';', $sql)));

    $results = [];
    foreach ($queries as $query) {
        if (empty($query)) continue;
        try {
            $conn->exec($query);
            $results[] = ["query" => substr($query, 0, 50) . "...", "status" => "Success"];
        } catch (PDOException $e) {
            // It might fail if column already exists (even with IF NOT EXISTS in some MariaDB versions)
            $results[] = ["query" => substr($query, 0, 50) . "...", "status" => "Error/Skipped", "message" => $e->getMessage()];
        }
    }

    echo json_encode(["success" => true, "results" => $results]);
} catch (Exception $e) {
    echo json_encode(["success" => false, "message" => $e->getMessage()]);
}
?>
