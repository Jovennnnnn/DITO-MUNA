# Implementation Plan - Driver Dashboard Notification Selection

This plan involves modifying the notification modal in the driver dashboard to match the selection and deletion behavior of the resident dashboard.

## Proposed Changes

### [Driver Dashboard Component]

#### [MODIFY] [driver_dashboard.dart](file:///C:/xampp/htdocs/septermber16/lib/screens/driver_dashboard.dart)

- **Remove** "Select" and "Clear All" text buttons from the notification modal toolbar when not in selection mode.
- **Implement** selection mode activation via long-press (mobile) or double-tap (desktop) on notification items.
- **Add** "Select All", "Delete", and "Cancel" buttons to the toolbar when selection mode is active.
- **Update** notification item UI to show selection state (checkmark icon and background highlight).
- **Update** dismissible behavior to be disabled during selection mode.

## Verification Plan

### Manual Verification
- Open Driver Dashboard.
- Open Notifications modal.
- Verify "Select" and "Clear All" buttons are GONE.
- Long-press or Double-tap a notification item.
- Verify selection mode activates and toolbar shows "Select All", "Delete", "Cancel".
- Select multiple items and verify the count updates.
- Tap "Select All" and verify all items are selected.
- Tap "Delete" and verify selected items are removed after confirmation.
- Tap "Cancel" and verify selection mode is deactivated.
