# Implementation Plan - Customize Resident Dashboard Notification Modal

Customize the icons and colors for different notification types in the Resident Dashboard's notification modal to improve user experience and visual clarity on both mobile and web interfaces.

## User Review Required

> [!NOTE]
> The notification types `COMPLAINT_RESOLVED` and `TRUCK_PROXIMITY` (ETA) will be assigned distinct colors and icons. Other notification types like `MAINTENANCE_ALERT` will also be updated to follow a consistent thematic color scheme instead of the default green.

## Proposed Changes

### [Resident Dashboard]

#### [MODIFY] [resident_dashboard.dart](file:///C:/xampp/htdocs/august31-main/lib/screens/resident_dashboard.dart)
- Add a helper method `_getNotificationStyle(String type)` to centralize the mapping of notification types to icons and colors.
- Update `_buildNotificationItem` to use the dynamic icon and color based on the notification type.
- Ensure the selection state colors remain consistent or adapt to the notification type's theme.
- Types to be handled:
    - `TRUCK_PROXIMITY` (ETA): Orange/Amber color with `local_shipping` icon.
    - `COMPLAINT_RESOLVED`: Indigo/Blue color with `assignment_turned_in` icon.
    - `MAINTENANCE_ALERT`: Red color with `warning` icon.
    - `ISSUE_UPDATE`: Light Blue color with `info` icon.
    - Default: Keep existing Teal/Green as fallback.

## Verification Plan

### Manual Verification
- Launch the Resident Dashboard.
- Open the Notifications Modal.
- Verify that ETA notifications (Truck Proximity) show an orange truck icon.
- Verify that Complaint Resolved notifications show an indigo assignment icon.
- Verify that the colors and icons are consistent across different screen sizes (Mobile vs Web).
