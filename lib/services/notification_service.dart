import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/session_manager.dart';
import '../models/user.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  static StreamSubscription? _dbSubscription;
  static int _lastNotificationTimestamp = DateTime.now().millisecondsSinceEpoch;

  static Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _notificationsPlugin.initialize(initializationSettings);
  }

  static Future<bool> requestPermissions() async {
    if (kIsWeb) return true;

    if (Platform.isAndroid) {
      final status = await Permission.notification.request();
      return status.isGranted;
    } else if (Platform.isIOS) {
      final bool? granted = await _notificationsPlugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
      return granted ?? false;
    }
    return true;
  }

  static void startListening(UserData user) {
    _dbSubscription?.cancel();
    _lastNotificationTimestamp = DateTime.now().millisecondsSinceEpoch;

    _dbSubscription = FirebaseDatabase.instance.ref('notifications').onChildAdded.listen((event) async {
      if (!event.snapshot.exists) return;
      
      final Map data = event.snapshot.value as Map;
      final String type = (data['type'] ?? '').toString();
      final int timestamp = data['timestamp'] ?? 0;

      // Only show notifications received after listener started
      if (timestamp <= _lastNotificationTimestamp) return;

      if (_isRelevant(data, user)) {
        showNotification(
          id: event.snapshot.key.hashCode,
          title: data['title'] ?? 'System Alert',
          body: data['message'] ?? '',
          type: type,
        );
      }
    });
  }

  /// Starts listening even without a logged-in user, using last known identity
  static Future<void> startPersistentListening() async {
    _dbSubscription?.cancel();
    
    // If user is already logged in, the dashboard will call startListening(user)
    // This persistent version is for background/logged-out states
    if (await SessionManager.isLoggedIn()) {
      final user = await SessionManager.getUser();
      if (user != null) {
        startListening(user);
        return;
      }
    }

    final lastInfo = await SessionManager.getLastUserInfo();
    if (lastInfo['role'] == null) return; // No previous user to track for

    _lastNotificationTimestamp = DateTime.now().millisecondsSinceEpoch;
    
    _dbSubscription = FirebaseDatabase.instance.ref('notifications').onChildAdded.listen((event) async {
      if (!event.snapshot.exists) return;
      
      final Map data = event.snapshot.value as Map;
      final int timestamp = data['timestamp'] ?? 0;
      if (timestamp <= _lastNotificationTimestamp) return;

      // Construct a minimal "ghost" user based on last login info
      final UserData ghostUser = UserData(
        userId: int.tryParse(lastInfo['userId'] ?? '0') ?? 0,
        name: "", 
        email: "",
        role: lastInfo['role']!,
        purok: lastInfo['purok'],
      );

      if (_isRelevant(data, ghostUser)) {
        showNotification(
          id: event.snapshot.key.hashCode,
          title: data['title'] ?? 'System Alert',
          body: data['message'] ?? '',
          type: (data['type'] ?? '').toString(),
        );
      }
    });
  }

  static void stopListening() {
    _dbSubscription?.cancel();
    _dbSubscription = null;
  }

  static bool _isRelevant(Map val, UserData user) {
    final String type = (val['type'] ?? '').toString();
    final String targetRole = (val['targetRole'] ?? '').toString();
    final String targetPurok = (val['purok'] ?? val['area'] ?? '').toString();
    final String residentId = (val['resident_id'] ?? val['targetUserId'] ?? '').toString();

    if (user.role == 'admin') {
      if (targetRole == 'admin') return true;
      if (['DRIVER_ISSUE', 'RESIDENT_COMPLAINT', 'REGISTRATION', 'NEW_REGISTRATION', 'TRUCK_ISSUE'].contains(type)) {
        return true;
      }
    } else if (user.role == 'resident') {
      if (residentId == user.userId.toString()) return true;
      if (type == 'TRUCK_PROXIMITY' && (targetPurok == '' || targetPurok == user.purok)) return true;
      if (type == 'COMPLAINT_RESOLVED' && residentId == user.userId.toString()) return true;
    } else if (user.role == 'driver') {
       if (targetRole == 'driver' || targetRole == 'all') return true;
       // Add other driver specific filters if needed
    }
    
    return false;
  }

  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? type,
    String? payload,
  }) async {
    // 1. Check if app notifications are enabled in settings
    bool enabled = await SessionManager.isAppNotificationsEnabled();
    if (!enabled) return;

    // 2. Double check system-level permission to prevent "phantom" calls
    if (!kIsWeb) {
      PermissionStatus status = await Permission.notification.status;
      if (!status.isGranted) {
        // If system permission was revoked externally, sync our local flag
        await SessionManager.setAppNotificationsEnabled(false);
        return;
      }
    }

    // Define style based on type
    Color notificationColor = const Color(0xFF00897B); // Default Teal
    String channelId = 'garbage_tracker_general';
    String channelName = 'General Alerts';

    if (type != null) {
      if (type.contains('ISSUE') || type.contains('COMPLAINT')) {
        notificationColor = const Color(0xFFE53935); // Red for issues
        channelId = 'garbage_tracker_issues';
        channelName = 'System Issues';
      } else if (type == 'TRUCK_PROXIMITY') {
        notificationColor = const Color(0xFFFB8C00); // Orange for proximity
        channelId = 'garbage_tracker_tracking';
        channelName = 'Tracking Alerts';
      } else if (type.contains('REGISTRATION')) {
        notificationColor = const Color(0xFF1E88E5); // Blue for users
        channelId = 'garbage_tracker_users';
        channelName = 'User Alerts';
      }
    }

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'Notifications for $channelName',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      color: notificationColor,
      ledColor: notificationColor,
      ledOnMs: 1000,
      ledOffMs: 500,
      enableLights: true,
      colorized: true,
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: channelName,
      ),
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(id, title, body, platformDetails, payload: payload);
  }
}
