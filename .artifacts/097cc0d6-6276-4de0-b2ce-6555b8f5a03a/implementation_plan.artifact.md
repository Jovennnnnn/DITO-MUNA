# Implementation Plan - Fix Resident Settings Modals Spacing

Adjust the swipe-up modals in the Resident Settings dashboard to ensure content is not too close to the bottom of the device, matching the spacing of the Data Management modal.

## User Review Required

> [!NOTE]
> I am adding a 40px bottom padding to all resident settings modals to raise the content from the bottom edge. This will affect:
> - Profile Picture Upload
> - Change Password
> - Language Selection
> - FAQs
> - Terms and Conditions
> - Contact Support
> - About Us

## Proposed Changes

### Resident Settings Screen

#### [MODIFY] [resident_settings_screen.dart](file:///C:/xampp/htdocs/august31-main/lib/screens/resident_settings_screen.dart)

- Update `_showStyledBottomSheet` to include bottom padding in its `SingleChildScrollView`.
- Add `MediaQuery.of(context).padding.bottom` to the main container's padding to respect safe areas on modern devices.
- Standardize the bottom spacing across all modals.

## Verification Plan

### Manual Verification
- Open Resident Settings.
- Trigger each modal (Upload Photo, Change Password, Language, etc.).
- Verify that the bottom-most content (buttons or text) has a comfortable gap from the device's bottom edge.
- Compare with the Data Management modal to ensure consistency.
