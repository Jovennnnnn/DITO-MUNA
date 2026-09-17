# Resident Complaints Screen Enhancements

Improve the "Clear All" functionality with sequential swipe animations and enhance the UI/UX for the web interface.

## User Review Required

> [!IMPORTANT]
> The "Clear All" confirmation dialog will be retained to prevent accidental data loss, but the deletion process will now feature a sequential animation where each complaint item swipes right and moves up one by one.

## Proposed Changes

### [Screens]

#### [MODIFY] [resident_complaints_screen.dart](file:///C:/xampp/htdocs/august31-main/lib/screens/resident_complaints_screen.dart)
- Replace `ListView.builder` with `AnimatedList` for both desktop and mobile layouts.
- Update `_handleClearAll` to remove items sequentially with a delay, triggering the `AnimatedList` removal animation.
- Improve the Desktop/Web layout by adjusting spacing and enhancing card design.
- Add "wow impact" animations (hover effects, scale transitions) to complaint cards.
- Refine the status summary cards for a cleaner look.

## Verification Plan

### Manual Verification
- Navigate to the Resident Complaints screen on a web browser.
- Verify that the complaint cards are well-spaced and have a modern, polished look.
- Click "Clear All" and confirm the action.
- Observe the sequential "swipe right" animation for each complaint card.
- Verify that all complaints are successfully deleted from both the local state and the backend/Firebase.
