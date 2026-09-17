import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';

// Session manager for handling user persistent data
class SessionManager {
  static const String keyUserData = "user_data";
  static const String keyIsLoggedIn = "is_logged_in";
  static const String keyAppNotifications = "app_notifications_enabled";
  static const String keyLastAutoDownload = "last_auto_download_date";

  static const String keyLastUserRole = "last_user_role";
  static const String keyLastUserId = "last_user_id";
  static const String keyLastUserPurok = "last_user_purok";
  static const String keyNotifPermissionRequested = "notif_permission_requested";

  static Future<void> saveUser(Map<String, dynamic> userMap) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyUserData, jsonEncode(userMap));
    await prefs.setBool(keyIsLoggedIn, true);
    
    // Save last user info for persistent notifications even after logout
    if (userMap['role'] != null) await prefs.setString(keyLastUserRole, userMap['role'].toString());
    if (userMap['user_id'] != null || userMap['resident_id'] != null) {
      await prefs.setString(keyLastUserId, (userMap['user_id'] ?? userMap['resident_id']).toString());
    }
    if (userMap['purok'] != null) await prefs.setString(keyLastUserPurok, userMap['purok'].toString());
  }

  static Future<UserData?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userStr = prefs.getString(keyUserData);
    if (userStr != null) {
      return UserData.fromJson(jsonDecode(userStr));
    }
    return null;
  }

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyIsLoggedIn) ?? false;
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    // Do not use clear() to preserve notification preferences and last user info
    await prefs.remove(keyUserData);
    await prefs.remove(keyIsLoggedIn);
  }

  static Future<void> setAppNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyAppNotifications, enabled);
  }

  static Future<bool> isAppNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    // Default to false for new users who haven't requested/allowed yet
    if (!prefs.containsKey(keyNotifPermissionRequested)) return false;
    return prefs.getBool(keyAppNotifications) ?? true;
  }

  static Future<void> setNotifPermissionRequested(bool requested) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyNotifPermissionRequested, requested);
  }

  static Future<bool> isNotifPermissionRequested() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyNotifPermissionRequested) ?? false;
  }

  static Future<Map<String, String?>> getLastUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'role': prefs.getString(keyLastUserRole),
      'userId': prefs.getString(keyLastUserId),
      'purok': prefs.getString(keyLastUserPurok),
    };
  }

  static Future<void> setLastAutoDownloadDate(String date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyLastAutoDownload, date);
  }

  static Future<String?> getLastAutoDownloadDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyLastAutoDownload);
  }
}
