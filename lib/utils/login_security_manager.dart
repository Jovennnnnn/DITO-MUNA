import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

class LoginSecurityManager {
  static final FirebaseDatabase _database = FirebaseDatabase.instance;
  static const int maxAttempts = 5;
  static const Duration lockoutDuration = Duration(minutes: 1);

  static String _sanitizeKey(String input) {
    // Firebase keys cannot contain certain characters
    return input.replaceAll(RegExp(r'[.#$\[\]]'), '_').toLowerCase();
  }

  static Future<SecurityStatus> checkStatus(String username) async {
    final key = _sanitizeKey(username);
    final snapshot = await _database.ref('login_security').child(key).get();

    if (!snapshot.exists) {
      return SecurityStatus(attempts: 0, isLocked: false);
    }

    final data = Map<String, dynamic>.from(snapshot.value as Map);
    final int attempts = data['failedAttempts'] ?? 0;
    final int? lockoutUntil = data['lockoutUntil'];

    if (lockoutUntil != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now < lockoutUntil) {
        debugPrint('[LOGIN] Account locked until: ${DateTime.fromMillisecondsSinceEpoch(lockoutUntil)}');
        return SecurityStatus(
          attempts: attempts,
          isLocked: true,
          lockoutUntil: DateTime.fromMillisecondsSinceEpoch(lockoutUntil),
        );
      } else {
        // Lockout expired, reset attempts (or keep them but allow login)
        // We'll reset them here to be clean
        debugPrint('[LOGIN] Lock expired');
        await resetAttempts(username);
        return SecurityStatus(attempts: 0, isLocked: false);
      }
    }

    return SecurityStatus(attempts: attempts, isLocked: false);
  }

  static Future<SecurityStatus> recordFailedAttempt(String username) async {
    final key = _sanitizeKey(username);
    final ref = _database.ref('login_security').child(key);
    
    final status = await checkStatus(username);
    final newAttempts = status.attempts + 1;
    
    debugPrint('[LOGIN] Incorrect password');
    debugPrint('[LOGIN] Failed attempts: $newAttempts');
    debugPrint('[LOGIN] Remaining attempts: ${maxAttempts - newAttempts}');

    Map<String, dynamic> updates = {
      'failedAttempts': newAttempts,
      'lastFailedAttempt': ServerValue.timestamp,
    };

    if (newAttempts >= maxAttempts) {
      final lockoutTime = DateTime.now().add(lockoutDuration);
      updates['lockoutUntil'] = lockoutTime.millisecondsSinceEpoch;
      debugPrint('[LOGIN] Account locked until: $lockoutTime');
    }

    await ref.update(updates);
    
    // Fetch updated status to return accurate lockout time
    return await checkStatus(username);
  }

  static Future<void> resetAttempts(String username) async {
    final key = _sanitizeKey(username);
    debugPrint('[LOGIN] Successful login - attempts reset');
    await _database.ref('login_security').child(key).remove();
  }
}

class SecurityStatus {
  final int attempts;
  final bool isLocked;
  final DateTime? lockoutUntil;

  SecurityStatus({
    required this.attempts,
    required this.isLocked,
    this.lockoutUntil,
  });

  int get remainingAttempts => LoginSecurityManager.maxAttempts - attempts;
}
