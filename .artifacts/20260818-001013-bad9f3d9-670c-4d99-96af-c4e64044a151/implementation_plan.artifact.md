# Admin Response Visibility Plan

This plan outlines the changes to show the admin's response to complaints directly on the resident's complaint history cards.

## Proposed Changes

### Resident Complaints Screen

#### [resident_complaints_screen.dart](file:///C:/xampp/htdocs/flutter-app-main/lib/screens/resident_complaints_screen.dart)

- **UI Card Update**:
    - Update `_buildOrganizedComplaintItem` to check for the `admin_response` field in the complaint data.
    - If `admin_response` is not null and not empty:
        - Add a specialized section at the bottom of the card (above the date).
        - Style it with a light background (e.g., `Colors.green.shade50`) and a "Admin Response:" label to make it stand out.
        - Use a distinct icon (e.g., `Icons.chat_bubble_outline_rounded`) to indicate feedback.
- **Improved Layout**: Ensure the description and admin response are spaced correctly so the card remains readable even with long messages.

---

## Verification Plan

### Manual Verification
- **Admin Feedback Display**:
    - As an Admin, resolve a complaint and add a message: "We have collected the garbage in your area."
    - As a Resident, open the Complaints page.
    - Verify that the card now shows the Admin's message in a highlighted section.
- **Empty Response**:
    - Verify that complaints without an admin response (e.g., Pending ones) do not show the response section at all.
- **Responsiveness**:
    - Verify the card expands gracefully on both Web and Mobile when a response is present.
