# Resident UI & Modal Improvements Walkthrough

I have updated the Resident settings page, modals, and notification layout to ensure a more professional and consistent user experience.

## Changes Overview

### 1. Standardized Modal Headers
All resident-facing modals (Password, Language, Data Management, FAQs, Contact, About, and Notifications) now share a uniform design:
- **Green Title**: Titles use `AppColors.tealText` for a branded look.
- **Close Button**: A dedicated "X" button is placed in the top right corner.
- **Divider**: A clean horizontal line separates the header from the content.

### 2. Relocated "Clear All" Button
In the **System Notifications** modal, the "Clear All" button has been moved for better usability:
- It is now positioned **below** the "Recently received system notifications" text.
- It is **right-aligned**, making it easier to distinguish from the descriptive text.

### 3. Formalized Legal Content
The **Terms and Conditions** and **Privacy Policy** modals have been updated with a formal layout:
- **Bolded Headers**: Sections like "1. Acceptance of Terms" are now bolded for better readability.
- **Improved Content**: The layout is cleaner, using standard bullet points and spacing.
- **Label Formatting**: Removed symbols like `&` and replaced them with `and` in the English localization, and refined translations in Filipino and Bisaya.

## Verification Summary
- **Static Analysis**: Ran `analyze_file` on updated screens to ensure no syntax errors were introduced.
- **Localization Check**: Verified that all labels for legal documents are formal and free of underscores.
- **Layout Consistency**: Checked that the new header style is applied consistently across all modal types in the resident settings.
