# Standardize Resident UI and Modals

Improve the consistency and professionalism of the resident settings page, modals, and notification system. This includes updating header styles, relocating buttons, and formalizing legal text layouts.

## Proposed Changes

### Localization & Utilities
#### [app_localizations.dart](file:///C:/xampp/htdocs/flutter-app-main/lib/utils/app_localizations.dart)
- Update `terms_conditions` and `privacy_policy` values to "Terms and Conditions" and "Privacy Policy" (removing `&` for a more formal look).
- Ensure no underscores exist in any user-facing localization values.

---

### UI Components & Modals
#### [resident_settings_screen.dart](file:///C:/xampp/htdocs/flutter-app-main/lib/screens/resident_settings_screen.dart)
- Update `_showStyledBottomSheet` to include:
    - `AppColors.tealText` (green) for the title.
    - A consistent close (`Icons.close_rounded`) button.
    - A `Divider` below the header row.
- Ensure all settings modals (Change Password, Data Management, Language, FAQs, Contact, About) use this updated style.

#### [legal_agreement_dialog.dart](file:///C:/xampp/htdocs/flutter-app-main/lib/widgets/legal_agreement_dialog.dart)
- Update the header to match the new standardized green style with a divider.
- Refactor the content rendering to use a more formal layout (e.g., bolding section headers like "1. Acceptance of Terms").

#### [resident_dashboard.dart](file:///C:/xampp/htdocs/flutter-app-main/lib/screens/resident_dashboard.dart)
- Update the Notification Modal header to use the standardized green style with a close button and divider.
- Relocate the "Clear All" button:
    - Move it below the "Recently received system notifications" text.
    - Align it to the right side for better reachability and visual hierarchy.

---

## Verification Plan

### Automated Tests
- None available for UI layout specifics, but will perform static analysis using `analyze_file`.

### Manual Verification
1.  **Inspect Settings Page**: Open resident settings and verify "Terms and Conditions" and "Privacy Policy" labels.
2.  **Inspect Modals**: Open each modal (Change Password, Language, etc.) and verify:
    - Title is green (`tealText`).
    - Close button is present.
    - Divider is present below the header.
3.  **Inspect Legal Modals**: Verify formal formatting of content (headers are distinct).
4.  **Inspect Notification Modal**:
    - Verify header style.
    - Verify "Clear All" button is below the text and right-aligned.
5.  **Screenshot Comparison**: Take screenshots of the updated modals to confirm alignment with user requirements.
