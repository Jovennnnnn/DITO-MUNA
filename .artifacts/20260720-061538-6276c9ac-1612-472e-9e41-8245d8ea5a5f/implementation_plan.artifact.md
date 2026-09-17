# Add Users to Navigation and Reorder Settings

This plan outlines the changes to the `AdminDashboard` to include a "Users" navigation item and move "Settings" to the end of the navigation bar (sidebar and bottom navigation).

## User Review Required

- **Navigation Order**: The new order will be: Dashboard, Track Trucks, Analytics, Complaints, Users, Data Management, Settings.
- **Bottom Navigation**: Adding "Users" to the bottom navigation bar will increase the item count to 7, which may be crowded on small mobile screens. I will monitor this.

## Proposed Changes

### Admin Dashboard Component

#### [admin_dashboard.dart](file:///C:/xampp/htdocs/Most-Complete-main0/lib/screens/admin_dashboard.dart)

- Import `user_management_screen.dart`.
- Update `IndexedStack` to include `UserManagementScreen`.
- Reorder screens in `IndexedStack` to match the new indices.
- Update `_buildSidebar` to include "Users" and move "Settings" to the end.
- Update `_buildBottomNav` to include "Users" and move "Settings" to the end.
- Update all `_selectedIndex` assignments (in Quick Actions, callbacks, etc.) to point to the new indices.

#### [user_management_screen.dart](file:///C:/xampp/htdocs/Most-Complete-main0/lib/screens/user_management_screen.dart)

- Add `onBack` callback to `UserManagementScreen` constructor.
- Implement a header with a back button when `isEmbedded` is true, similar to other screens.

## Verification Plan

### Automated Tests
- No automated tests are available for UI navigation currently.

### Manual Verification
- Deploy the app and navigate to the Admin Dashboard.
- Verify that "Users" is present in the sidebar (desktop) and bottom navigation (mobile).
- Verify that "Settings" is at the end of both navigation bars.
- Verify that clicking "Users" correctly displays the `UserManagementScreen`.
- Verify that "Quick Actions" cards (Analytics, Users, Settings) still navigate to the correct screens.
- Verify that the "Back" button in embedded screens works correctly.
