# Implementation Plan - Data Management Module

This plan outlines the development of the Data Management module to mirror the Kotlin application's "Safety Net" features, ensuring database integrity and administrative control.

## User Review Required

- **Backend URLs**: I will use `http://localhost/Most-Complete-main0/backend/` as the base URL to match your XAMPP setup, instead of `:8080` from the prompt, to ensure connectivity.
- **Firebase Sync**: The Auto Backup toggle will be linked to `admin_settings/auto_backup` in Firebase Realtime Database.

## Proposed Changes

### Data Management Module
#### [NEW] [data_management_screen.dart](file:///C:/xampp/htdocs/Most-Complete-main0/lib/screens/data_management_screen.dart)

- **UI Components**:
    - **Summary Cards**: Quick stats on total backups and storage used.
    - **Auto Backup Switch**: Real-time sync with Firebase using `StreamBuilder`.
    - **Action Buttons**:
        - "Backup Now": Triggers `trigger_backup.php` with a `CircularProgressIndicator`.
        - "Export Full System": Calls `export_report.php` for a PDF summary.
    - **Backup History Table**:
        - Structured list showing Filename, Date, and Size.
        - "Download" button to save the SQL file locally.
        - "Delete" button for cleanup.

### Navigation Update
#### [admin_dashboard.dart](file:///C:/xampp/htdocs/Most-Complete-main0/lib/screens/admin_dashboard.dart)

- Add "Data Management" as a new menu item in the sidebar and mobile drawer.
- Integrate it into the `IndexedStack` for seamless navigation.

### API Service Enhancements
#### [api_service.dart](file:///C:/xampp/htdocs/Most-Complete-main0/lib/api/api_service.dart)

- Ensure `triggerBackup`, `getBackupHistory`, and `exportData` methods are correctly wired to the backend PHP scripts.

---

## Verification Plan

### Manual Verification
- **Auto Backup Toggle**: Change the switch and verify the value updates in Firebase Console instantly.
- **Manual Backup**: Click "Backup Now", wait for the loader, and verify the success SnackBar with the filename.
- **History Table**: Check if the list accurately reflects the files in `backend/backups/`.
- **Download**: Click download and verify the `.sql` file is saved to the local machine.
- **Export**: Click export and verify a PDF is generated and downloaded.
