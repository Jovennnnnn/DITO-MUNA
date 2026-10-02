<?php
header("Content-Type: application/json");
require_once 'db_config.php';

try {
    // Fetch Residents (Confirmed accounts in residents table)
    $resQuery = "SELECT resident_id as user_id, username, name, email, 'resident' as role, phone, purok, complete_address, created_at FROM residents";
    $resStmt = $conn->prepare($resQuery);
    $resStmt->execute();
    $residents = $resStmt->fetchAll(PDO::FETCH_ASSOC);

    // Fetch Drivers and Admins
    $userQuery = "SELECT user_id, username, name, email, role, phone, license_number, preferred_truck, created_at FROM users";
    $userStmt = $conn->prepare($userQuery);
    $userStmt->execute();
    $users = $userStmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        "success" => true,
        "residents" => $residents,
        "users" => $users
    ]);

} catch (PDOException $e) {
    echo json_encode(["success" => false, "message" => "Database Error: " . $e->getMessage()]);
}
?>
