# Migration Walkthrough: Android (Kotlin) to Flutter (Dart)

The entire Android system logic and UI have been mapped to a modern Flutter architecture. This allows the application to run on both **Android** and **iOS** from a single codebase.

## 🔄 File Migration Mapping

| Feature | Old Kotlin/XML File | New Flutter (Dart) File |
| :--- | :--- | :--- |
| **Login Logic** | `MainActivity.kt` | `lib/screens/login_screen.dart` |
| **Admin Dashboard** | `AdminDashboardActivity.kt` | `lib/screens/admin_dashboard.dart` |
| **Registration** | `RegisterActivity.kt` | `lib/screens/register_choice_screen.dart` |
| **Network Client** | `RetrofitClient.kt` | `lib/api/api_client.dart` |
| **API Endpoints** | `ApiService.kt` | `lib/api/api_service.dart` |
| **Session** | `SessionManager.kt` | `lib/utils/session_manager.dart` |
| **Logs Model** | `SystemLog.kt` | `lib/models/system_log.dart` |
| **User Model** | `UserModels.kt` | `lib/models/user.dart` |

## 🛠️ How to Run the New App

1.  **Install Flutter**: Ensure you have the Flutter SDK installed on your Windows machine.
2.  **Navigate to Project**: Open the `flutter_app` folder in VS Code or Android Studio.
3.  **Install Dependencies**: Run the following command in the terminal:
    ```bash
    flutter pub get
    ```
4.  **Configure Backend**: Open `lib/api/api_client.dart` and ensure the `baseUrl` matches your XAMPP IP address.
5.  **Run App**:
    ```bash
    flutter run
    ```

## 📍 Native Features Integration
- **Maps**: Migrated to `mapbox_maps_flutter`. You will need to add your Mapbox Public Token to the configuration.
- **Real-time Data**: Integrated using `firebase_database`.
- **Persistent Storage**: Migrated from SharedPreferences to `shared_preferences`.
