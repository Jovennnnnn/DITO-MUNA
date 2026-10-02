import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/user.dart';

class ResolvedTruckAssignment {
  final int driverId;
  final String driverName;
  final String truckId;      // Current assigned truck ID, e.g., "GT-007"
  final String truckNumber;  // e.g., "GT-007"
  final String plateNumber;  // e.g., "ABC 1234"
  final String status;
  final double latitude;
  final double longitude;
  final int lastSeen;
  final bool isOnline;

  ResolvedTruckAssignment({
    required this.driverId,
    required this.driverName,
    required this.truckId,
    required this.truckNumber,
    required this.plateNumber,
    this.status = 'ACTIVE',
    this.latitude = 0.0,
    this.longitude = 0.0,
    this.lastSeen = 0,
    this.isOnline = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'driverId': driverId,
      'driver_id': driverId,
      'driverName': driverName,
      'driver_name': driverName,
      'truckId': truckId,
      'truck_id': truckId,
      'truckNumber': truckNumber,
      'plateNumber': plateNumber,
      'plate_number': plateNumber,
      'status': status,
      'latitude': latitude,
      'longitude': longitude,
      'lastSeen': lastSeen,
      'isOnline': isOnline,
    };
  }
}

class TruckAssignmentService {
  static final FirebaseDatabase _db = FirebaseDatabase.instance;

  /// Resolves current truck assignment for a logged-in driver.
  /// Driver -> current assigned truck ID -> truck metadata -> truck number -> plate number.
  static Future<ResolvedTruckAssignment?> resolveDriverTruckAssignment(UserData user) async {
    final String driverIdStr = user.userId.toString();
    final String driverName = user.name;
    String? preferredTruck = user.preferredTruck;

    debugPrint("[CURRENT TRUCK TRACE] driverId = $driverIdStr");
    debugPrint("[CURRENT TRUCK TRACE] users/$driverIdStr/preferred_truck = ${preferredTruck ?? 'NULL'}");

    // 1. Fallback to Firebase RTDB users/$driverId node if user object missing preferred_truck
    if (preferredTruck == null || preferredTruck.trim().isEmpty || preferredTruck == "Unknown" || preferredTruck == "None") {
      try {
        final userSnap = await _db.ref('users/$driverIdStr').get();
        if (userSnap.exists && userSnap.value != null) {
          final uMap = userSnap.value as Map;
          preferredTruck = uMap['preferred_truck']?.toString() ?? uMap['preferredTruck']?.toString();
          debugPrint("[CURRENT TRUCK TRACE] Recovered preferred_truck from Firebase users/$driverIdStr = $preferredTruck");
        }
      } catch (e) {
        debugPrint("[TruckAssignmentService] Error querying user node: $e");
      }
    }

    // 2. Fallback: check if truck_locations has an active node registered to this driver
    if (preferredTruck == null || preferredTruck.trim().isEmpty || preferredTruck == "Unknown" || preferredTruck == "None") {
      try {
        final locsSnap = await _db.ref('truck_locations').get();
        if (locsSnap.exists && locsSnap.value != null) {
          final Map locsMap = locsSnap.value as Map;
          locsMap.forEach((key, val) {
            if (val is Map) {
              final String valDriverId = (val['driver_id'] ?? val['driverId'] ?? '').toString();
              final String keyStr = key.toString().toUpperCase();
              if (valDriverId == driverIdStr && keyStr != "UNKNOWN" && keyStr != "NONE") {
                preferredTruck = keyStr;
                debugPrint("[CURRENT TRUCK TRACE] Recovered active assigned truck from truck_locations for driver $driverIdStr = $preferredTruck");
              }
            }
          });
        }
      } catch (e) {
        debugPrint("[TruckAssignmentService] Error querying truck_locations node: $e");
      }
    }

    debugPrint("[CURRENT TRUCK TRACE] resolvedTruckId = ${preferredTruck ?? 'NULL'}");

    if (preferredTruck == null || preferredTruck!.trim().isEmpty || preferredTruck == "Unknown" || preferredTruck == "None") {
      debugPrint("SOURCE DATA MISSING:");
      debugPrint("field = preferred_truck");
      debugPrint("location = users/$driverIdStr (or MySQL users.preferred_truck)");
      debugPrint("driver = $driverName");
      return null;
    }

    final String assignedTruckId = preferredTruck!.trim().toUpperCase();
    String plateNumber = '';
    String sourcePath = 'trucks/$assignedTruckId';
    bool metaExists = false;

    try {
      final truckMetaSnap = await _db.ref(sourcePath).get();
      if (truckMetaSnap.exists && truckMetaSnap.value != null) {
        metaExists = true;
        final Map metaData = truckMetaSnap.value as Map;
        plateNumber = (metaData['plateNumber'] ?? metaData['plate_number'] ?? metaData['plate'] ?? '').toString().trim();
      } else {
        // Fallback check on truck_locations node if metadata node missing
        final locSnap = await _db.ref('truck_locations/$assignedTruckId').get();
        if (locSnap.exists && locSnap.value != null) {
          final Map locData = locSnap.value as Map;
          plateNumber = (locData['plate_number'] ?? locData['plateNumber'] ?? '').toString().trim();
        }
      }
    } catch (e) {
      debugPrint("[TRUCK_RESOLUTION_FAILED] path: $sourcePath, error: $e");
    }

    debugPrint("[CURRENT TRUCK TRACE] trucks/$assignedTruckId exists = $metaExists");
    debugPrint("[CURRENT TRUCK TRACE] truckNumber = $assignedTruckId");
    debugPrint("[CURRENT TRUCK TRACE] plateNumber = ${plateNumber.isNotEmpty ? plateNumber : 'MISSING'}");
    debugPrint("[CURRENT TRUCK TRACE] liveLocationTruckId = $assignedTruckId");
    debugPrint("[CURRENT TRUCK TRACE] finalResolvedTruckId = $assignedTruckId");
    debugPrint("[CURRENT TRUCK TRACE] finalResolvedTruckNumber = $assignedTruckId");
    debugPrint("[CURRENT TRUCK TRACE] finalResolvedPlateNumber = ${plateNumber.isNotEmpty ? plateNumber : 'MISSING'}");

    return ResolvedTruckAssignment(
      driverId: user.userId,
      driverName: driverName,
      truckId: assignedTruckId,
      truckNumber: assignedTruckId,
      plateNumber: plateNumber,
      status: 'ACTIVE',
      isOnline: true,
    );
  }

