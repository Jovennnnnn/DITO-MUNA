# Implementation Plan - Universal GPS Tracking (Mobile & Web)

Implement a robust, cross-platform GPS tracking system for the `TrackTrucksScreen` that maintains the "essence" of real-time monitoring on both Mobile and Web without switching map providers.

## User Review Required
- **Web Marker Refresh Rate**: On Web, markers will reposition based on camera movement and Firebase updates. There might be a slight delay compared to native mobile markers, but the GPS data will be accurate.
- **Platform Detection**: I will use `foundation.kIsWeb` to toggle between Native and Overlay logic.

## Proposed Changes

### Tracking Component
#### [track_trucks_screen.dart](file:///C:/xampp/htdocs/Most-Complete-main0/lib/screens/track_trucks_screen.dart)
- **Universal Marker Logic**:
    - Keep `PointAnnotationManager` for Android/iOS (Native smooth tracking).
    - Implement a `Stack` + `Positioned` overlay for Web (Chrome).
- **Coordinate Conversion**: Use `mapboxMap.pointPixels()` (or similar projection math) to translate GPS Lat/Lng into Screen X/Y for the Web icons.
- **Firebase Wiring**: Ensure the listeners continue to use the shared `truck_locations` node used by the Kotlin app.
- **UI Interaction**: Ensure selecting a truck in the sidebar still pans the map correctly on both platforms.

### State Management
- Add a listener for `onCameraChangeListener` to re-calculate marker positions on Web whenever the user pans or zooms.

---

## Verification Plan

### Manual Verification
1. **Mobile Check**: Run on an emulator/device and verify that `PointAnnotationManager` creates truck markers.
2. **Web Check (Chrome)**:
    - Verify that truck icons appear on the map.
    - Verify that when a truck moves in Firebase, the icon on the Web map moves.
    - Verify that panning/zooming the map keeps the icons in their correct geographical positions.
3. **Admin Sync**: Update a truck's location manually in the Firebase console and verify both the sidebar stats and the map marker update instantly.
