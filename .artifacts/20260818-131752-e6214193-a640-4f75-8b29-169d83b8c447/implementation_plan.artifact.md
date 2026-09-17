# Updated Implementation Plan - Fix Button Hover Clipping

This plan addresses the visual clipping issue where the `HoverActionButton`'s zoom effect hits the side boundaries of the bottom sheet in the Resident Dashboard.

## Proposed Changes

### [Resident Settings Screen]

#### [resident_settings_screen.dart](file:///C:/xampp/htdocs/flutter-app-main/lib/screens/resident_settings_screen.dart)

- **Fix Button Clipping**:
    - Locate the `_showStyledBottomSheet` helper function.
    - Increase the horizontal padding of the container from `24` to `32` (or adjust the `Padding` around the `children` list).
    - Alternatively, wrap the buttons in a `Padding` widget with horizontal space to allow for the 1.03x scale factor without hitting the edge of the modal.
    - Specifically, in `_showDataManagementModal`, ensure the `HoverActionButton` widgets for "Save Changes" and "Delete Account" have enough horizontal clearance.

---

## Verification Plan

### Automated Tests
- N/A

### Manual Verification
1.  **Data Management Modal**:
    - Open the Data Management modal.
    - Hover over the "Save Changes" button.
    - Verify that the zoom effect is smooth and the button edges are NOT cut off or "hidden" by the side of the modal.
    - Hover over the "Delete Account" button and verify the same.
2.  **Change Password Modal**:
    - Verify the "Save Changes" button there also has enough room to scale without clipping.
