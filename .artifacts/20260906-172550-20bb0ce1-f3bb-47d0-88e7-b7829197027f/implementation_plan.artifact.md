# Implementation Plan - Resident UI Shadow Enhancements

Apply balanced shadows to the containers of complaints and notifications in the Resident Dashboard to highlight them and improve visual consistency.

## Proposed Changes

### Resident Complaints

#### [resident_complaints_screen.dart](file:///C:/xampp/htdocs/august31-main/lib/screens/resident_complaints_screen.dart)

- **Update `_buildOrganizedComplaintItem`**:
    - Replace the existing `boxShadow` with `AppTheme.balancedPulidongShadow`.
    - This will provide an even shadow on all sides (top, bottom, and sides).

### Resident Notifications

#### [resident_dashboard.dart](file:///C:/xampp/htdocs/august31-main/lib/screens/resident_dashboard.dart)

- **Update `_buildNotificationItem`**:
    - Add `boxShadow: AppTheme.balancedPulidongShadow` to the `BoxDecoration`.
    - This will highlight the notification items within the "System Notifications" modal.

---

## Verification Plan

### Manual Verification
- **Visual Inspection**:
    - Open the **Complaints** tab in the Resident Dashboard. Verify that each complaint card has a balanced shadow spreading to all sides.
    - Open the **System Notifications** modal. Verify that each notification item has a balanced shadow that highlights it against the modal background.
- **Consistency**:
    - Ensure the shadows match the style recently applied to the Driver Dashboard.
