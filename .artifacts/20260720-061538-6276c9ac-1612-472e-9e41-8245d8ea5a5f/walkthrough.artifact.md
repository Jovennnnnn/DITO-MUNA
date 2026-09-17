# Admin Dashboard Navigation Update Walkthrough

I have updated the Admin Dashboard to improve navigation by adding "Users" directly to the navigation bars and moving "Settings" to the end.

## Changes Made

### 1. User Management Integration
- Added `UserManagementScreen` to the `IndexedStack` in `AdminDashboard`.
- Updated `UserManagementScreen` to support being embedded with a back button when needed.
- This allows admins to manage users without leaving the dashboard context.

### 2. Navigation Reordering
- **New Navigation Order**:
    1. **Dashboard (Home)**
    2. **Track Trucks**
    3. **Analytics**
    4. **Complaints (Issues)**
    5. **Users** (New addition to nav bar)
    6. **Data Management**
    7. **Settings** (Moved to the end)

### 3. Sidebar and Bottom Navigation
- Updated both the desktop sidebar and mobile bottom navigation to reflect the new order and include the "Users" item.
- Ensured consistent iconography and labeling across both navigation modes.

### 4. Quick Actions Sync
- Updated the "Quick Actions" grid on the main dashboard:
    - **Analytics**: Corrected to index 2.
    - **Users**: Now navigates within the dashboard (`_selectedIndex = 4`) instead of pushing a new screen.
    - **Settings**: Updated to index 6.

## Verification Summary

- **Sidebar Items**: Dashboard(0), Track(1), Analytics(2), Complaints(3), Users(4), Data(5), Settings(6). ✅
- **Bottom Nav Items**: Home(0), Track(1), Analytics(2), Issues(3), Users(4), Data(5), Settings(6). ✅
- **IndexedStack Screens**: Correctly mapped to the indices above. ✅
- **Quick Actions**: All cards correctly update `_selectedIndex`. ✅
- **UserManagementScreen**: Correctly handles `isEmbedded` and `onBack` parameters. ✅
