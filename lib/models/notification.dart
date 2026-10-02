class SystemNotification {
  final String id;
  final String type;
  final String title;
  final String message;
  final int timestamp;
  final bool isRead;
  final String? relatedId;
  final int? userId;
  final String? status;
  final String? adminResponse;

  SystemNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.timestamp,
    required this.isRead,
    this.relatedId,
    this.userId,
    this.status,
    this.adminResponse,
  });

  factory SystemNotification.fromJson(Map<String, dynamic> json, String id) {
    return SystemNotification(
      id: id,
      type: json['type'] ?? '',
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      timestamp: json['timestamp'] ?? 0,
      isRead: json['isRead'] ?? false,
      relatedId: json['relatedId'],
      userId: json['userId'],
      status: json['status'],
      adminResponse: json['adminResponse'],
    );
  }
}
