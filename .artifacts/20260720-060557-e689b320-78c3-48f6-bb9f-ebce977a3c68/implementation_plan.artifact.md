# Implementation Plan - System Notifications preference module

Implement a "System Notifications" preference module in Flutter Web Admin that synchronizes with Firebase and triggers backend email alerts via PHP.

## User Review Required
> [!NOTE]
> The setting `admin_settings/email_notifications_enabled` and `admin_settings/app_notifications_enabled` will be treated as **Global Admin Settings**. This means changing them in one Admin session will affect all other active Admin sessions and the overall system behavior for all admins.

## Proposed Changes

### Core Services

#### [NEW] [admin_settings_service.dart](file:///C:/xampp/htdocs/Most-Complete-main0/lib/services/admin_settings_service.dart)
- Create a singleton service to manage global admin settings in Firebase.
- Provide `ValueNotifier<bool>` for `emailNotificationsEnabled` and `appNotificationsEnabled`.
- Listen to Firebase Realtime Database at `admin_settings/` for real-time updates.

#### [api_service.dart](file:///C:/xampp/htdocs/Most-Complete-main0/lib/api/api_service.dart)
- Add `notifyAdminIssue` method to call `notify_admin_issue.php`.
- Ensure `updateUserSettings` is used to sync Firebase changes back to the MySQL database.

---

### UI Components

#### [admin_settings_screen.dart](file:///C:/xampp/htdocs/Most-Complete-main0/lib/screens/admin_settings_screen.dart)
- Integrate `AdminSettingsService` to drive the toggles.
- Update UI to match Kotlin design:
    - Card-based layout with rounded corners.
    - Teal-colored switches (`#00BFA5`).
    - Standardized icons for "System Notifications".
- Update `_toggleSetting` to:
    1. Update Firebase via `AdminSettingsService`.
    2. Update MySQL via `ApiService`.
    3. Update local `SessionManager`.

#### [admin_dashboard.dart](file:///C:/xampp/htdocs/Most-Complete-main0/lib/screens/admin_dashboard.dart)
- Wrap notification snackbar logic with a check for `appNotificationsEnabled` from `AdminSettingsService`.
- Ensure real-time suppression of snackbars when notifications are disabled.

---

### Utilities

#### [session_manager.dart](file:///C:/xampp/htdocs/Most-Complete-main0/lib/utils/session_manager.dart)
- Ensure `keyAppNotifications` is consistently used for local state.

## Verification Plan

### Automated Tests
- I will perform manual verification as the project structure is tailored for web deployment and manual UI checks.

### Manual Verification
1. **Firebase Sync**:
    - Open two Admin Dashboard tabs.
    - Change notification settings in one tab.
    - Verify the other tab reflects the change immediately.
    - Check Firebase Console to verify `admin_settings/email_notifications_enabled` and `admin_settings/app_notifications_enabled` values.
2. **MySQL Sync**:
    - Change settings and check the `users` table in PHPMyAdmin to ensure `email_notifications` and `app_notifications` columns are updated.
3. **App Notification Suppression**:
    - Turn OFF App Notifications.
    - Simulate a `DRIVER_ISSUE` or `RESIDENT_COMPLAINT` in `notification_logs` in Firebase.
    - Verify NO snackbar appears in the Admin Dashboard, but the "Recent Activity" still updates.
4. **Email Notification Trigger**:
    - Turn ON Email Notifications.
    - Call the `notifyAdminIssue` endpoint (via a test button or manual API call).
    - Verify that the PHP backend sends an email (logs will be checked in the terminal/PHP error log).
