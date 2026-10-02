import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

class GeofenceService {
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  
  // Radius in meters to trigger notification
  final double alertRadius = 300.0; 
  // Radius in meters to mark as "DONE" (slightly larger to avoid flickering)
  final double exitRadius = 400.0; 

  void startMonitoring(String truckId) {
    _database.ref('truck_locations/$truckId').onValue.listen((event) async {
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        final double truckLat = (data['latitude'] ?? 0.0).toDouble();
        final double truckLng = (data['longitude'] ?? 0.0).toDouble();
        
        _checkPuroks(truckId, truckLat, truckLng);
      }
    });
  }

  void _checkPuroks(String truckId, double truckLat, double truckLng) async {
    final puroksSnapshot = await _database.ref('puroks').get();
    if (!puroksSnapshot.exists) return;

    final puroks = puroksSnapshot.value as Map<dynamic, dynamic>;
    
    puroks.forEach((purokId, purokData) {
      final double pLat = (purokData['lat'] ?? 0.0).toDouble();
      final double pLng = (purokData['lng'] ?? 0.0).toDouble();
      final String status = purokData['status'] ?? 'pending';
      
      double distance = _calculateDistance(truckLat, truckLng, pLat, pLng);

      // LOGIC 1: ENTERING PUROK (Trigger Notification)
      if (distance <= alertRadius && status == 'pending') {
        _updatePurokStatus(purokId, 'collecting', truckId);
        _triggerNotification(purokId, "The garbage truck is approaching your area!");
      }
      
      // LOGIC 2: EXITING PUROK (Mark as DONE)
      if (distance > exitRadius && status == 'collecting') {
        _updatePurokStatus(purokId, 'done', truckId);
      }
    });
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    var c = cos;
    var a = 0.5 - c((lat2 - lat1) * p)/2 + 
          c(lat1 * p) * c(lat2 * p) * 
          (1 - c((lon2 - lon1) * p))/2;
    return 12742 * asin(sqrt(a)) * 1000; // Result in meters
  }

  Future<void> _updatePurokStatus(String purokId, String status, String truckId) async {
    await _database.ref('puroks/$purokId').update({
      'status': status,
      'last_truck': truckId,
      'updated_at': ServerValue.timestamp,
    });
    
    // Also update a general log for Admin (Aligned with integration_spec.md)
    final String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await _database.ref('collection_logs').push().set({
      'date': today,
      'zoneName': purokId, // Assuming purokId is the name, or fetch name
      'type': status == 'collecting' ? 'ENTRY' : 'EXIT',
      'duration_minutes': status == 'done' ? 15 : 0, // Mock duration for demo
      'distance_km': status == 'done' ? 2.5 : 0.0, // Mock distance for demo
      'timestamp': ServerValue.timestamp,
    });
  }

  void _triggerNotification(String purokId, String message) async {
    // Write to Firebase notifications table
    await _database.ref('notifications').push().set({
      'type': 'COLLECTION_ALERT',
      'title': 'Garbage Truck Alert',
      'message': message,
      'purok': purokId,
      'timestamp': ServerValue.timestamp,
      'isRead': false,
    });
  }
}
