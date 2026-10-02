import 'package:dio/dio.dart';
import 'api_client.dart';

class ApiService {
  final Dio _dio = ApiClient.instance;

  Future<Response> login(String username, String password) async {
    return await _dio.post('login.php', data: {
      'username_or_email': username,
      'password': password,
    });
  }

  Future<Response> register(Map<String, dynamic> data) async {
    return await _dio.post('register.php', data: data);
  }

  Future<Response> getUsers() async {
    return await _dio.get('get_users.php');
  }

  Future<Response> approveUser(int id, String role) async {
    return await _dio.post('approve_user.php', data: {
      'user_id': id,
      'role': role,
    });
  }

  Future<Response> rejectUser(int id, String role) async {
    return await _dio.post('reject_user.php', data: {
      'user_id': id,
      'role': role,
    });
  }

  Future<Response> getComplaints() async {
    return await _dio.get('get_complaints.php');
  }

  Future<Response> updateComplaint(int id, String status, String? response) async {
    return await _dio.post('update_complaint.php', data: FormData.fromMap({
      'complaint_id': id,
      'status': status,
      'admin_response': response,
    }));
  }

  Future<Response> fileComplaint(String residentId, String category, String description) async {
    return await _dio.post('file_complaint.php', data: FormData.fromMap({
      'resident_id': residentId,
      'category': category,
      'description': description,
    }));
  }

  Future<Response> getLocations() async {
    return await _dio.get('get_locations.php');
  }

  Future<Response> getAccessLogs() async {
    return await _dio.get('get_access_logs.php');
  }

  Future<Response> getAdminPermissions(int userId) async {
    return await _dio.get('get_admin_permissions.php', queryParameters: {'user_id': userId});
  }

  Future<Response> getUserSettings(int userId, String role) async {
    return await _dio.get('get_user_settings.php', queryParameters: {'user_id': userId, 'role': role});
  }

  Future<Response> updateUserSettings({
    required int userId,
    required String role,
    bool? emailNotifications,
    bool? appNotifications,
    bool? autoBackup,
  }) async {
    final Map<String, dynamic> data = {'user_id': userId, 'role': role};
    if (emailNotifications != null) data['email_notifications'] = emailNotifications;
    if (appNotifications != null) data['app_notifications'] = appNotifications;
    if (autoBackup != null) data['auto_backup'] = autoBackup;

    return await _dio.post('update_user_settings.php', data: data);
  }

  Future<Response> toggle2FA(int userId, bool enabled) async {
    return await _dio.post('toggle_2fa.php', data: {
      'user_id': userId,
      'enabled': enabled,
    });
  }

  Future<Response> updatePermissions(int userId, bool manageDb, bool viewAnalytics) async {
    return await _dio.post('update_permissions.php', data: {
      'user_id': userId,
      'can_manage_db': manageDb,
      'can_view_analytics': viewAnalytics,
    });
  }

  Future<Response> updateLocation({
    required int userId,
    required double latitude,
    required double longitude,
    required String truckId,
    required double speed,
    required String status,
    required bool isFull,
  }) async {
    return await _dio.post('update_location.php', data: FormData.fromMap({
      'user_id': userId,
      'latitude': latitude,
      'longitude': longitude,
      'truck_id': truckId,
      'speed': speed,
      'status': status,
      'is_full': isFull,
    }));
  }

  Future<Response> changePassword(int id, String role, String oldPass, String newPass) async {
    return await _dio.post('change_password.php', data: FormData.fromMap({
      'id': id,
      'role': role,
      'old_password': oldPass,
      'new_password': newPass,
    }));
  }

  Future<Response> verifyPassword(int id, String role, String password) async {
    return await _dio.post('verify_password.php', data: FormData.fromMap({
      'id': id,
      'role': role,
      'password': password,
    }));
  }

  Future<Response> forgotPassword(String email) async {
    return await _dio.post('forgot_password.php', data: {
      'email': email,
    });
  }

  Future<Response> verifyOTP(String email, String otp) async {
    return await _dio.post('verify_otp.php', data: {
      'email': email,
      'otp': otp,
    });
  }

  Future<Response> resetPassword(String email, String otp, String password) async {
    return await _dio.post('reset_password_final.php', data: {
      'email': email,
      'otp': otp,
      'password': password,
    });
  }

