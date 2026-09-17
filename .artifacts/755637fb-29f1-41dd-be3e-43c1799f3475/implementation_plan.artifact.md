# Implementation Plan - Login Page Animations & Responsiveness

Add entrance animations to the "Welcome Back" text and "Language Selection" in the Login screen to provide a smoother transition from the splash screen. Ensure the layout remains responsive across Web, Mobile, Tablet, and iOS.

## User Review Required

> [!NOTE]
> The animations are implemented using the existing `FadeSlideEntrance` widget to maintain consistency with other UI elements in the app.

## Proposed Changes

### Login Screen

#### [MODIFY] [login_screen.dart](file:///C:/xampp/htdocs/august31-main/lib/screens/login_screen.dart)

- Wrap the "Welcome Back" text in a `FadeSlideEntrance` with a `200ms` delay.
- Wrap the Language Selection row in a `FadeSlideEntrance` with a `300ms` delay.
- This creates a staggered entrance effect where the branding (Hero) appears first, followed by the subtitle, then the language choice, and finally the login form.

## Verification Plan

### Manual Verification
- Run the app on **Chrome** (`flutter run -d chrome`) to verify Web responsiveness and animation.
- Run the app on a **Physical Android Device** (`flutter run`) to verify mobile behavior.
- Check that the "Welcome Back" text and Language Selection animate smoothly after the splash screen finishes.
- Verify that the layout adjusts correctly on different screen sizes (Web/Tablet vs. Mobile).
