# Migration Plan: Kotlin/XML to Flutter (Dart)

This plan outlines the complete migration of the Android project to Flutter. The goal is to achieve 1:1 functional parity while supporting both Android and iOS.

## User Review Required

- **Flutter Environment**: You must have the Flutter SDK installed on your Windows machine.
- **Dependencies**: We will use `dio` for networking, `provider` or `get` for state management, and `mapbox_maps_flutter` for mapping.
- **Mapbox Token**: You will need to provide your Mapbox Access Token in the `pubspec.yaml` or native configuration.

## Proposed Changes

### [New Flutter Project Structure]
```text
lib/
├── main.dart
├── api/
│   ├── api_client.dart (was RetrofitClient.kt)
│   └── api_service.dart (was ApiService.kt)
├── models/
│   ├── system_log.dart
│   ├── user_model.dart
│   └── ...
├── screens/
│   ├── login_screen.dart (was MainActivity.kt)
│   ├── admin_dashboard.dart (was AdminDashboardActivity.kt)
│   └── ...
├── widgets/
│   ├── system_log_item.dart (was SystemLogAdapter.kt)
│   └── ...
├── utils/
│   ├── session_manager.dart
│   └── logger.dart
└── theme/
    └── app_theme.dart (was styles.xml/colors.xml)
```

### [Migration Steps]
1. **Foundation**: Create the basic project structure and `pubspec.yaml`.
2. **Models**: Convert all Kotlin data classes to Dart classes with JSON serialization.
3. **Networking**: Replace Retrofit with `Dio` and implement all endpoints.
4. **UI Conversion**: Map XML layouts to Flutter Widget trees.
5. **Logic Migration**: Port business logic from Activities to Controllers/State classes.

---

## Verification Plan

### Automated Tests
- `flutter build apk` to verify Android build.
- `flutter build ios` (requires Mac) to verify iOS build.

### Manual Verification
1. **Login Flow**: Test with the existing PHP backend.
2. **Dashboard Routing**: Ensure correct redirection based on user roles.
3. **Real-time Tracking**: Verify Mapbox and Firebase integration.
4. **System Logs**: Check if logs appear in the Firebase console.
5. **Charts**: Verify MPAndroidChart logic is correctly ported to Flutter.