  // --- Backup & Data Management ---

  Future<Response> triggerBackup() async {
    return await _dio.post('trigger_backup.php');
  }

  Future<Response> getBackupHistory() async {
    return await _dio.get('get_backup_history.php');
  }

  Future<Response> deleteBackup(String filename) async {
    return await _dio.post('delete_backup.php', data: {'filename': filename});
  }

  Future<Response> exportData() async {
    return await _dio.get('export_report.php');
  }

  Future<Response> exportComplaintsReport() async {
    return await _dio.get('export_complaints_report.php');
  }

  Future<Response> deleteComplaint(int id) async {
    return await _dio.post('delete_complaint.php', data: {
      'complaint_id': id,
      'action': 'delete',
    });
  }

  Future<Response> bulkDeleteComplaints(List<int> ids) async {
    return await _dio.post('bulk_delete_complaints.php', data: {
      'complaint_ids': ids.join(','),
    });
  }

  Future<Response> archiveComplaint(int id, bool archive) async {
    return await _dio.post('archive_complaint.php', data: FormData.fromMap({
      'complaint_id': id,
      'is_archived': archive ? 1 : 0,
    }));
  }

  Future<Response> triggerAutoBackupChecker() async {
    return await _dio.get('auto_backup_checker.php');
  }

  Future<Response> triggerSchemaDebug() async {
    return await _dio.get('debug_schema.php');
  }

  Future<Response> notifyAdminIssue({
    required String driverName,
    required String issueType,
    required String description,
    String? adminEmail,
  }) async {
    final Map<String, dynamic> data = {
      'driver_name': driverName,
      'issue_type': issueType,
      'description': description,
    };
    if (adminEmail != null) data['admin_email'] = adminEmail;

    return await _dio.post('notify_admin_issue.php', data: FormData.fromMap(data));
  }

  // --- User Validation ---

  Future<Response> checkUsername(String username) async {
    return await _dio.post('check_username.php', data: FormData.fromMap({'username': username}));
  }

  Future<Response> checkEmail(String email) async {
    return await _dio.post('check_email.php', data: FormData.fromMap({'email': email}));
  }

  Future<Response> checkPhone(String phone) async {
    return await _dio.post('check_phone.php', data: FormData.fromMap({'phone': phone}));
  }

  Future<Response> checkTruck(String truckId) async {
    return await _dio.post('check_truck.php', data: FormData.fromMap({'truck_id': truckId}));
  }

  // --- Profile Management ---

  Future<Response> updateProfile({
    required int userId,
    required String role,
    required String name,
    required String phone,
    String? username,
    String? email,
    String? address,
    String? purok,
    String? preferredTruck,
    String? licenseNumber,
    String? profilePicture,
  }) async {
    final Map<String, dynamic> data = {
      'user_id': userId,
      'role': role,
      'name': name,
      'phone': phone,
    };
    if (username != null) data['username'] = username;
    if (email != null) data['email'] = email;
    if (address != null) data['address'] = address;
    if (purok != null) data['purok'] = purok;
    if (preferredTruck != null) data['preferred_truck'] = preferredTruck;
    if (licenseNumber != null) data['license_number'] = licenseNumber;
    if (profilePicture != null) data['profile_picture'] = profilePicture;

    return await _dio.post('update_user_profile.php', data: FormData.fromMap(data));
  }

  Future<Response> checkAvailability(String type, String value) async {
    return await _dio.get('check_availability.php', queryParameters: {'type': type, 'value': value});
  }

  Future<Response> uploadProfilePicture({
    required int userId,
    required String role,
    required String fileName,
    required List<int> imageBytes,
  }) async {
    return await _dio.post('upload_profile_picture.php', data: FormData.fromMap({
      'user_id': userId,
      'role': role,
      'profile_picture': MultipartFile.fromBytes(imageBytes, filename: fileName),
    }));
  }

  Future<Response> updateResidentData(Map<String, dynamic> data) async {
    return await _dio.post('update_resident_data.php', data: data);
  }

  Future<Response> deleteUser(int userId, String role) async {
    return await _dio.post('delete_user.php', data: {
      'user_id': userId,
      'role': role,
    });
  }
}
