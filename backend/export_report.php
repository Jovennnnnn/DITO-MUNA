<?php
/**
 * PROFESSIONAL ANALYTICS EXPORT ENGINE
 * Generates a stylized Excel report (HTML/XLS) matching the UI screenshots.
 */
require_once 'db_config.php';

// Check if format is XLS
if (($_GET['format'] ?? '') !== 'xls') {
    // Fallback to original ZIP functionality if not XLS (for backward compatibility with other features)
    handle_zip_export();
    exit;
}

// 1. COLLECT DATA FROM GET PARAMS (FROM FLUTTER)
$date_generated = date('F d, Y - h:i A');
$period = ($_GET['start_date'] ?? date('Y-m-d')) . ' to ' . ($_GET['end_date'] ?? date('Y-m-d'));
$total_drivers = $_GET['total_drivers'] ?? '2';
$report_type = $_GET['type'] ?? 'ALL REPORTS';

$res_rate = $_GET['res_rate'] ?? '0.00%';
$avg_time = $_GET['avg_time'] ?? '0.0 hours';
$purok_coverage = $_GET['coverage'] ?? '0%';
$routes_done = $_GET['routes_done'] ?? '0/0';

$waste_tomorrow = $_GET['waste_tomorrow'] ?? '0 kg';
$waste_weekly = $_GET['waste_weekly'] ?? '0 kg';
$ai_insight = $_GET['insight1'] ?? 'System performing normally.';
$ai_recs = $_GET['insight2'] ?? 'No recommendations at this time.';

$active = $_GET['active_count'] ?? '0';
$idle = $_GET['inactive_count'] ?? '0';
$offline = '0'; // Logic for offline can be added
$full = $_GET['full_count'] ?? '0';
$completed = $_GET['resolved_count'] ?? '0';

$pending_complaints = $_GET['pending_count'] ?? '0';
$inprogress_complaints = $_GET['inprogress_count'] ?? '0';
$resolved_complaints = $_GET['resolved_count'] ?? '0';

$total_dist = $_GET['dist'] ?? '0.0 km';
$total_stops = $_GET['stops'] ?? '0 stops';
$avg_coll_time = $_GET['coll_time'] ?? '0.0 hours';

