import 'package:shared_preferences/shared_preferences.dart';

class RoutePersistenceManager {
  static const String _keyLastRoute = 'last_visited_route';
  static const String _keyForgotPasswordStep = 'forgot_password_step';
  static const String _keyForgotPasswordEmail = 'forgot_password_email';

  /// Saves the last visited route name.
  static Future<void> saveLastRoute(String routeName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastRoute, routeName);
  }

  /// Gets the last visited route name.
  static Future<String?> getLastRoute() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastRoute);
  }

  /// Clears the last visited route (e.g., on logout).
  static Future<void> clearLastRoute() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLastRoute);
  }

  /// Saves the current step in Forgot Password flow.
  static Future<void> saveForgotPasswordState(int step, String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyForgotPasswordStep, step);
    await prefs.setString(_keyForgotPasswordEmail, email);
  }

  /// Gets the Forgot Password flow state.
  static Future<Map<String, dynamic>?> getForgotPasswordState() async {
    final prefs = await SharedPreferences.getInstance();
    final step = prefs.getInt(_keyForgotPasswordStep);
    final email = prefs.getString(_keyForgotPasswordEmail);
    if (step != null && email != null) {
      return {'step': step, 'email': email};
    }
    return null;
  }

  /// Clears the Forgot Password state.
  static Future<void> clearForgotPasswordState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyForgotPasswordStep);
    await prefs.remove(_keyForgotPasswordEmail);
  }
}
