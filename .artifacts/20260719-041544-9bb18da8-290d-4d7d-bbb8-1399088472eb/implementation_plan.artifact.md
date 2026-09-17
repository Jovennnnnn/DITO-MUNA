# Connect Fleet Status to Real-time GPS Data

The user reported that the 'Fleet Status' UI is likely using mockup data and is not connected to the driver's GPS. My research confirmed that while `truck_locations` in Firebase RTDB is being used for some data (status, distance, visited_puroks), other fields like 'Fuel' and 'Stops' are hardcoded in the UI, and actual GPS tracking (latitude/longitude updates) is missing from the Flutter app (it's only in the legacy Java code).

## User Review Required

> [!IMPORTANT]
> I will be adding `geolocator` and `permission_handler` dependencies to `pubspec.yaml` to enable real-time GPS tracking on the driver's device.

- **GPS Privacy**: The app will request location permissions from the driver. Tracking will only occur when the driver sets their status to 'ACTIVE'.
- **Mockup Data Replacement**: I will replace the hardcoded "3.4 km", "0.7 L", and "2" stops with dynamic data from Firebase.

## Proposed Changes

### Dependencies

#### [pubspec.yaml](file:///C:/xampp/htdocs/Most-Complete-main0/pubspec.yaml)

- Add `geolocator: ^11.0.0`
- Add `permission_handler: ^11.3.1`

---

### Driver Operations

#### [driver_dashboard.dart](file:///C:/xampp/htdocs/Most-Complete-main0/lib/screens/driver_dashboard.dart)

- Implement a periodic GPS tracking service that runs when status is 'ACTIVE'.
- Update Firebase RTDB `truck_locations/{truckId}` with real-time `latitude`, `longitude`, `speed`, and `purok` (based on proximity to known Purok coordinates).
- Calculate distance traveled and update Firebase.

---

### UI Integration

#### [track_trucks_screen.dart](file:///C:/xampp/htdocs/Most-Complete-main0/lib/screens/track_trucks_screen.dart)
#### [resident_track_truck_screen.dart](file:///C:/xampp/htdocs/Most-Complete-main0/lib/screens/resident_track_truck_screen.dart)

- Update `_buildDetailedTruckCard` to use dynamic data from the Firebase snapshot.
- Remove hardcoded "N/A" and replace with actual truck/driver info.
- Show "No active units" more gracefully if Firebase is empty.

---

### Backend Sync

#### [update_location.php](file:///C:/xampp/htdocs/Most-Complete-main0/backend/update_location.php)

- (Optional/Secondary) Ensure the Flutter app also pings the MySQL backend for long-term history/logging if required by the user, though Firebase is the primary real-time source.

## Verification Plan

### Automated Tests
- I will run `flutter pub get` to verify dependencies.
- I will use `analyze_file` to check for syntax errors in modified files.

### Manual Verification
- **Simulated GPS Movement**: If possible, I will use a test script or manual Firebase updates to verify that the UI reacts to position changes.
- **UI Inspection**: Verify that "Fleet Status" cards no longer show hardcoded "0.7 L" etc. unless that's the actual value.
- **Log Monitoring**: Use `print` statements (monitored via logcat if applicable) to verify GPS updates are being sent to Firebase.
