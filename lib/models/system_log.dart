class SystemLog {
  final String id;
  final String type;
  final String message;
  final int timestamp;
  final String details;
  final String adminName;
  final String date;

  SystemLog({
    this.id = '',
    this.type = '',
    this.message = '',
    this.timestamp = 0,
    this.details = '',
    this.adminName = '',
    this.date = '',
  });

  factory SystemLog.fromJson(Map<String, dynamic> json) {
    return SystemLog(
      id: json['id'] ?? '',
      type: json['type'] ?? '',
      message: json['message'] ?? '',
      timestamp: json['timestamp'] ?? 0,
      details: json['details'] ?? '',
      adminName: json['adminName'] ?? '',
      date: json['date'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'message': message,
      'timestamp': timestamp,
      'details': details,
      'adminName': adminName,
      'date': date,
    };
  }
}
