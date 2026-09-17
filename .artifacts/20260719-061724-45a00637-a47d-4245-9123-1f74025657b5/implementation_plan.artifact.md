# Implementation Plan - Analytics Export with Real Data

This plan outlines the steps to implement real-time data export for the Analytics screen in PDF and Excel formats, ensuring that the exported reports reflect the actual data seen on the dashboard instead of hardcoded values.

## Proposed Changes

### [Flutter Web Admin Dashboard]

#### [analytics_screen.dart](file:///C:/xampp/htdocs/Most-Complete-main0/lib/screens/analytics_screen.dart)

- Add missing variable declarations for AI insights and Purok names in `_AnalyticsScreenState`.
- Implement `_generateAiInsights()` to fetch real AI analysis from Gemini.
- Implement `_exportReport(String category, String format)` to trigger the backend export script with real-time data.
- Update `_showExportDialog` to correctly handle user selections and trigger the download.
- Add necessary imports (`url_launcher`).

```dart
// Example of _exportReport implementation
Future<void> _exportReport(String category, String format) async {
  final String baseUrl = ApiClient.baseUrl;
  final String dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

  final queryParams = {
    'type': category,
    'format': format.contains('PDF') ? 'pdf' : 'xls',
    'start_date': dateStr,
    'end_date': dateStr,
    'res_rate': "${_coveragePercent.toInt()}%",
    'avg_time': "${_avgCollectionTime.toStringAsFixed(1)} hours",
    'coverage': "${_coveragePercent.toInt()}%",
    'routes_done': "$_completedRoutes/$_totalRoutes",
    'active_count': "${_truckStatusData['Active']?.toInt() ?? 0}",
    'full_count': "${_truckStatusData['Full']?.toInt() ?? 0}",
    'inactive_count': "${_truckStatusData['Idle']?.toInt() ?? 0}",
    'pending_count': "${_complaintStatusData['Pending']?.toInt() ?? 0}",
    'inprogress_count': "${_complaintStatusData['In Progress']?.toInt() ?? 0}",
    'resolved_count': "${_complaintStatusData['Resolved']?.toInt() ?? 0}",
    'dist': "${_distanceCovered.toStringAsFixed(1)} km",
    'stops': "$_stopsPerRoute",
    'insight1': _geminiSummary ?? "System performing normally.",
    'insight2': _recommendations,
  };

  final uri = Uri.parse("${baseUrl}export_report.php").replace(queryParameters: queryParams);

  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
```

## Verification Plan

### Manual Verification
- **Test Export**: Open the Analytics screen, change filters, and click EXPORT.
- **Verify PDF**: Select PDF format and check if the downloaded/printed document contains the same numbers as seen on the dashboard.
- **Verify Excel**: Select Excel format and check if the generated .xls file contains correct data.
- **Verify AI Data**: Ensure AI insights are present in the exported report.
