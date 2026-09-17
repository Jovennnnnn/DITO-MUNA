# Walkthrough - Notification Consent and Management

I have implemented a comprehensive notification consent and management system for residents to ensure they have control over their alerts and understand why they are receiving them.

## Changes

### 1. New Registration Consent Flow
- **Consent Dialog**: Created a new `dialog_notification_consent.xml` that appears immediately after a resident successfully registers.
- **Explanation**: The dialog explains the benefits of enabling notifications:
    - Real-time truck arrival alerts.
    - Community announcements.
    - Updates on reported complaints.
- **Preference Persistence**: User choices are immediately saved to `SessionManager`, ensuring their preference is respected from their very first login.

### 2. Resident Settings Integration
- **Functional Toggle**: The "Push Notifications" switch in `ResidentSettingsActivity.kt` is now fully functional.
- **Real-time Synchronization**: Toggling the switch instantly updates the `SessionManager`, which in turn affects the dashboard's behavior.
- **Visual Feedback**: Added Toast messages to confirm when notifications are enabled or disabled.

### 3. Smart Dashboard Alerts
- **Preference Check**: Modified `ResidentDashboardActivity.kt` to check the notification preference before showing the "Truck Nearby!" banner.
- **Suppression**: If notifications are disabled, the banner is suppressed, but internal notification lists and unread badges still update so users don't miss information when they manually check.

## Technical Details

### [ResidentRegisterActivity.kt](file:///C:/xampp/htdocs/Asia-repo1-main/app/src/main/java/com/example/myapplication/ResidentRegisterActivity.kt)
- Replaced the immediate `finish()` after registration with `showNotificationConsentDialog()`.
- Added imports for `AlertDialog`, `LayoutInflater`, and `SessionManager`.

### [ResidentSettingsActivity.kt](file:///C:/xampp/htdocs/Asia-repo1-main/app/src/main/java/com/example/myapplication/ResidentSettingsActivity.kt)
- Added `setupNotificationSwitch()` to bind the UI switch to the `SessionManager` state.

### [ResidentDashboardActivity.kt](file:///C:/xampp/htdocs/Asia-repo1-main/app/src/main/java/com/example/myapplication/ResidentDashboardActivity.kt)
- Updated the `arrivalAlertListener` to respect the `sessionManager.isAppNotificationsEnabled()` flag.

## Verification Summary
- **Privacy First**: Residents now have a clear path to opt-in or opt-out of notifications during the onboarding process.
- **User Control**: The settings toggle provides ongoing control over notification behavior.
- **Consistency**: Verified that the app state and UI correctly reflect the saved notification preferences across different activities.
