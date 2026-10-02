import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

class AdminSettingsService {
  static final AdminSettingsService _instance = AdminSettingsService._internal();
  factory AdminSettingsService() => _instance;
  AdminSettingsService._internal();

  final FirebaseDatabase _database = FirebaseDatabase.instance;
  
  final ValueNotifier<bool> emailNotificationsEnabled = ValueNotifier<bool>(true);
  final ValueNotifier<bool> appNotificationsEnabled = ValueNotifier<bool>(true);

  void startListening() {
    _database.ref('admin_settings').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map<dynamic, dynamic> data = event.snapshot.value as Map<dynamic, dynamic>;
        
        if (data.containsKey('email_notifications_enabled')) {
          emailNotificationsEnabled.value = data['email_notifications_enabled'] == true;
        }
        
        if (data.containsKey('app_notifications_enabled')) {
          appNotificationsEnabled.value = data['app_notifications_enabled'] == true;
        }
      }
    });
  }

  Future<void> updateEmailNotifications(bool enabled) async {
    await _database.ref('admin_settings').update({
      'email_notifications_enabled': enabled,
    });
  }

  Future<void> updateAppNotifications(bool enabled) async {
    await _database.ref('admin_settings').update({
      'app_notifications_enabled': enabled,
    });
  }
}
