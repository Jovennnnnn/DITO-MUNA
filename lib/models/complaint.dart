class Complaint {
  final int id;
  final String residentId;
  final String category;
  final String description;
  final String status;
  final String? adminResponse;
  final String createdAt;
  final String? updatedAt;
  final String? fullName;
  final String? purok;

  Complaint({
    required this.id,
    required this.residentId,
    required this.category,
    required this.description,
    required this.status,
    this.adminResponse,
    required this.createdAt,
    this.updatedAt,
    this.fullName,
    this.purok,
  });

  factory Complaint.fromJson(Map<String, dynamic> json) {
    return Complaint(
      id: json['id'] ?? 0,
      residentId: json['resident_id']?.toString() ?? '',
      category: json['category'] ?? '',
      description: json['description'] ?? '',
      status: json['status'] ?? 'PENDING',
      adminResponse: json['admin_response'],
      createdAt: json['created_at'] ?? '',
      updatedAt: json['updated_at'],
      fullName: json['full_name'],
      purok: json['purok'],
    );
  }
}
