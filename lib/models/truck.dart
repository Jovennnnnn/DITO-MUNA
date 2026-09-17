class TruckLocation {
  final int id;
  final int driverId;
  final String truckId;
  final double latitude;
  final double longitude;
  final double speed;
  final String status;
  final bool isFull;
  final String? plateNumber;
  final String? driverName;
  final String updatedAt;

  TruckLocation({
    required this.id,
    required this.driverId,
    required this.truckId,
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.status,
    required this.isFull,
    this.plateNumber,
    this.driverName,
    required this.updatedAt,
  });

  factory TruckLocation.fromJson(Map<String, dynamic> json) {
    return TruckLocation(
      id: json['id'] ?? 0,
      driverId: json['driverId'] ?? 0,
      truckId: json['truckId'] ?? '',
      latitude: (json['latitude'] ?? 0.0).toDouble(),
      longitude: (json['longitude'] ?? 0.0).toDouble(),
      speed: (json['speed'] ?? 0.0).toDouble(),
      status: json['status'] ?? 'offline',
      isFull: json['isFull'] ?? false,
      plateNumber: json['plateNumber'],
      driverName: json['driverName'],
      updatedAt: json['updatedAt']?.toString() ?? '',
    );
  }
}
