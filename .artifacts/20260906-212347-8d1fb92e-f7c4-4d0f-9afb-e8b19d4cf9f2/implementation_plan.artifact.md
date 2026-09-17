# Implementation Plan - Revert Modal Scroll Behavior

This plan focuses on reverting the "Data Management" modals in the Driver and Resident apps to their previous scrollable behavior while maintaining the new spacing and responsive layout quality.

## Proposed Changes

### UI & Modal Adjustments

#### [driver_settings_screen.dart](file:///C:/xampp/htdocs/august31-main/lib/screens/driver_settings_screen.dart)
- **Revert Modal Height**: Decrease the `maxHeightMultiplier` for the `Data Management` modal from `0.9` back to `0.6` (or the previous scroll-friendly value). This will allow the modal to be more compact and scrollable as it was before.

#### [driver_dashboard.dart](file:///C:/xampp/htdocs/august31-main/lib/screens/driver_dashboard.dart)
- **Dashboard Header Edit**: Revert the `maxHeightMultiplier` for the `DataManagementModal` call in the header to allow scrolling.

#### [resident_dashboard.dart](file:///C:/xampp/htdocs/august31-main/lib/screens/resident_dashboard.dart)
- **Dashboard Header Edit**: Revert the `maxHeightMultiplier` for the `DataManagementModal` to allow scrolling, maintaining consistency with the Driver version.

#### [data_management_modal.dart](file:///C:/xampp/htdocs/august31-main/lib/widgets/data_management_modal.dart)
- **Internal Height Constraints**: Adjust the `BoxConstraints` to allow the content to scroll within a smaller fixed height.

### Layout Stability
- Ensure that despite the reduced height, the spacing between titles and input fields remains at the new improved values, and the overall UI remains responsive.

## Verification Plan

### Manual Verification
1.  **Scroll Check**:
    - Open "Data Management" from both Settings and Dashboard.
    - Verify that the modal is smaller and allows for vertical scrolling to reach all fields.
2.  **Responsive Check**:
    - Ensure the layout still adapts correctly when the keyboard is open and provides enough room for the active input field.