// 2. FETCH DETAILED DATA FROM MYSQL
// Truck Status Table
$trucks = [];
try {
    $stmt = $conn->query("SELECT u.name, u.plate_number, tl.status
                          FROM users u
                          LEFT JOIN truck_locations tl ON u.preferred_truck = tl.truck_id
                          WHERE u.role = 'driver' AND u.is_archived = 0");
    $trucks = $stmt->fetchAll(PDO::FETCH_ASSOC);
} catch(Exception $e) {}

// Complaints Table
$complaints = [];
try {
    $stmt = $conn->query("SELECT category, description, status, created_at FROM complaints WHERE is_archived = 0 ORDER BY created_at DESC LIMIT 10");
    $complaints = $stmt->fetchAll(PDO::FETCH_ASSOC);
} catch(Exception $e) {}

// Purok Coverage Table (Visit Frequency)
$puroks = [
    "Purok 1", "Purok 2", "Purok 3", "Purok 4",
    "Dos Riles", "Sentro", "San Isidro", "Paraiso",
    "Riverside", "Kalaw Street", "Home Subdivision",
    "Tanco Road / Ayala Highway"
];
$coverage_data = [];
try {
    // Get last visit and count per purok from collection_logs
    foreach($puroks as $p) {
        $stmt = $conn->prepare("SELECT COUNT(*) as count, MAX(timestamp) as last_visit FROM collection_logs WHERE zone_name = ?");
        $stmt->execute([$p]);
        $res = $stmt->fetch(PDO::FETCH_ASSOC);
        $coverage_data[$p] = [
            'count' => $res['count'] ?? 0,
            'last' => $res['last_visit'] ? date('Y-m-d H:i:s', strtotime($res['last_visit'])) : 'NO VISITS RECORDED'
        ];
    }
} catch(Exception $e) {}

// 3. GENERATE XLS CONTENT (HTML/CSS)
$filename = "Official_Report_" . date('Ymd_His') . ".xls";
header("Content-Type: application/vnd.ms-excel");
header("Content-Disposition: attachment; filename=\"$filename\"");

?>
<html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:excel" xmlns="http://www.w3.org/TR/REC-html40">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<style>
    .header-main { background-color: #004D40; color: #FFFFFF; font-weight: bold; font-size: 18pt; text-align: center; height: 40px; }
    .header-sub { background-color: #00BFA5; color: #FFFFFF; font-weight: bold; font-size: 12pt; text-align: left; padding: 5px; }
    .header-section { background-color: #00BFA5; color: #FFFFFF; font-weight: bold; font-size: 11pt; border: 1px solid #E0E0E0; }

    .label-cell { background-color: #E8F5E9; color: #2E7D32; font-weight: bold; border: 1px solid #E0E0E0; font-size: 10pt; }
    .value-cell { background-color: #FFFFFF; color: #424242; border: 1px solid #E0E0E0; font-size: 10pt; }

    .table-header { background-color: #E0F2F1; color: #00796B; font-weight: bold; border: 1px solid #B2DFDB; text-align: center; }
    .table-cell { border: 1px solid #E0E0E0; padding: 4px; font-size: 9pt; }
    .no-data { color: #E53935; font-style: italic; text-align: center; background-color: #FFEBEE; }

    .ai-box { background-color: #FFFFFF; border: 1px solid #E0E0E0; font-size: 9pt; vertical-align: top; }
    .ai-bullet { color: #004D40; font-weight: bold; }
</style>
</head>
<body>
    <table>
        <!-- MAIN TITLE -->
        <tr><td colspan="12" class="header-main">GARBAGE TRACKING & ANALYTICS REPORT</td></tr>
        <tr><td colspan="12" class="header-sub" style="text-align: center; font-size: 10pt;">Official Intelligence Summary & Operational Insights</td></tr>

        <!-- SUMMARY INFO -->
        <tr>
            <td colspan="2" class="label-cell">Period Selected:</td>
            <td colspan="3" class="value-cell"><?php echo $period; ?></td>
            <td colspan="2" class="label-cell">Total Drivers:</td>
            <td colspan="5" class="value-cell"><?php echo $total_drivers; ?></td>
        </tr>
        <tr>
            <td colspan="2" class="label-cell">Date Generated:</td>
            <td colspan="3" class="value-cell"><?php echo $date_generated; ?></td>
            <td colspan="2" class="label-cell">Report Type:</td>
            <td colspan="5" class="value-cell"><?php echo $report_type; ?></td>
        </tr>

        <tr><td colspan="12" style="height: 10px;"></td></tr>

        <!-- PERFORMANCE OVERVIEW -->
        <tr><td colspan="12" class="header-section">Performance Overview</td></tr>
        <tr>
            <td colspan="3" class="table-header">Resolution Rate</td>
            <td colspan="3" class="table-header">Avg Response Time</td>
            <td colspan="3" class="table-header">Purok Coverage</td>
            <td colspan="3" class="table-header">Routes Completed</td>
        </tr>
        <tr>
            <td colspan="3" class="value-cell" style="text-align: center;"><?php echo $res_rate; ?></td>
            <td colspan="3" class="value-cell" style="text-align: center;"><?php echo $avg_time; ?></td>
            <td colspan="3" class="value-cell" style="text-align: center;"><?php echo $purok_coverage; ?></td>
            <td colspan="3" class="value-cell" style="text-align: center;"><?php echo $routes_done; ?></td>
        </tr>

        <tr><td colspan="12" style="height: 20px;"></td></tr>

        <!-- WASTE PREDICTIONS -->
        <tr><td colspan="12" class="header-section">Waste Predictions</td></tr>
        <tr>
            <td colspan="2" class="table-header">Tomorrow's</td>
            <td colspan="3" class="table-header">Weekly Forecast</td>
            <td colspan="7" class="table-header">AI Insights & Recommendations</td>
        </tr>
        <tr>
            <td colspan="2" class="value-cell" style="text-align: center; vertical-align: middle; font-weight: bold;"><?php echo $waste_tomorrow; ?></td>
            <td colspan="3" class="value-cell" style="text-align: center; vertical-align: middle; font-weight: bold;"><?php echo $waste_weekly; ?></td>
            <td colspan="7" class="ai-box">
                <span class="ai-bullet">•</span> <?php echo $ai_insight; ?><br>
                <span class="ai-bullet">•</span> <?php echo $ai_recs; ?>
            </td>
        </tr>

        <tr><td colspan="12" style="height: 20px;"></td></tr>

        <!-- TRUCK & FLEET STATUS -->
        <tr><td colspan="12" class="header-section">Truck & Fleet Status</td></tr>
        <tr><td colspan="12" class="table-header">Fleet Distribution</td></tr>
        <tr>
            <td colspan="2" class="label-cell" style="text-align: center;">Active: <?php echo $active; ?></td>
            <td colspan="2" class="label-cell" style="text-align: center;">Idle: <?php echo $idle; ?></td>
            <td colspan="3" class="label-cell" style="text-align: center;">Offline: <?php echo $offline; ?></td>
            <td colspan="2" class="label-cell" style="text-align: center;">Full: <?php echo $full; ?></td>
            <td colspan="3" class="label-cell" style="text-align: center;">Completed: <?php echo $completed; ?></td>
        </tr>
        <tr>
            <td colspan="2" class="table-header">ID</td>
            <td colspan="4" class="table-header">Plate Number</td>
            <td colspan="3" class="table-header">Driver Assigned</td>
            <td colspan="3" class="table-header">Current Status</td>
        </tr>
        <?php if (empty($trucks)): ?>
            <tr><td colspan="12" class="no-data">No registered trucks found in the system database.</td></tr>
        <?php else: ?>
            <?php $i = 1; foreach ($trucks as $t): ?>
            <tr>
                <td colspan="2" class="table-cell" style="text-align: center;"><?php echo $i++; ?></td>
                <td colspan="4" class="table-cell"><?php echo $t['plate_number'] ?? 'N/A'; ?></td>
                <td colspan="3" class="table-cell"><?php echo $t['name']; ?></td>
                <td colspan="3" class="table-cell" style="text-align: center;"><?php echo strtoupper($t['status'] ?? 'IDLE'); ?></td>
            </tr>
            <?php endforeach; ?>
        <?php endif; ?>

        <tr><td colspan="12" style="height: 20px;"></td></tr>

        <!-- COMPLAINTS ANALYTICS -->
        <tr><td colspan="12" class="header-section">Complaints Analytics</td></tr>
        <tr><td colspan="12" class="table-header">Complaints Volume Summary</td></tr>
        <tr>
            <td colspan="4" class="label-cell" style="text-align: center;">Pending: <?php echo $pending_complaints; ?></td>
            <td colspan="4" class="label-cell" style="text-align: center;">In Progress: <?php echo $inprogress_complaints; ?></td>
            <td colspan="4" class="label-cell" style="text-align: center;">Resolved: <?php echo $resolved_complaints; ?></td>
        </tr>
        <tr>
            <td colspan="1" class="table-header">ID</td>
            <td colspan="2" class="table-header">Category</td>
            <td colspan="6" class="table-header">Complaint Description</td>
            <td colspan="3" class="table-header">Date Filed</td>
        </tr>
        <?php if (empty($complaints)): ?>
            <tr><td colspan="12" class="no-data">No complaints found for the selected period.</td></tr>
        <?php else: ?>
            <?php $i = 1; foreach ($complaints as $c): ?>
            <tr>
                <td colspan="1" class="table-cell" style="text-align: center;"><?php echo $i++; ?></td>
                <td colspan="2" class="table-cell"><?php echo $c['category']; ?></td>
                <td colspan="6" class="table-cell"><?php echo $c['description']; ?></td>
                <td colspan="3" class="table-cell" style="text-align: center;"><?php echo date('Y-m-d', strtotime($c['created_at'])); ?></td>
            </tr>
            <?php endforeach; ?>
        <?php endif; ?>

        <tr><td colspan="12" style="height: 20px;"></td></tr>

        <!-- OPERATIONAL EFFICIENCY -->
        <tr><td colspan="12" class="header-section">Operational Efficiency</td></tr>
        <tr>
            <td colspan="3" class="table-header">Total Distance</td>
            <td colspan="3" class="table-header">Total Stops</td>
            <td colspan="3" class="table-header">Avg Coll. Time</td>
            <td colspan="3" class="table-header">Prediction Error</td>
        </tr>
        <tr>
            <td colspan="3" class="value-cell" style="text-align: center;"><?php echo $total_dist; ?></td>
            <td colspan="3" class="value-cell" style="text-align: center;"><?php echo $total_stops; ?></td>
            <td colspan="3" class="value-cell" style="text-align: center;"><?php echo $avg_coll_time; ?></td>
            <td colspan="3" class="value-cell" style="text-align: center;">0.0s</td>
        </tr>

        <tr><td colspan="12" style="height: 20px;"></td></tr>

        <!-- PUROK COVERAGE DETAILS -->
        <tr><td colspan="12" class="header-section">Purok Coverage Details</td></tr>
        <tr>
            <td colspan="4" class="table-header">Purok Area Name</td>
            <td colspan="4" class="table-header">Visit Frequency</td>
            <td colspan="4" class="table-header">Last Collection Timestamp</td>
        </tr>
        <?php foreach ($coverage_data as $purok => $data): ?>
        <tr>
            <td colspan="4" class="table-cell"><?php echo $purok; ?></td>
            <td colspan="4" class="table-cell" style="text-align: center;"><?php echo $data['count']; ?> visits</td>
            <td colspan="4" class="table-cell" style="text-align: center;"><?php echo $data['last']; ?></td>
        </tr>
        <?php endforeach; ?>
    </table>
</body>
</html>
<?php

function handle_zip_export() {
    global $conn;
    header("Content-Type: application/json");
    $backup_dir = 'backups/';
    $export_dir = 'exports/';
    if (!file_exists($export_dir)) mkdir($export_dir, 0777, true);
    foreach (glob($export_dir . "*.zip") as $old_zip) {
        if (time() - filemtime($old_zip) > 3600) unlink($old_zip);
    }
    $zip_filename = 'GTracker_Snapshots_Bundle_' . date('Y-m-d_His') . '.zip';
    $zip_filepath = $export_dir . $zip_filename;
    try {
        if (!extension_loaded('zip')) throw new Exception("Server Error: PHP ZIP extension is not enabled.");
        $zip = new ZipArchive();
        if ($zip->open($zip_filepath, ZipArchive::CREATE | ZipArchive::OVERWRITE) !== TRUE) throw new Exception("Technical Error: Cannot create ZIP bundle.");
        $files_added = 0;
        if (file_exists($backup_dir)) {
            $files = scandir($backup_dir);
            foreach ($files as $file) {
                if (strpos($file, '.sql') !== false) { $zip->addFile($backup_dir . $file, $file); $files_added++; }
            }
        }
        $zip->close();
        if ($files_added === 0) throw new Exception("No snapshots found. Please create a 'Backup Now' first.");
        echo json_encode(["success" => true, "message" => "Successfully bundled $files_added snapshots.", "url" => get_absolute_url($zip_filepath)]);
    } catch (Exception $e) { echo json_encode(["success" => false, "message" => $e->getMessage()]); }
}
?>
