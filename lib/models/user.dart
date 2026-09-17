class UserData {
  final int userId;
  final String username;
  final String name;
  final String email;
  final String role;
  final String? phone;
  final String? purok;
  final String? completeAddress;
  final String? licenseNumber;
  final String? preferredTruck;
  final String? profilePicture;
  final int isArchived;
  final String? createdAt;

  UserData({
    this.userId = 0,
    this.username = '',
    this.name = '',
    this.email = '',
    this.role = '',
    this.phone,
    this.purok,
    this.completeAddress,
    this.licenseNumber,
    this.preferredTruck,
    this.profilePicture,
    this.isArchived = 0,
    this.createdAt,
  });

  factory UserData.fromJson(Map<String, dynamic> json) {
    return UserData(
      userId: int.tryParse(json['user_id'].toString()) ?? 0,
      username: json['username']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      phone: json['phone']?.toString(),
      purok: json['purok']?.toString(),
      completeAddress: json['complete_address']?.toString(),
      licenseNumber: json['license_number']?.toString(),
      preferredTruck: json['preferred_truck']?.toString(),
      profilePicture: json['profile_picture']?.toString(),
      isArchived: int.tryParse(json['is_archived'].toString()) ?? 0,
      createdAt: json['created_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'username': username,
      'name': name,
      'email': email,
      'role': role,
      'phone': phone,
      'purok': purok,
      'complete_address': completeAddress,
      'license_number': licenseNumber,
      'preferred_truck': preferredTruck,
      'profile_picture': profilePicture,
      'is_archived': isArchived,
      'created_at': createdAt,
    };
  }

  String? get profilePictureUrl {
    if (profilePicture == null || profilePicture!.isEmpty) return null;
    
    // If it's already a full URL, just return it.
    if (profilePicture!.startsWith('http')) {
      return profilePicture;
    }
    
    // Fallback: build URL if database somehow has relative path
    return "https://indigo-bear-885857.hostingersite.com/backend/$profilePicture";
  }

  UserData copyWith({
    int? userId,
    String? username,
    String? name,
    String? email,
    String? role,
    String? phone,
    String? purok,
    String? completeAddress,
    String? licenseNumber,
    String? preferredTruck,
    String? profilePicture,
    int? isArchived,
    String? createdAt,
  }) {
    return UserData(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      phone: phone ?? this.phone,
      purok: purok ?? this.purok,
      completeAddress: completeAddress ?? this.completeAddress,
      licenseNumber: licenseNumber ?? this.licenseNumber,
      preferredTruck: preferredTruck ?? this.preferredTruck,
      profilePicture: profilePicture ?? this.profilePicture,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
