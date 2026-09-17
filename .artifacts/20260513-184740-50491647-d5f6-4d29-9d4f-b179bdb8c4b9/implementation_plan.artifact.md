# Implementation Plan - Modernized User Management, Filters, and Archiving System

This plan addresses UI interactivity issues, streamlines the date filtering process, modernizes the Purok selection, and implements a robust multi-select archiving system with auto-deletion.

## User Review Required

> [!IMPORTANT]
> - **Unified Date Picker**: I will replace the current two-step date selection with a single-step Date Range Picker. Users can select a single date (by clicking it twice) or a range.
> - **Archive Logic**: Archiving will now be "soft-delete". Archived users will be moved to a dedicated "Archive" view (accessible via a new button), prevented from logging in, and automatically deleted after 6 months of inactivity in the archive.
> - **Multi-Select**: I will implement a "Selection Mode" to allow bulk archiving/unarchiving of users.

## Proposed Changes

### Database & Backend

#### [archive_user.php](file:///C:/xampp/htdocs/Asia-repo1-main/backend/archive_user.php)
- Update to set `archived_at = NOW()` when `is_archived` is set to 1.
- Support bulk archiving if feasible (or call repeatedly from Android).

#### [login.php](file:///C:/xampp/htdocs/Asia-repo1-main/backend/login.php)
- Update SQL queries to check `AND is_archived = 0`.
- Return a specific error message if an archived user tries to log in ("Your account has been archived. Please contact admin.").

#### [get_users.php](file:///C:/xampp/htdocs/Asia-repo1-main/backend/get_users.php)
- Implement auto-deletion: Run a `DELETE` query for records where `is_archived = 1` and `archived_at` is older than 6 months.

---

### Android Application - UI & Interactivity

#### [activity_user_management.xml](file:///C:/xampp/htdocs/Asia-repo1-main/app/src/main/res/layout/activity_user_management.xml)
- Add a "Select" ImageButton in the header for multi-select.
- Add an "Archive" ImageButton in the header (near Search) or as a floating action button to open the Archive view.
- Add a hidden "Selection Actions" bar (Archive, Unarchive, Delete, Cancel) that appears when in Selection Mode.

#### [item_user_card.xml](file:///C:/xampp/htdocs/Asia-repo1-main/app/src/main/res/layout/item_user_card.xml)
- Add a `CheckBox` (start-aligned) that is only visible during Selection Mode.

#### [UserManagementActivity.kt](file:///C:/xampp/htdocs/Asia-repo1-main/app/src/main/java/com/example/myapplication/UserManagementActivity.kt)
- **Filters**:
    - `btnDatePicker`: Open `MaterialDatePicker.dateRangePicker()` directly.
    - `layoutPurokFilter`: Open a new `BottomSheetDialog` showing the Purok list.
- **Archiving**:
    - Implement `isSelectionMode` logic.
    - Implement a "Show Archived" mode that changes the UI to display only archived items and switches the "Archive" action to "Unarchive".
    - Implement bulk archive/unarchive functionality.
- **Touch Sensitivity**: Ensure all filter containers have `android:foreground="?attr/selectableItemBackground"` for better feedback.

---

## Verification Plan

### Manual Verification
1. **Filter Responsiveness**:
   - Tap anywhere in the "Date" box; verify the Calendar opens immediately.
   - Tap anywhere in the "Purok" box; verify the BottomSheet modal opens.
2. **Date Filtering**:
   - Select a range; verify the list updates.
   - Clear the filter from the modal/UI; verify "All Time" returns.
3. **Archive Flow**:
   - Select multiple users and click "Archive".
   - Switch to the "Archive" tab; verify they are there.
   - Try logging in with an archived account; verify it is blocked.
   - Unarchive a user; verify they return to their original tab (Resident/Driver).
4. **Auto-Delete (Simulation)**:
   - Manually set `archived_at` in the DB to 7 months ago.
   - Refresh the user list; verify the record is permanently gone.
