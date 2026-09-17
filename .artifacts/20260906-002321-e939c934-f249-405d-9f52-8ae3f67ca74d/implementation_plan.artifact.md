# Implementation Plan - Fix Layout Overflow and Final Scroll Stability

This plan fixes the "bottom overflow" error (black and yellow stripes) that appears when the keyboard is open on the Login and Forgot Password screens.

## Proposed Changes

### [login_screen.dart](file:///C:/xampp/htdocs/august31-main/lib/screens/login_screen.dart)
### [forgot_password_screen.dart](file:///C:/xampp/htdocs/august31-main/lib/screens/forgot_password_screen.dart)

The overflow is caused by `SliverFillRemaining` trying to force a minimum size that is now larger than the visible screen space when the keyboard is open.

1.  **Replace `CustomScrollView` + `SliverFillRemaining`**:
    - We will switch to a more standard `SingleChildScrollView` combined with a `ConstrainedBox`.
    - This allows the screen to scroll naturally without "forcing" elements to fill the remaining space in a way that overflows.
2.  **Adjust `Spacer` logic**:
    - Use `Column` with `MainAxisAlignment.spaceBetween` or fixed `SizedBox` to maintain the "stayput" look without using spring-like spacers that cause overflows.
3.  **Ensure Keyboard Inset Support**:
    - Keep `resizeToAvoidBottomInset: true` to ensure the keyboard still gives the user space to scroll.

#### Specific Code Adjustment:
- Wrap the entire content in a `LayoutBuilder` and `SingleChildScrollView`.
- Use `minHeight: constraints.maxHeight` to keep everything centered/bottom-aligned when the keyboard is closed.

## Verification Plan

### Automated Tests
- Run `analyze_file` on modified files.

### Manual Verification
1.  **Keyboard Open**: Tap any field. Verify that NO "bottom overflow" error (yellow/black stripes) appears.
2.  **Scroll Test**: While keyboard is open, scroll to the bottom. Verify you can still see the "Sign In" button clearly.
3.  **Keyboard Closed**: Verify the layout still looks balanced and the logo/header is in the right place.
