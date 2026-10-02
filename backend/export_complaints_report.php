<?php
/**
 * COMPLAINTS MODULE EXPORT ENGINE
 * Generates a focused report of all Reported Complaints and Issues.
 */
header("Content-Type: application/json");
require_once 'db_config.php';

$reports_dir = 'reports/complaints/';
if (!file_exists($reports_dir)) {
    mkdir($reports_dir, 0777, true);
}

$filename = 'Complaints_Report_' . date('Y-m-d_His') . '.html';
$filepath = $reports_dir . $filename;

try {
    // Check for columns to be resilient
    $columns = $conn->query("DESCRIBE complaints")->fetchAll(PDO::FETCH_COLUMN);
    $response_val = in_array('admin_response', $columns) ? 'admin_response' : "''";

    $stmt = $conn->query("SELECT c.category, c.description, c.status, $response_val as response, c.created_at, r.name
                          FROM complaints c
                          LEFT JOIN residents r ON c.resident_id = r.resident_id
                          ORDER BY c.created_at DESC");
    $data = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $html = "<html><head><style>
        body { font-family: sans-serif; padding: 40px; }
        h2 { color: #C62828; border-bottom: 2px solid #eee; padding-bottom: 10px; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background: #424242; color: white; font-size: 12px; }
        .status { font-weight: bold; text-transform: uppercase; font-size: 11px; }
    </style></head><body>";

    $html .= "<h2>Reported Complaints and Issues</h2>";
    $html .= "<p>Generated on: " . date('Y-m-d H:i:s') . "</p>";
    $html .= "<table><thead><tr><th>Date</th><th>Resident</th><th>Category</th><th>Details</th><th>Status</th><th>Response</th></tr></thead><tbody>";

    foreach ($data as $row) {
        $html .= "<tr>
            <td>{$row['created_at']}</td>
            <td>" . ($row['name'] ?? 'N/A') . "</td>
            <td>{$row['category']}</td>
            <td>{$row['description']}</td>
            <td><span class='status'>{$row['status']}</span></td>
            <td>{$row['response']}</td>
        </tr>";
    }

    $html .= "</tbody></table></body></html>";

    file_put_contents($filepath, $html);

    echo json_encode([
        "success" => true,
        "url" => get_absolute_url($filepath)
    ]);

} catch (Exception $e) {
    echo json_encode(["success" => false, "message" => $e->getMessage()]);
}
?>
