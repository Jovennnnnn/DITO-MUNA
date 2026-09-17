import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'session_manager.dart';

class SystemLogger {
  static final FirebaseDatabase _database = FirebaseDatabase.instance;

  /// Logs a system event to Firebase node 'system_logs'
  /// [type]: LOGIN, LOGOUT, EXPORT, UPDATE
  static Future<void> logEvent(String type, String message) async {
    try {
      final user = await SessionManager.getUser();
      final String adminName = user?.name ?? "System Admin";
      final int timestamp = DateTime.now().millisecondsSinceEpoch;
      final String date = DateFormat('yyyy-MM-dd').format(DateTime.now());

      final newLogRef = _database.ref('system_logs').push();
      await newLogRef.set({
        'type': type,
        'message': message,
        'adminName': adminName,
        'timestamp': timestamp,
        'date': date,
      });

      // Trigger auto-cleanup logic (30-day retention)
      await _cleanupOldLogs();
    } catch (e) {
      print("SystemLogger Error: $e");
    }
  }

  /// Removes logs older than 30 days
  static Future<void> _cleanupOldLogs() async {
    try {
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;
      
      final query = _database.ref('system_logs').orderByChild('timestamp').endAt(thirtyDaysAgo);
      final snapshot = await query.get();

      if (snapshot.exists && snapshot.value != null) {
        final Map<dynamic, dynamic> oldLogs = snapshot.value as Map<dynamic, dynamic>;
        for (var key in oldLogs.keys) {
          await _database.ref('system_logs').child(key).remove();
        }
      }
    } catch (e) {
      print("Cleanup Error: $e");
    }
  }
}