  /// Resolves an active fleet truck node for Admin / Fleet Tracking views.
  static ResolvedTruckAssignment resolveFleetNode({
    required String nodeKey,
    required Map liveData,
    required Map<String, dynamic> trucksRegistry,
  }) {
    final int driverId = int.tryParse((liveData['driver_id'] ?? liveData['driverId'] ?? '').toString()) ?? 0;
    final String driverName = (liveData['driver_name'] ?? liveData['driverName'] ?? 'Driver').toString();
    final String truckId = (liveData['truck_id'] ?? liveData['truckId'] ?? nodeKey).toString().toUpperCase();

    final Map? registryMap = (trucksRegistry[truckId] ?? trucksRegistry[nodeKey]) as Map?;

    final String plateNumber = (liveData['plate_number'] ?? 
                                 liveData['plateNumber'] ?? 
                                 registryMap?['plateNumber'] ?? 
                                 registryMap?['plate_number'] ?? '').toString().trim();

    final String truckNumber = (registryMap?['truckNumber'] ?? 
                                registryMap?['truckId'] ?? 
                                truckId).toString().toUpperCase();

    final double lat = (liveData['latitude'] ?? liveData['lat'] ?? 0.0).toDouble();
    final double lng = (liveData['longitude'] ?? liveData['lng'] ?? 0.0).toDouble();
    final int lastSeen = (liveData['lastSeen'] is num) ? (liveData['lastSeen'] as num).toInt() : 0;
    final String status = (liveData['status'] ?? 'ACTIVE').toString().toUpperCase();
    final bool isOnline = liveData['isOnline'] == true;

    return ResolvedTruckAssignment(
      driverId: driverId,
      driverName: driverName,
      truckId: truckId,
      truckNumber: truckNumber,
      plateNumber: plateNumber,
      status: status,
      latitude: lat,
      longitude: lng,
      lastSeen: lastSeen,
      isOnline: isOnline,
    );
  }
}
