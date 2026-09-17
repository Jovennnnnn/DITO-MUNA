# Implementation Plan - Map Control Feedback & Profile Border Consistency

The goal is to apply consistent temporary green feedback to the Target (GPS) buttons and unify the profile picture border color between the Home Dashboard and Settings screen.

## Proposed Changes

### Map Button Feedback (Target Icon)
I will implement a temporary "active" state that turns the Target button green for 2 seconds upon clicking, regardless of the follow-lock state.

#### [mapbox_view.dart](file:///C:/xampp/htdocs/august31-main/lib/widgets/mapbox_view.dart) (Mini-Map)
- Add `bool _isTargetActive = false` to the state.
- Update the Target button's `onTap`:
    - Set `_isTargetActive = true`.
    - Use `Future.delayed` to set it back to `false` after 2 seconds.
- Update `isActive` property of `_buildMiniMapAction` to use `_isFollowLocked || _isTargetActive`.

#### [resident_track_truck_screen.dart](file:///C:/xampp/htdocs/august31-main/lib/screens/resident_track_truck_screen.dart) (Full Map)
- Add `bool _isTargetActive = false` to the state.
- Update the Target button's `onTap` in `_buildMapControls`:
    - Set `_isTargetActive = true`.
    - Use `Future.delayed` to set it back to `false` pagkalipas ng 2 seconds.
- Update the button's background and icon color logic to check for `_isFollowLocked || _isTargetActive`.

### Profile Picture Border Consistency
#### [resident_settings_screen.dart](file:///C:/xampp/htdocs/august31-main/lib/screens/resident_settings_screen.dart)
- Update the profile picture container's `border` color.
- **Old**: `AppColors.tealText.withValues(alpha: 0.2)`
- **New**: `const Color(0xFF00695C)` (matching the Home Dashboard's profile border).

---

## Verification Plan

### Manual Verification
- **Mini-Map**: Click the GPS button; verify it turns green for 2 seconds even if follow is already locked.
- **Track Page**: Click the GPS button; verify the same green feedback behavior.
- **Settings Page**: Check the profile picture border; verify it is now a solid dark green (`#00695C`).
