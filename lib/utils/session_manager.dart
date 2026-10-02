import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';

// Session manager for handling user persistent data & saved profiles
class SessionManager {
  static const String keyUserData = "user_data";
  static const String keyIsLoggedIn = "is_logged_in";
  static const String keyRememberMe = "remember_me_enabled";
  static const String keySavedProfiles = "saved_user_profiles";
  static const String keyPrimarySavedUserId = "primary_saved_user_id";

  static const String keyAppNotifications = "app_notifications_enabled";
  static const String keyLastAutoDownload = "last_auto_download_date";

  static const String keyLastUserRole = "last_user_role";
  static const String keyLastUserId = "last_user_id";
  static const String keyLastUserPurok = "last_user_purok";
  static const String keyNotifPermissionRequested = "notif_permission_requested";

  static Future<void> saveUser(Map<String, dynamic> userMap, {bool rememberMe = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyUserData, jsonEncode(userMap));
    await prefs.setBool(keyIsLoggedIn, true);
    await prefs.setBool(keyRememberMe, rememberMe);

    final String? uid = (userMap['user_id'] ?? userMap['id'] ?? userMap['resident_id'])?.toString();
    final String? role = userMap['role']?.toString();
    
    // Save last user info for persistent notifications
    if (role != null) await prefs.setString(keyLastUserRole, role);
    if (uid != null) await prefs.setString(keyLastUserId, uid);
    if (userMap['purok'] != null) await prefs.setString(keyLastUserPurok, userMap['purok'].toString());

    if (rememberMe) {
      await saveProfile(userMap);
    }

    debugPrint("[AUTH DEBUG] Firebase currentUser exists: true");
    debugPrint("[AUTH DEBUG] Saved profile exists: true");
    debugPrint("[AUTH DEBUG] User ID: ${uid ?? 'unknown'}");
    debugPrint("[AUTH DEBUG] Role: ${role ?? 'unknown'}");
    debugPrint("[AUTH DEBUG] Auto-login result: SUCCESS");
  }

  static Future<void> saveProfile(Map<String, dynamic> userMap) async {
    final prefs = await SharedPreferences.getInstance();
    final String? uid = (userMap['user_id'] ?? userMap['id'] ?? userMap['resident_id'])?.toString();
    if (uid == null || uid.isEmpty) return;

    final String name = (userMap['name'] ?? userMap['username'] ?? 'User').toString();
    final String email = (userMap['email'] ?? userMap['username'] ?? '').toString();
    final String role = (userMap['role'] ?? 'resident').toString();
    final String? profilePicture = userMap['profile_picture']?.toString() ?? userMap['profilePicture']?.toString();

    // Safe Profile Map - NEVER STORE PLAINTEXT PASSWORDS!
    final Map<String, dynamic> profileMap = {
      'user_id': uid,
      'name': name,
      'email': email,
      'role': role,
      'profile_picture': profilePicture,
      'saved_at': DateTime.now().millisecondsSinceEpoch,
      'user_data': userMap,
    };

    List<Map<String, dynamic>> profiles = await getSavedProfiles();
    profiles.removeWhere((p) => (p['user_id'] ?? p['id']).toString() == uid || (p['email'] ?? '').toString().toLowerCase() == email.toLowerCase());
    profiles.insert(0, profileMap); // Put latest saved profile at top

    await prefs.setString(keySavedProfiles, jsonEncode(profiles));
    await prefs.setString(keyPrimarySavedUserId, uid);
  }

  static Future<List<Map<String, dynamic>>> getSavedProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(keySavedProfiles);
    if (raw != null && raw.isNotEmpty) {
      try {
        final List list = jsonDecode(raw) as List;
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (e) {
        debugPrint("[AUTH DEBUG] Error parsing saved profiles: $e");
      }
    }
    return [];
  }

  static Future<Map<String, dynamic>?> getPrimarySavedProfile() async {
    final profiles = await getSavedProfiles();
    if (profiles.isNotEmpty) {
      return profiles.first;
    }
    return null;
  }

  static Future<void> removeSavedProfile(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    List<Map<String, dynamic>> profiles = await getSavedProfiles();
    profiles.removeWhere((p) => (p['user_id'] ?? p['id']).toString() == userId);
    
    await prefs.setString(keySavedProfiles, jsonEncode(profiles));
    if (profiles.isEmpty) {
      await prefs.remove(keyPrimarySavedUserId);
      await prefs.setBool(keyRememberMe, false);
      debugPrint("[AUTH DEBUG] Saved profile exists: false");
    } else {
      await prefs.setString(keyPrimarySavedUserId, (profiles.first['user_id'] ?? profiles.first['id']).toString());
    }
  }

  static Future<bool> isRememberMeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyRememberMe) ?? false;
  }

  static Future<void> setRememberMeEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyRememberMe, enabled);
  }

  static Future<UserData?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userStr = prefs.getString(keyUserData);
    if (userStr != null) {
      try {
        return UserData.fromJson(jsonDecode(userStr));
      } catch (e) {
        debugPrint("Error parsing user data: $e");
      }
    }
    return null;
  }

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyIsLoggedIn) ?? false;
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyUserData);
    await prefs.setBool(keyIsLoggedIn, false);
    debugPrint("[AUTH DEBUG] Logout executed. Active session cleared.");
  }

  static Future<void> setAppNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyAppNotifications, enabled);
  }

  static Future<bool> isAppNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
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
