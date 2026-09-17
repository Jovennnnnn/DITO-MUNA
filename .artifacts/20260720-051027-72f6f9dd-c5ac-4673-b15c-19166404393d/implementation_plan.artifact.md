# Enhanced Excel Report Export Implementation

Implement a professional, stylized Excel export feature for the Garbage Tracking & Analytics system that matches the provided UI screenshots.

## User Review Required

- **Excel Format**: The report will be generated using a specialized HTML-to-Excel approach. This allows me to use **CSS directly** to define the exact colors (Dark Green: `#004D40`, Teal: `#00BFA5`), borders, and layout requested in the screenshots. Excel recognizes this format and will render it as a native spreadsheet.
- **Backend URL Change**: I will change the hardcoded `http://localhost:8080/export_report.php` in `AnalyticsScreen` to use the project's base URL (`ApiClient.baseUrl`).

## Proposed Changes

### [Frontend] Analytics Screen

#### [analytics_screen.dart](file:///C:/xampp/htdocs/Most-Complete-main0/lib/screens/analytics_screen.dart)

- Modify `_exportReport` to:
    - Use `ApiClient.baseUrl` instead of hardcoded `localhost:8080`.
    - Improve parsing of AI insights to extract "Tomorrow's" and "Weekly" waste predictions.
    - Pass additional parameters: `waste_tomorrow`, `waste_weekly`, `total_drivers`.
    - Send the current `_geminiSummary` as `insight1` and `_recommendations` as `insight2`.

### [Backend] Report Engine

#### [export_report.php](file:///C:/xampp/htdocs/Most-Complete-main0/backend/export_report.php)

- Completely rewrite to handle `format=xls`.
- Implement a comprehensive HTML/CSS template that matches the screenshot design:
    - **Header**: Dark green "GARBAGE TRACKING & ANALYTICS REPORT" bar.
    - **Summary Section**: Grid with Period, Total Drivers, Date Generated, etc.
    - **Performance Overview**: Teal header with Resolution Rate, Avg Response Time, etc.
    - **Waste Predictions**: Sections for Tomorrow's, Weekly Forecast, and AI Insights.
    - **Fleet Distribution**: Summary counts and a detailed table of trucks (Plate, Driver, Status).
    - **Complaints Analytics**: Summary counts and a detailed table of recent complaints.
    - **Purok Coverage**: Detailed table of visit frequencies and last collection timestamps for all Puroks.
- Logic to fetch data from MySQL:
    - `users` and `truck_locations` for fleet status.
    - `complaints` for issues.
    - `collection_logs` for purok visit frequencies.

---

## Verification Plan

### Automated Tests
- No automated tests are applicable for this UI-heavy export, but I will perform manual verification of the generated file.

### Manual Verification
1.  **Launch the App**: Run the Flutter app and navigate to the Analytics screen.
2.  **Trigger Export**: Click the **EXPORT** button and select **Excel Spreadsheet (.xlsx)**.
3.  **Open Exported File**:
    - Verify the filename is correct (e.g., `Official_Report_YYYYMMDD_HHMMSS.xls`).
    - Verify the layout matches the screenshots exactly (colors, fonts, sections).
    - Verify the data matches what is currently in the dashboard (Purok visits, truck counts, etc.).
4.  **Edge Cases**:
    - Test with "All Areas" and specific Purok filters.
    - Test when there is no data (ensure "No records found" messages appear as in the screenshot).
