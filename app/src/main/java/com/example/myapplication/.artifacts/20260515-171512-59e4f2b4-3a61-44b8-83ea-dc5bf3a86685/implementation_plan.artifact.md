# Implement User Permissions Functionality

This plan outlines the steps to make the "User Permissions" dialog functional by allowing admins to toggle access to the Database and Analytics features. These settings will be stored locally via `SessionManager` and enforced in the Admin Dashboard.

## Proposed Changes

### [Layouts]

#### [dialog_user_permissions.xml](file:///C:/xampp/htdocs/Asia-repo1-main/app/src/main/res/layout/dialog_user_permissions.xml)
- Add IDs to the MaterialCheckBox elements to allow programmatic access.
    - `cb_manage_database` for the "Manage Database" option.
    - `cb_view_analytics` for the "View Analytics" option.

### [Utils]

#### [SessionManager.kt](file:///C:/xampp/htdocs/Asia-repo1-main/app/src/main/java/com/example/myapplication/utils/SessionManager.kt)
- Add keys for storing permission states: `KEY_PERM_MANAGE_DATABASE` and `KEY_PERM_VIEW_ANALYTICS`.
- Add getter and setter methods:
    - `canManageDatabase(): Boolean`
    - `setManageDatabaseEnabled(enabled: Boolean)`
    - `canViewAnalytics(): Boolean`
    - `setViewAnalyticsEnabled(enabled: Boolean)`

### [Activities]

#### [AdminSettingsActivity.kt](file:///C:/xampp/htdocs/Asia-repo1-main/app/src/main/java/com/example/myapplication/AdminSettingsActivity.kt)
- In `showModal`, add a specific branch for `R.layout.dialog_user_permissions`.
- Load the current permission states from `SessionManager` when the dialog opens.
- Implement the `btn_apply_permissions` click listener to save the new states and show a success notification.

#### [AdminDashboardActivity.kt](file:///C:/xampp/htdocs/Asia-repo1-main/app/src/main/java/com/example/myapplication/AdminDashboardActivity.kt)
- In `setupClickListeners`, check the permissions from `SessionManager` before allowing access to Analytics or User Management.
- Optionally hide or disable the corresponding UI elements (`row_analytics`, `row_residents`) if permissions are revoked.

---

## Verification Plan

### Manual Verification
1. **Open Admin Settings**: Navigate to the Settings tab in the Admin app.
2. **Toggle Permissions**: Click on "User Permissions" and uncheck "View Analytics".
3. **Apply Changes**: Click "Apply Changes". Verify the success toast appears.
4. **Test Restriction**: Go back to the Dashboard and try to click the "Analytics" row. It should either be hidden or show an "Access Denied" message.
5. **Re-enable**: Go back to Settings, re-enable "View Analytics", and verify that access is restored.
6. **Persistence**: Close the app completely and reopen it. Verify that the permission settings are preserved.
