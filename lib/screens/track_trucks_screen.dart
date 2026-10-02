import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size, Visibility;
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:geolocator/geolocator.dart' as geo;
import '../utils/app_theme.dart';
import '../widgets/fade_slide_entrance.dart';
import '../utils/custom_notification.dart';
import '../utils/prediction_engine.dart';
import '../services/truck_assignment_service.dart';
import '../api/api_service.dart';

class TrackTrucksScreen extends StatefulWidget {
  final bool isEmbedded;
  final VoidCallback? onBack;
  const TrackTrucksScreen({super.key, this.isEmbedded = false, this.onBack});

  @override
  State<TrackTrucksScreen> createState() => _TrackTrucksScreenState();
}

class _TrackTrucksScreenState extends State<TrackTrucksScreen> with TickerProviderStateMixin {
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  MapboxMap? mapboxMap;
  List<Map<dynamic, dynamic>> _trucks = [];
  Map<String, dynamic> _allTrucksRegistry = {};
  
  Map<String, dynamic> _firebaseLocations = {};
  Map<String, dynamic> _phpLocations = {};
  
  String? _followedTruckId;
  Timer? _phpSyncTimer;
  final ApiService _apiService = ApiService();

  final Map<String, StreamSubscription> _sharedRouteSubscriptions = {};
  final Map<String, String> _truckPlates = {}; // Cache for plate numbers
  final Map<String, String> _driverCurrentTrucks = {}; // driverId -> truckId
  StreamSubscription? _trucksMetaSubscription;
  StreamSubscription? _usersSubscription;

  final Map<String, List<Map<dynamic, dynamic>>> _lastRoutePoints = {}; 
  final Set<String> _visiblePaths = {};
  final Map<String, Position?> _sessionStartPoints = {};

  bool _isFollowLocked = false;
  bool _isMapActive = false;
  bool _isFleetPanelVisible = true;
  bool _isScanning = true;
  final Position _balintawakCenter = Position(121.1620, 13.9565);

  // Animation for Refresh Button
  late AnimationController _refreshRotationController;
  bool _isRefreshing = false;

  void _handleManualRefresh() async {
    if (_isRefreshing) return;
    
    setState(() => _isRefreshing = true);
    _refreshRotationController.repeat();
    
    try {
      // 1. Refresh Base Data from Firebase (Force update)
      final trucksSnapshot = await _database.ref('trucks').get();
      if (trucksSnapshot.exists) {
        _allTrucksRegistry = Map<String, dynamic>.from(trucksSnapshot.value as Map);
      }
      
      final locationsSnapshot = await _database.ref('truck_locations').get();
      if (locationsSnapshot.exists && locationsSnapshot.value != null) {
        _firebaseLocations = Map<String, dynamic>.from(locationsSnapshot.value as Map);
      }
      
      final usersSnapshot = await _database.ref('users').get();
      if (usersSnapshot.exists) {
        final Map data = usersSnapshot.value as Map;
        final Map<String, String> currentAssignments = {};
        data.forEach((key, value) {
          if (value is Map && value['role'] == 'driver') {
            final String? truckId = value['preferred_truck']?.toString();
            if (truckId != null) currentAssignments[key.toString()] = truckId;
          }
        });
        _driverCurrentTrucks.clear();
        _driverCurrentTrucks.addAll(currentAssignments);
      }

      // Also trigger PHP location sync
      _syncPhpLocations();

      // 2. Reprocess merged data
      _processMergedTrucks();
      
      // 3. UI Feedback (Centered White Box)
      if (mounted) {
        showDialog(
          context: context,
          barrierColor: Colors.black.withValues(alpha: 0.1),
          barrierDismissible: false,
          builder: (context) {
            Future.delayed(const Duration(milliseconds: 1500), () {
              if (Navigator.canPop(context)) Navigator.pop(context);
            });
            return Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 15, offset: const Offset(0, 5))
                  ],
                ),
                child: const Material(
                  color: Colors.transparent,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                      SizedBox(width: 12),
                      Text("Fleet data refreshed", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF1A1A1A))),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      }
    } catch (e) {
      debugPrint("Refresh error: $e");
    } finally {
      if (mounted) {
        _refreshRotationController.stop();
        _refreshRotationController.reset();
        setState(() => _isRefreshing = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _listenToTrucks();
    _listenToTruckMeta();
    _listenToUsers();
    _syncPhpLocations();
    _phpSyncTimer = Timer.periodic(const Duration(seconds: 3), (_) => _syncPhpLocations());
    _refreshRotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _isScanning = false);
    });
  }

  void _syncPhpLocations() async {
    try {
      final response = await _apiService.getLocations();
      final dynamic rawData = response.data;
      List? phpLocations;
      if (rawData is Map) {
        phpLocations = (rawData['locations'] ?? rawData['data']) as List?;
      } else if (rawData is List) {
        phpLocations = rawData;
      }

      if (phpLocations != null && mounted) {
        final Map<String, dynamic> phpMap = {};
        final int now = DateTime.now().millisecondsSinceEpoch;

        for (var loc in phpLocations) {
          if (loc == null || loc is! Map) continue;
          final String tid = (loc['truck_id'] ?? loc['truckId'] ?? loc['id'] ?? '').toString().toUpperCase().trim();
          final String driverName = (loc['driver_name'] ?? loc['driverName'] ?? loc['full_name'] ?? '').toString();
          
          if (driverName.toLowerCase().contains("john driver")) continue;

          final double lat = double.tryParse(loc['latitude']?.toString() ?? loc['lat']?.toString() ?? '0') ?? 0.0;
          final double lng = double.tryParse(loc['longitude']?.toString() ?? loc['lng']?.toString() ?? '0') ?? 0.0;
          final String status = (loc['status'] ?? 'ACTIVE').toString().toUpperCase();
          
          final dynamic rawTime = loc['updated_at'] ?? loc['updatedAt'] ?? loc['lastSeen'] ?? loc['last_seen'];
          int timestampMs = 0;
          if (rawTime is num) {
            timestampMs = rawTime.toInt();
          } else if (rawTime != null) {
            String str = rawTime.toString().trim();
            if (str.contains(' ')) str = str.replaceAll(' ', 'T');
            final parsed = DateTime.tryParse(str);
            if (parsed != null) timestampMs = parsed.millisecondsSinceEpoch;
          }

          final dynamic secondsAgoRaw = loc['seconds_ago'] ?? loc['secondsAgo'];
          final int secondsAgo = secondsAgoRaw is num ? secondsAgoRaw.toInt() : (timestampMs > 0 ? ((now - timestampMs) / 1000).abs().toInt() : 0);
          final bool isFresh = secondsAgo <= 60; // 60s freshness filter

          if (tid.isNotEmpty && lat != 0.0 && lng != 0.0 && status != 'OFFLINE' && isFresh) {
            phpMap[tid] = {
              'truck_id': tid,
              'driver_id': loc['driver_id'] ?? loc['driverId'] ?? loc['user_id'],
              'driver_name': driverName.isEmpty ? 'Driver' : driverName,
              'plate_number': loc['plate_number'] ?? loc['plateNumber'] ?? 'N/A',
              'latitude': lat,
              'longitude': lng,
              'lat': lat,
              'lng': lng,
              'speed': double.tryParse(loc['speed']?.toString() ?? '0') ?? 0.0,
              'status': status,
              'isOnline': true,
              'lastSeen': timestampMs > 0 ? timestampMs : now,
              'updatedAt': '$secondsAgo secs ago',
              'seconds_ago': secondsAgo,
            };
          }
        }
        _phpLocations = phpMap;
        _processMergedTrucks();
      }
    } catch (e) {
      debugPrint("PHP locations sync error: $e");
    }
  }

  @override
  void dispose() {
    for (final sub in _sharedRouteSubscriptions.values) {
      sub.cancel();
    }
    _trucksMetaSubscription?.cancel();
    _usersSubscription?.cancel();
    _phpSyncTimer?.cancel();
    _refreshRotationController.dispose();
    super.dispose();
  }

  void _listenToTruckMeta() {
    _trucksMetaSubscription?.cancel();
    _trucksMetaSubscription = _database.ref('trucks').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map data = event.snapshot.value as Map;
        final Map<String, String> newPlates = {};
        data.forEach((key, value) {
          if (value is Map && value['plateNumber'] != null) {
            newPlates[key.toString().toUpperCase()] = value['plateNumber'].toString();
          }
        });
        if (mounted) setState(() => _truckPlates.addAll(newPlates));
      }
    });
  }

  void _listenToUsers() {
    _usersSubscription?.cancel();
    _usersSubscription = _database.ref('users').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map data = event.snapshot.value as Map;
        final Map<String, String> currentAssignments = {};
        data.forEach((key, value) {
          if (value is Map && value['role'] == 'driver') {
            final String? truckId = value['preferred_truck']?.toString();
            if (truckId != null) currentAssignments[key.toString()] = truckId;
          }
        });
        if (mounted) {
          setState(() {
            _driverCurrentTrucks.clear();
            _driverCurrentTrucks.addAll(currentAssignments);
          });
        }
      }
    });
  }

  void _listenToTrucks() {
    _database.ref('trucks').onValue.listen((event) {
      if (event.snapshot.exists) {
        _allTrucksRegistry = Map<String, dynamic>.from(event.snapshot.value as Map);
        _processMergedTrucks();
      }
    });

    _database.ref('truck_locations').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        _firebaseLocations = Map<String, dynamic>.from(event.snapshot.value as Map);
      } else {
        _firebaseLocations = {};
      }
      _processMergedTrucks();
    });
  }

  void _processMergedTrucks() {
    final List<Map<dynamic, dynamic>> mergedList = [];
    final Set<String> seenTrucks = {};
    final Set<String> seenDrivers = {};
    final int now = DateTime.now().millisecondsSinceEpoch;

    // STEP 1: Process Firebase RTDB Live Locations FIRST (Authoritative real-time stream used by Driver Portal)
    final Map<String, Map<String, dynamic>> canonicalLiveMap = {};

    _firebaseLocations.forEach((rawKey, value) {
      if (value == null || value is! Map) return;
      final Map liveData = Map<String, dynamic>.from(value);
      
      String tid = (liveData['truck_id'] ?? liveData['truckId'] ?? rawKey).toString().toUpperCase().trim();
      if (tid == "UNKNOWN" || tid == "N/A" || tid.isEmpty) {
        tid = rawKey.toString().toUpperCase().trim();
      }

      canonicalLiveMap[tid] = {
        ...liveData,
        'truck_id': tid,
        '_source': 'firebase_rtdb',
      };
    });

    // STEP 2: Only add PHP locations if NOT already present in Firebase RTDB
    _phpLocations.forEach((rawKey, value) {
      if (value == null || value is! Map) return;
      final Map liveData = Map<String, dynamic>.from(value);
      
      String tid = (liveData['truck_id'] ?? liveData['truckId'] ?? rawKey).toString().toUpperCase().trim();
      if (tid == "UNKNOWN" || tid == "N/A" || tid.isEmpty) {
        tid = rawKey.toString().toUpperCase().trim();
      }

      if (!canonicalLiveMap.containsKey(tid)) {
        canonicalLiveMap[tid] = {
          ...liveData,
          'truck_id': tid,
          '_source': 'php_mysql',
        };
      }
    });

    canonicalLiveMap.forEach((tid, liveData) {
      final String status = (liveData['status'] ?? 'ACTIVE').toString().toUpperCase();
      
      final String driverId = (liveData['driver_id'] ?? liveData['driverId'] ?? liveData['user_id'] ?? '').toString().toLowerCase();
      final String driverName = (liveData['driver_name'] ?? liveData['driverName'] ?? 'Driver').toString();
      final String driverNameLower = driverName.toLowerCase();

      // Exclude placeholder driver "john driver"
      if (driverNameLower.contains("john driver")) return;

      // Extract coordinates with strict double precision
      final double lat = double.tryParse(liveData['latitude']?.toString() ?? liveData['lat']?.toString() ?? liveData['last_lat']?.toString() ?? '') ?? 0.0;
      final double lng = double.tryParse(liveData['longitude']?.toString() ?? liveData['lng']?.toString() ?? liveData['last_lng']?.toString() ?? '') ?? 0.0;
      
      // Strict validity check: Lat must be between -90 and 90, Lng between -180 and 180, and non-zero
      final bool hasValidCoords = (lat != 0.0 && lng != 0.0 && lat.abs() <= 90.0 && lng.abs() <= 180.0);

      // Extract timestamp to verify 60-second freshness
      final dynamic lastSeenRaw = liveData['lastSeen'] ?? liveData['last_seen'] ?? liveData['timestamp'];
      int lastSeenMs = 0;
      if (lastSeenRaw is num) {
        lastSeenMs = lastSeenRaw.toInt();
      } else if (lastSeenRaw != null) {
        String str = lastSeenRaw.toString().trim();
        if (str.contains(' ')) str = str.replaceAll(' ', 'T');
        final parsed = DateTime.tryParse(str);
        if (parsed != null) lastSeenMs = parsed.millisecondsSinceEpoch;
      }

      if (lastSeenMs == 0) {
        final dynamic updatedRaw = liveData['updatedAt'] ?? liveData['updated_at'];
        if (updatedRaw != null) {
          String str = updatedRaw.toString().trim();
          if (str.contains(' ')) str = str.replaceAll(' ', 'T');
          final parsed = DateTime.tryParse(str);
          if (parsed != null) lastSeenMs = parsed.millisecondsSinceEpoch;
        }
      }

      int secondsAgo = -1;
      final dynamic secondsAgoRaw = liveData['seconds_ago'] ?? liveData['secondsAgo'];
      if (secondsAgoRaw is num) {
        secondsAgo = secondsAgoRaw.toInt();
      } else if (lastSeenMs > 0) {
        secondsAgo = ((now - lastSeenMs) / 1000).abs().toInt();
      }

      // Freshness filter: MUST have location update within last 60 seconds (secondsAgo <= 60)
      final bool isFresh = (secondsAgo >= 0) && (secondsAgo <= 60);
      final bool isOnlineFlag = liveData['isOnline'] != false;
      final bool isGenuinelyOnline = hasValidCoords && status != 'OFFLINE' && isOnlineFlag && isFresh;

      // STRICT DEDUPLICATION: one card = one driver_id (and one truck_id)
      final String uniqueDriverKey = driverId.isNotEmpty ? driverId : driverNameLower;

      if (isGenuinelyOnline && !seenTrucks.contains(tid) && !seenDrivers.contains(uniqueDriverKey)) {
        seenTrucks.add(tid);
        seenDrivers.add(uniqueDriverKey);

        final resolved = TruckAssignmentService.resolveFleetNode(
          nodeKey: tid,
          liveData: liveData,
          trucksRegistry: _allTrucksRegistry,
        );

        mergedList.add({
          ...Map<String, dynamic>.from(_allTrucksRegistry[tid] as Map? ?? {}),
          ...Map<String, dynamic>.from(liveData),
          'truck_id': resolved.truckId,
          'truckNumber': resolved.truckNumber,
          'plate_number': resolved.plateNumber,
          'driver_name': resolved.driverName.isNotEmpty ? resolved.driverName : driverName,
          'latitude': lat,
          'longitude': lng,
          'lat': lat,
          'lng': lng,
          'status': status,
          'isOnline': true,
        });
      }
    });

    if (mounted) {
      setState(() => _trucks = mergedList);
      _updateTruckMarkers();

      // Real-time camera follow for targeted driver or active driver
      if (_followedTruckId != null) {
        final followed = mergedList.firstWhere(
          (t) => (t['truck_id'] ?? t['truckId'] ?? '').toString().toUpperCase() == _followedTruckId!.toUpperCase(),
          orElse: () => {},
        );
        if (followed.isNotEmpty) {
          final double lat = (followed['latitude'] ?? followed['lat'] ?? 0.0).toDouble();
          final double lng = (followed['longitude'] ?? followed['lng'] ?? 0.0).toDouble();
          if (lat != 0.0 && lng != 0.0) {
            mapboxMap?.setCamera(CameraOptions(center: Point(coordinates: Position(lng, lat)), zoom: 17.5));
          }
        }
      }
      
      final activeTruckIds = mergedList.map((t) => (t['truck_id'] ?? '').toString()).toSet();
      final trucksToClear = _sharedRouteSubscriptions.keys.where((id) => !activeTruckIds.contains(id)).toList();
      for (var id in trucksToClear) {
        _sharedRouteSubscriptions[id]?.cancel();
        _sharedRouteSubscriptions.remove(id);
        _clearSharedRoute(id);
      }
      for (var t in mergedList) {
        final String tid = (t['truck_id'] ?? '').toString();
        final String? sid = t['current_session']?.toString();
        if (sid != null && sid.isNotEmpty) {
          if (!_sharedRouteSubscriptions.containsKey(tid)) _setupRouteSubscription(tid, sid);
        } else {
          _sharedRouteSubscriptions[tid]?.cancel();
          _sharedRouteSubscriptions.remove(tid);
          _clearSharedRoute(tid);
        }
      }
    }
  }

  void _setupRouteSubscription(String truckId, String sessionId) {
    _sharedRouteSubscriptions[truckId]?.cancel();
    _sharedRouteSubscriptions[truckId] = _database.ref('driver_routes/$sessionId/route').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map data = event.snapshot.value as Map;
        final List<Map<dynamic, dynamic>> points = [];
        data.forEach((key, value) => points.add(Map<dynamic, dynamic>.from(value as Map)));
        points.sort((a, b) => (a['timestamp'] ?? 0).compareTo(b['timestamp'] ?? 0));
        _lastRoutePoints[truckId] = points;
        if (_visiblePaths.contains(truckId)) _updateSharedRoutePolyline(truckId, points);
      }
    });

    _database.ref('driver_routes/$sessionId').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map data = event.snapshot.value as Map;
        if (data['start_lat'] != null && data['start_lng'] != null) {
          if (mounted) setState(() => _sessionStartPoints[truckId] = Position(data['start_lng'], data['start_lat']));
        }
      }
    });
  }

  void _clearSharedRoute(String truckId) async {
    if (mapboxMap == null) return;
    try {
      final style = mapboxMap!.style;
      final String sourceId = "route-source-$truckId";
      if (await style.styleSourceExists(sourceId)) {
        await style.setStyleSourceProperty(sourceId, "data", jsonEncode({"type": "FeatureCollection", "features": []}));
      }
    } catch (_) {}
    if (mounted) setState(() => _sessionStartPoints.remove(truckId));
  }

  void _updateSharedRoutePolyline(String truckId, List<Map<dynamic, dynamic>> points) async {
    if (mapboxMap == null || points.length < 2) return;
    points.sort((a, b) => ((a['timestamp'] ?? 0) as num).compareTo((b['timestamp'] ?? 0) as num));

    final String sourceId = "route-source-$truckId";
    final List<Map<String, dynamic>> features = [];

    final List<Map<dynamic, dynamic>> validPoints = [];
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final double lat = (p['latitude'] ?? p['lat'] ?? 0.0).toDouble();
      final double lng = (p['longitude'] ?? p['lng'] ?? 0.0).toDouble();

      if (lat < -90 || lat > 90 || lng < -180 || lng > 180 || (lat == 0 && lng == 0)) {
        continue;
      }

      if (validPoints.isNotEmpty) {
        final prev = validPoints.last;
        final double prevLat = (prev['latitude'] ?? prev['lat'] ?? 0.0).toDouble();
        final double prevLng = (prev['longitude'] ?? prev['lng'] ?? 0.0).toDouble();
        final double d = geo.Geolocator.distanceBetween(prevLat, prevLng, lat, lng);
        
        if (d < 0.5) continue;
      }

      validPoints.add(p);
    }

    if (validPoints.length >= 2) {
      List<List<double>> currentSegmentCoords = [];
      String currentColor = (validPoints[1]['color'] ?? 'GREEN').toString().toUpperCase();

      double firstLat = (validPoints[0]['latitude'] ?? validPoints[0]['lat'] ?? 0.0).toDouble();
      double firstLng = (validPoints[0]['longitude'] ?? validPoints[0]['lng'] ?? 0.0).toDouble();
      currentSegmentCoords.add([firstLng, firstLat]);

      for (int i = 1; i < validPoints.length; i++) {
        final curr = validPoints[i];
        final double currLat = (curr['latitude'] ?? curr['lat'] ?? 0.0).toDouble();
        final double currLng = (curr['longitude'] ?? curr['lng'] ?? 0.0).toDouble();
        String color = (curr['color'] ?? 'GREEN').toString().toUpperCase();

        if (color == currentColor) {
          currentSegmentCoords.add([currLng, currLat]);
        } else {
          currentSegmentCoords.add([currLng, currLat]);
          if (currentSegmentCoords.length >= 2) {
            features.add({
              "type": "Feature",
              "geometry": {
                "type": "LineString",
                "coordinates": List<List<double>>.from(currentSegmentCoords)
              },
              "properties": {"color": currentColor}
            });
          }
          currentColor = color;
          currentSegmentCoords = [[currLng, currLat]];
        }
      }

      if (currentSegmentCoords.length >= 2) {
        features.add({
          "type": "Feature",
          "geometry": {
            "type": "LineString",
            "coordinates": List<List<double>>.from(currentSegmentCoords)
          },
          "properties": {"color": currentColor}
        });
      }
    }

    final featureCollection = {"type": "FeatureCollection", "features": features};
    try {
      final style = mapboxMap!.style;
      if (!(await style.styleSourceExists(sourceId))) {
        await style.addSource(GeoJsonSource(id: sourceId, data: jsonEncode(featureCollection)));
        await style.addLayer(LineLayer(id: "route-layer-$truckId", sourceId: sourceId, lineColor: Colors.green.toARGB32(), lineWidth: 8.0, lineOpacity: 0.9, lineCap: LineCap.ROUND, lineJoin: LineJoin.ROUND));
        await style.setStyleLayerProperty("route-layer-$truckId", "line-color", ["match", ["get", "color"], "GREEN", "#00FF00", "YELLOW", "#FFFF00", "PINK", "#FF1493", "BLACK", "#000000", "BLUE", "#0000FF", "#00FF00"]);
      } else { await style.setStyleSourceProperty(sourceId, "data", jsonEncode(featureCollection)); }
    } catch (_) {}
  }

  double _getResponsiveZoom(BuildContext context) {
    final double width = MediaQuery.of(context).size.width;
    if (width < 600) {
      return 12.8;
    } else if (width < 1024) {
      return 13.4;
    } else {
      return 13.8;
    }
  }

  void _recenterToBalintawak() {
    final double responsiveZoom = _getResponsiveZoom(context);
    mapboxMap?.setCamera(CameraOptions(center: Point(coordinates: _balintawakCenter), zoom: responsiveZoom));
  }
  void _focusOnTruck(Map<dynamic, dynamic> truck, {double zoom = 17.5}) {
    final double lat = (truck['latitude'] ?? truck['lat'] ?? 0.0).toDouble();
    final double lng = (truck['longitude'] ?? truck['lng'] ?? 0.0).toDouble();
    if (lat == 0 || lng == 0) return;
    mapboxMap?.setCamera(CameraOptions(center: Point(coordinates: Position(lng, lat)), zoom: zoom));
  }

  void _onMapCreated(MapboxMap map) {
    mapboxMap = map;
  }

  void _onStyleLoaded(dynamic data) async {
    try {
      await mapboxMap?.location.updateSettings(LocationComponentSettings(enabled: false, pulsingEnabled: false));
      await mapboxMap?.compass.updateSettings(CompassSettings(position: OrnamentPosition.TOP_LEFT, marginTop: 200.0, marginLeft: 20.0));
    } catch (_) {}
    _updateTruckMarkers();
    
    // Always start initial map view centered on Barangay Balintawak, Lipa City, Batangas
    _recenterToBalintawak();
  }

  bool _isUpdatingMarkers = false;
  Future<void> _updateTruckMarkers() async {
    if (mapboxMap == null || _isUpdatingMarkers) return;
    _isUpdatingMarkers = true;

    try {
      final style = mapboxMap!.style;
      final List<Map<String, dynamic>> driverFeatures = [];

      for (var truck in _trucks) {
        final double lat = (truck['latitude'] ?? truck['lat'] ?? 0.0).toDouble();
        final double lng = (truck['longitude'] ?? truck['lng'] ?? 0.0).toDouble();
        if (lat == 0.0 || lng == 0.0) continue;

        final String tid = (truck['truck_id'] ?? truck['truckId'] ?? 'GT-001').toString().toUpperCase();
        final String driverName = (truck['driver_name'] ?? truck['driverName'] ?? 'Driver').toString();
        final String status = (truck['status'] ?? "ACTIVE").toString().toUpperCase();

        print("[MARKER DEBUG] Driver: $driverName ($tid)");
        print("[MARKER DEBUG] Latitude from fleet data: $lat");
        print("[MARKER DEBUG] Longitude from fleet data: $lng");
        print("[MARKER DEBUG] Mapbox marker coordinate: [$lng, $lat]");

        debugPrint("[MARKER DEBUG] Driver: $driverName ($tid)");
        debugPrint("[MARKER DEBUG] Latitude from fleet data: $lat");
        debugPrint("[MARKER DEBUG] Longitude from fleet data: $lng");
        debugPrint("[MARKER DEBUG] Mapbox marker coordinate: [$lng, $lat]");

        final String markerLabel = "$driverName • $tid";

        driverFeatures.add({
          "type": "Feature",
          "geometry": {
            "type": "Point",
            "coordinates": [lng, lat]
          },
          "properties": {
            "name": driverName,
            "truck_id": tid,
            "label": markerLabel,
            "status": status,
          }
        });
      }

      final String sourceId = "admin-drivers-source";
      final String geoJsonData = jsonEncode({
        "type": "FeatureCollection",
        "features": driverFeatures
      });

      bool sourceExists = await style.styleSourceExists(sourceId);
      if (!sourceExists) {
        await style.addSource(GeoJsonSource(id: sourceId, data: geoJsonData));

        // 1. Outer Pulsing Halo Ring (EXACT MATCH TO DRIVER PORTAL)
        if (!(await style.styleLayerExists("admin-drivers-halo"))) {
          await style.addLayer(CircleLayer(
            id: "admin-drivers-halo",
            sourceId: sourceId,
            circleRadius: 18.0,
            circleOpacity: 0.3,
            circleStrokeWidth: 2.0,
            circleSortKey: 3100.0,
          ));
        }

        // 2. Solid Inner Green Circle (EXACT MATCH TO DRIVER PORTAL)
        if (!(await style.styleLayerExists("admin-drivers-circle"))) {
          await style.addLayer(CircleLayer(
            id: "admin-drivers-circle",
            sourceId: sourceId,
            circleRadius: 8.0,
            circleColor: Colors.green.toARGB32(),
            circleStrokeWidth: 3.0,
            circleStrokeColor: Colors.white.toARGB32(),
            circleSortKey: 3200.0,
          ));
        }

        // 3. Driver Name & Truck ID Label (EXACT MATCH TO DRIVER PORTAL)
        if (!(await style.styleLayerExists("admin-drivers-label"))) {
          await style.addLayer(SymbolLayer(
            id: "admin-drivers-label",
            sourceId: sourceId,
            textField: "{label}",
            textSize: 14.0,
            textColor: Colors.green.toARGB32(),
            textHaloColor: Colors.white.toARGB32(),
            textHaloWidth: 2.0,
            textAnchor: TextAnchor.BOTTOM,
            textOffset: [0, -1.5],
            symbolSortKey: 3300.0,
            textAllowOverlap: true,
          ));
        }

        final statusColorExpression = [
          "match", ["get", "status"],
          "IDLE", "#FFFF00",
          "FULL", "#FF1493",
          "FINISHED", "#000000",
          "#00FF00"
        ];

        await style.setStyleLayerProperty("admin-drivers-halo", "circle-color", statusColorExpression);
        await style.setStyleLayerProperty("admin-drivers-halo", "circle-stroke-color", statusColorExpression);
      } else {
        await style.setStyleSourceProperty(sourceId, "data", geoJsonData);
      }
    } catch (e) {
      debugPrint("[MAPBOX RENDER ERROR] $e");
    } finally {
      _isUpdatingMarkers = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final bool isDesktop = constraints.maxWidth >= 900;
      return FadeSlideEntrance(
        child: Scaffold(
          backgroundColor: Colors.white, 
          body: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(), 
        ),
      );
    });
  }

  Widget _buildDesktopLayout() {
    return Container(
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(40),
        boxShadow: AppTheme.balancedDeepShadow,
        border: Border.all(color: const Color(0xFFE0E0E0), width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: MapWidget(
              gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
              },
              onMapCreated: _onMapCreated,
              onStyleLoadedListener: _onStyleLoaded,
              viewport: CameraViewportState(
                center: Point(coordinates: _balintawakCenter),
                zoom: _getResponsiveZoom(context),
              ),
            ),
          ),
          _buildCornerHeader(),
          _buildMapControls(bottom: 32),
          _buildDebugOverlay(),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOutQuart,
            top: 24, bottom: 24,
            right: _isFleetPanelVisible ? 24 : -450,
            child: PointerInterceptor(
              child: Container(
                width: 420,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 30, spreadRadius: 5, offset: const Offset(-10, 0))],
                  border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5),
                ),
                child: Column(children: [
                  _buildFixedPanelHeader(),
                  const Divider(height: 1),
                  Expanded(child: ClipRRect(borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)), child: _buildFleetStatusContent(null))),
                ]),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOutQuart,
            top: 0, bottom: 0,
            right: _isFleetPanelVisible ? 444 : 0,
            child: Center(
              child: PointerInterceptor(
                child: GestureDetector(
                  onTap: () => setState(() => _isFleetPanelVisible = !_isFleetPanelVisible),
                  child: Container(
                    width: 24, height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00695C), 
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                      ), 
                      boxShadow: AppTheme.pulidongShadow,
                    ),
                    child: Icon(_isFleetPanelVisible ? Icons.keyboard_arrow_right_rounded : Icons.keyboard_arrow_left_rounded, size: 18, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    final activeTrucks = _trucks.where((t) => t['isOnline'] == true).toList();
    final bool hasActiveTrucks = activeTrucks.isNotEmpty;
    final int count = activeTrucks.length;

    // Minimum size 0.18 ensures the handle, title, AND subtitle description stay 100% visible 
    // right above (medyo dikit) the top of the menu navigation container on mobile/iOS/tablet.
    final double minSize = 0.18;
    final double initialSize = !hasActiveTrucks
        ? 0.18
        : (count <= 2 ? 0.22 : 0.26);
    final double maxSize = !hasActiveTrucks
        ? 0.35
        : (count <= 2 ? 0.70 : 0.92);
    final List<double> snapSizes = !hasActiveTrucks
        ? [0.18, 0.35]
        : (count <= 2 ? [0.18, 0.45, 0.70] : [0.18, 0.55, 0.92]);

    // Elevated map controls position to provide a clear, comfortable gap above the sheet
    final double controlsBottom = !hasActiveTrucks
        ? 175.0
        : (count <= 2 ? 210.0 : 245.0);

    return Stack(children: [
      Positioned.fill(
        child: Stack(children: [
          Positioned.fill(
            child: MapWidget(
              gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
              },
              onMapCreated: _onMapCreated,
              onStyleLoadedListener: _onStyleLoaded,
              viewport: CameraViewportState(
                center: Point(coordinates: _balintawakCenter),
                zoom: _getResponsiveZoom(context),
              ),
            ),
          ),
          _buildMapControls(bottom: controlsBottom),
        ]),
      ),
      _buildFloatingHeader(),
      _buildDebugOverlay(),
      Positioned.fill(
        child: DraggableScrollableSheet(
          initialChildSize: initialSize,
          minChildSize: minSize,
          maxChildSize: maxSize,
          snap: true,
          snapSizes: snapSizes,
          builder: (context, scrollController) => PointerInterceptor(
            child: _buildFleetStatusContent(scrollController, isMobile: true),
          ),
        ),
      ),
    ]);
  }

  Widget _buildCornerHeader() {
    final double width = MediaQuery.of(context).size.width;
    final bool isMobile = width < 600;
    final bool isTablet = width >= 600 && width < 1024;

    return Positioned(
      top: isMobile ? 12 : (isTablet ? 16 : 24),
      left: isMobile ? 12 : (isTablet ? 16 : 24),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : (isTablet ? 18 : 24),
          vertical: isMobile ? 8 : (isTablet ? 12 : 16),
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(isMobile ? 16 : 24),
          boxShadow: AppTheme.pulidongShadow,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Fleet GIS Tracking",
              style: TextStyle(
                fontSize: isMobile ? 14.5 : (isTablet ? 17 : 20),
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Colors.greenAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  "Real-time telemetry and monitoring",
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: isMobile ? 10 : 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFixedPanelHeader() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(28, 32, 28, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("Active Fleet Status", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF00796B))),
        SizedBox(height: 4),
        Text("Live collection unit updates", style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Widget _buildDebugOverlay() {
    final active = _trucks.where((t) => t['isOnline'] == true).toList();
    final double width = MediaQuery.of(context).size.width;
    final double topSafeArea = MediaQuery.of(context).padding.top;
    
    final bool isMobile = width < 600;
    final bool isTablet = width >= 600 && width < 900;
    final bool isDesktop = width >= 900;

    final double btnSize = (width * 0.12).clamp(44.0, 50.0);
    final double floatingHeaderBottom = topSafeArea + 12.0 + btnSize;

    // Calculate top position dynamically below the floating header bar
    final double topOffset = isDesktop 
        ? 125.0 
        : (floatingHeaderBottom + (isMobile ? 8.0 : 12.0));
    final double leftOffset = isMobile ? 16.0 : (isTablet ? 20.0 : 24.0);

    return Positioned(
      top: topOffset,
      left: leftOffset,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 14,
          vertical: isMobile ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: Colors.white, 
          borderRadius: BorderRadius.circular(16), 
          boxShadow: AppTheme.pulidongShadow, 
          border: Border.all(color: Colors.white, width: 1.5)
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min, 
          children: [
            _buildHUDSeparator("TOTAL UNITS", "${_trucks.length}", isGreen: true),
            const SizedBox(width: 10),
            Container(width: 1.5, height: 14, color: Colors.grey.shade300),
            const SizedBox(width: 10),
            _buildHUDSeparator("ONLINE", "${active.length}", isGreen: true),
          ],
        ),
      ),
    );
  }

  Widget _buildHUDSeparator(String label, String value, {bool isGreen = false}) {
    return Row(children: [
      Text("$label: ", style: TextStyle(color: Colors.grey.shade600, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
      Text(value, style: TextStyle(color: isGreen ? const Color(0xFF00796B) : const Color(0xFF1A1A1A), fontSize: 12, fontWeight: FontWeight.w900)),
    ]);
  }

  Widget _buildFloatingHeader() {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double btnSize = (screenWidth * 0.12).clamp(44.0, 50.0);
    final bool isMobile = screenWidth < 900;

    return Positioned(
      top: 12, left: 16, right: 16,
      child: SafeArea(
        child: Row(children: [
          _HoverZoomCard(
            onTap: () {
              if (isMobile) {
                Scaffold.of(context).openDrawer();
              } else if (widget.onBack != null) {
                widget.onBack!();
              }
            },
            child: Container(
              width: btnSize, 
              height: btnSize, 
              decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: AppTheme.pulidongShadow), 
              child: Icon(
                isMobile ? Icons.menu_rounded : Icons.arrow_back_ios_new_rounded, 
                color: const Color(0xFF1A1A1A), 
                size: isMobile ? 22 : 18
              )
            )
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(height: btnSize, padding: const EdgeInsets.symmetric(horizontal: 16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: AppTheme.pulidongShadow), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text("Track Fleet", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))), Text("Live GPS connected", style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600))]))),
          const SizedBox(width: 10),
          _HoverZoomCard(
            onTap: isMobile ? _handleManualRefresh : null,
            child: Container(
              width: btnSize, 
              height: btnSize, 
              decoration: BoxDecoration(
                color: Colors.white, 
                shape: BoxShape.circle, 
                boxShadow: AppTheme.pulidongShadow
              ), 
              child: RotationTransition(
                turns: _refreshRotationController,
                child: Icon(
                  isMobile ? Icons.refresh_rounded : Icons.explore_rounded, 
                  color: const Color(0xFF1A1A1A), 
                  size: 20
                ),
              )
            ),
          )
        ]),
      ),
    );
  }

  Widget _buildMapControls({double bottom = 240}) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth >= 900;
    final double btnSize = isDesktop ? 56.0 : (screenWidth * 0.15).clamp(48.0, 60.0);
    final double iconSize = isDesktop ? 24.0 : (screenWidth * 0.065).clamp(22.0, 26.0);
    return Positioned(
      bottom: bottom, left: isDesktop ? 24 : null, right: isDesktop ? null : 16,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _buildMapControlButton(
          icon: Icons.map_outlined, 
          isActive: _isMapActive, 
          size: btnSize, 
          iconSize: iconSize, 
          onTap: () { 
            setState(() => _isMapActive = true); 
            _recenterToBalintawak(); 
            Future.delayed(const Duration(seconds: 2), () { if (mounted) setState(() => _isMapActive = false); }); 
          }
        ),
      ]),
    );
  }

  Widget _buildMapControlButton({required IconData icon, required bool isActive, required double size, required double iconSize, required VoidCallback onTap}) {
    return StatefulBuilder(builder: (context, setInnerState) {
      bool isHovered = false;
      return MouseRegion(onEnter: (_) => setInnerState(() => isHovered = true), onExit: (_) => setInnerState(() => isHovered = false), cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: AnimatedContainer(duration: const Duration(milliseconds: 200), width: size, height: size, decoration: BoxDecoration(color: isActive ? const Color(0xFF00796B) : (isHovered ? const Color(0xFFE0F2F1) : Colors.white), shape: BoxShape.circle, boxShadow: AppTheme.pulidongShadow, border: Border.all(color: isActive ? const Color(0xFF00796B) : (isHovered ? const Color(0xFF00796B).withValues(alpha: 0.3) : Colors.transparent), width: 1.5)), child: Icon(icon, color: isActive ? Colors.white : (isHovered ? const Color(0xFF00796B) : const Color(0xFF1A1A1A)), size: iconSize))));
    });
  }

  Widget _buildFleetStatusContent(ScrollController? scrollController, {bool isMobile = false}) {
    final List sortedTrucks = List.from(_trucks);
    sortedTrucks.sort((a, b) {
      final bool aOnline = a['isOnline'] == true;
      final bool bOnline = b['isOnline'] == true;
      if (aOnline && !bOnline) return -1;
      if (!aOnline && bOnline) return 1;
      return 0;
    });

    final List activeTrucks = sortedTrucks.where((t) => t['isOnline'] == true).toList();

    List<Widget> items;
    if (_isScanning && activeTrucks.isEmpty) {
      items = [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Color(0xFF00796B),
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "Scanning for active unit...",
                  style: TextStyle(color: Colors.grey, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ];
    } else if (activeTrucks.isEmpty) {
      items = [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Text(
              "No online active truck",
              style: TextStyle(color: Colors.grey, fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ];
    } else {
      items = sortedTrucks.map((truck) => _buildOrganizedTruckCard(truck)).toList();
    }
    
    if (isMobile) {
      return Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 25, spreadRadius: 5, offset: Offset(0, -5))],
        ),
        clipBehavior: Clip.antiAlias,
        child: CustomScrollView(
          controller: scrollController,
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _StickyHeaderDelegate(
                minHeight: 88,
                maxHeight: 88,
                child: Container(
                  color: Colors.white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.center,
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Active Fleet Status", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
                            SizedBox(height: 2),
                            Text("Real-time updates on active units", style: TextStyle(fontSize: 11.5, color: Colors.grey, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Divider(height: 1, thickness: 1, color: Color(0xFFF5F5F5)),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.only(top: 8, bottom: 120),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => items[index],
                  childCount: items.length,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ListView(controller: scrollController, physics: const BouncingScrollPhysics(), padding: EdgeInsets.zero, children: [
      const SizedBox(height: 12),
      ...items,
      const SizedBox(height: 120)
    ]);
  }

  Widget _buildOrganizedTruckCard(Map<dynamic, dynamic> truck) {
    final String tid = (truck['truck_id'] ?? truck['truckId'] ?? 'N/A').toString().toUpperCase();
    final String license = (truck['plate_number'] ?? truck['plateNumber'] ?? 'N/A').toString().toUpperCase();
    final String driver = (truck['driver_name'] ?? truck['driverName'] ?? 'Driver').toString();
    final String status = (truck['status'] ?? 'IDLE').toString().toUpperCase();
    final bool isActive = status == 'ACTIVE' || status == 'COLLECTING';
    final Color statusColor = isActive ? const Color(0xFF00796B) : Colors.grey.shade400;

    final double speed = (truck['speed'] ?? 0.0).toDouble();
    final double dist = double.tryParse(truck['distance_covered']?.toString() ?? "0.0") ?? 0.0;
    final double fuel = (truck['fuel_level'] ?? 0.0).toDouble();
    final int stops = (truck['stops_count'] ?? 0) as int;
    final bool isPathVisible = _visiblePaths.contains(tid);
    final bool isBeingFollowed = _isFollowLocked && _followedTruckId?.toUpperCase() == tid.toUpperCase();

    final String purokVal = (truck['purok'] ?? truck['current_purok'] ?? '').toString();
    final double lat = (truck['latitude'] ?? truck['lat'] ?? 0.0).toDouble();
    final double lng = (truck['longitude'] ?? truck['lng'] ?? 0.0).toDouble();

    String locationDisplay = "Waiting for GPS...";
    if (purokVal.isNotEmpty) {
      locationDisplay = purokVal;
    } else if (lat != 0.0 && lng != 0.0) {
      locationDisplay = "${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}";
    }

    String eta = isActive
        ? "${PredictionEngine.estimateArrivalTime(dist > 0 ? dist : 2.5, [
            speed > 5 ? speed : 15.0
          ]).toStringAsFixed(0)} mins"
        : "--";
    String lastUpdate = truck['updatedAt'] != null ? "just now" : "Offline";

    return _HoverZoomCard(
      onTap: () => _focusOnTruck(truck),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: isBeingFollowed ? const Color(0xFF00796B).withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.12),
                blurRadius: isBeingFollowed ? 25 : 20,
                offset: const Offset(0, 0),
                spreadRadius: isBeingFollowed ? 3 : 2,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
                spreadRadius: 0,
              ),
            ],
            border: Border.all(
              color: isBeingFollowed ? const Color(0xFF00796B) : Colors.grey.shade100, 
              width: isBeingFollowed ? 2.5 : 1
            )),
        child: Column(children: [
          // Top Row: Icon, Name/License, Status & TRACKING badge
          Row(children: [
            Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: isBeingFollowed ? const Color(0xFFE0F2F1) : const Color(0xFFE3F2FD), 
                    borderRadius: BorderRadius.circular(16)),
                child: Icon(
                  Icons.local_shipping_rounded, 
                  color: isBeingFollowed ? const Color(0xFF00796B) : const Color(0xFF2196F3), 
                  size: 28
                )),
            const SizedBox(width: 16),
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(driver,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF1A1A1A))),
              Text("$tid | $license",
                  style: const TextStyle(
                      color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600))
            ])),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                    child: Text(status,
                        style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.w900))),
                if (isBeingFollowed) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00796B),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.gps_fixed_rounded, color: Colors.white, size: 10),
                        SizedBox(width: 4),
                        Text("TRACKING", style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ]),

          const SizedBox(height: 24),

          // Middle Info: Location, Speed, Driver
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _buildMetricsInfo(Icons.location_on_rounded, Colors.redAccent, "Location", locationDisplay),
            _buildMetricsInfo(Icons.speed_rounded, Colors.blueAccent, "Speed", "${speed.toStringAsFixed(0)} km/h"),
            _buildMetricsInfo(Icons.person_rounded, Colors.indigoAccent, "Driver", driver),
          ]),

          const SizedBox(height: 20),

          // Metrics Pill Row
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                    spreadRadius: 0,
                  ),
                ],
                border: Border.all(color: Colors.grey.shade100)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _buildPillMetric(Icons.straighten_rounded, Colors.green, "DISTANCE",
                  "${dist.toStringAsFixed(1)} km"),
              Container(width: 1, height: 20, color: Colors.grey.shade300),
              _buildPillMetric(Icons.local_gas_station_rounded, Colors.orange, "FUEL",
                  "${fuel.toStringAsFixed(1)} L"),
              Container(width: 1, height: 20, color: Colors.grey.shade300),
              _buildPillMetric(Icons.pause_circle_filled_rounded, Colors.red, "STOPS", "$stops"),
            ]),
          ),

          const SizedBox(height: 24),

          // Action Buttons
          Row(children: [
            Expanded(
              child: _buildSecondaryButton(
                  "HISTORY", Icons.history_rounded, () => _showHistoryOverlay(context, tid)),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _buildPrimaryButton(
                isPathVisible ? "HIDE PATH" : "COMPARE PATH", 
                Icons.near_me_rounded, 
                isPathVisible ? Colors.orange : const Color(0xFF00796B), 
                () => _togglePath(tid)
              ),
            ),
            const SizedBox(width: 12),
            _buildTargetButton(
              isBeingFollowed: isBeingFollowed,
              onTap: () => _toggleFollowTruck(tid, truck),
            ),
          ]),

          const SizedBox(height: 20),

          // Footer
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _buildFooterInfo(Icons.access_time_rounded, "Last Update: $lastUpdate"),
            _buildFooterInfo(null, "Start: --:--"),
            _buildFooterInfo(null, "ETA: $eta", isTeal: true),
          ]),
        ])),
    );
  }

  void _showHistoryOverlay(BuildContext context, String truckId) {
    final List<Map<dynamic, dynamic>> history = _lastRoutePoints[truckId] ?? [];
    final bool isMobile = MediaQuery.of(context).size.width < 900;
    bool isModalLoading = true;

    Widget contentBody(ScrollController scrollController, StateSetter setModalState) {
      if (isModalLoading) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) setModalState(() => isModalLoading = false);
        });
      }

      return Container(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Activity History", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF00796B))),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded))
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text("Recent route telemetry and collection history.", style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
              ),
            ),
            const Divider(height: 40),
            if (isModalLoading)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(color: Color(0xFF00897B), strokeWidth: 3),
                      const SizedBox(height: 16),
                      Text("Loading unit telemetry...", style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                ),
              )
            else
              Flexible(
                child: history.isEmpty
                    ? const Padding(padding: EdgeInsets.all(40), child: Center(child: Text("No history data recorded yet.", style: TextStyle(color: Colors.grey))))
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: history.length > 10 ? 10 : history.length,
                        itemBuilder: (context, index) {
                          final point = history.reversed.toList()[index];
                          final double pLat = (point['lat'] ?? point['latitude'] ?? 0.0).toDouble();
                          final double pLng = (point['lng'] ?? point['longitude'] ?? 0.0).toDouble();
                          final String rawPurok = (point['purok'] ?? point['current_purok'] ?? '').toString();
                          final String pointPurok = rawPurok.isNotEmpty 
                              ? rawPurok 
                              : (pLat != 0.0 && pLng != 0.0 ? "${pLat.toStringAsFixed(5)}, ${pLng.toStringAsFixed(5)}" : "Waiting for GPS...");
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade100)),
                            child: Row(children: [
                              Container(width: 8, height: 8, decoration: BoxDecoration(color: (point['color'] == 'PINK' ? Colors.pink : const Color(0xFF00796B)), shape: BoxShape.circle)),
                              const SizedBox(width: 16),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text("At $pointPurok", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                                Text("Recorded at ${DateFormat('h:mm a').format(DateTime.fromMillisecondsSinceEpoch(point['timestamp'] as int))}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              ])),
                            ]),
                          );
                        },
                      ),
              ),
          ],
        ),
      );
    }

    if (isMobile) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => StatefulBuilder(
          builder: (context, setModalState) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * (isModalLoading ? 0.5 : 0.8),
              ),
              child: contentBody(ScrollController(), setModalState),
            );
          },
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOut,
                width: 450,
                height: isModalLoading ? 380 : 600,
                child: contentBody(ScrollController(), setModalState),
              ),
            );
          },
        ),
      );
    }
  }

  Widget _buildPillMetric(IconData icon, Color color, String label, String value) {
    return Column(children: [
      Row(children: [Icon(icon, size: 12, color: color), const SizedBox(width: 4), Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.w800))]),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
    ]);
  }

  Widget _buildFooterInfo(IconData? icon, String text, {bool isTeal = false}) {
    return Row(children: [
      if (icon != null) Icon(icon, size: 12, color: Colors.grey),
      if (icon != null) const SizedBox(width: 4),
      Text(text, style: TextStyle(fontSize: 10, color: isTeal ? const Color(0xFF00796B) : Colors.grey, fontWeight: FontWeight.w700)),
    ]);
  }

  Widget _buildMetricsInfo(IconData icon, Color color, String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, size: 12, color: color), const SizedBox(width: 4), Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w700))]),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF1A1A1A))),
    ]);
  }

  Widget _buildSecondaryButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(vertical: 14), decoration: BoxDecoration(color: const Color(0xFFF0F2F5), borderRadius: BorderRadius.circular(16)), alignment: Alignment.center, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: const Color(0xFF1A1A1A), size: 16), const SizedBox(width: 8), Text(label, style: const TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.w900, fontSize: 12))])));
  }

  Widget _buildPrimaryButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(vertical: 14), decoration: BoxDecoration(gradient: LinearGradient(colors: [color.withValues(alpha: 0.8), color]), borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 4))]), alignment: Alignment.center, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: Colors.white, size: 16), const SizedBox(width: 8), Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12))])));
  }

  void _togglePath(String truckId) {
    setState(() {
      if (_visiblePaths.contains(truckId)) { 
        _visiblePaths.remove(truckId); 
        _clearSharedRoute(truckId); 
        CustomNotification.showTopNotification(context, "Path hidden for unit $truckId", false);
      } 
      else {
        _visiblePaths.add(truckId);
        if (_lastRoutePoints.containsKey(truckId)) _updateSharedRoutePolyline(truckId, _lastRoutePoints[truckId]!);
        CustomNotification.showTopNotification(context, "Comparing path for unit $truckId", false);
      }
    });
  }

  Widget _buildTargetButton({required bool isBeingFollowed, required VoidCallback onTap}) {
    final Color btnColor = isBeingFollowed ? const Color(0xFF004D40) : const Color(0xFF00796B);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: btnColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: btnColor.withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
          border: isBeingFollowed
              ? Border.all(color: Colors.tealAccent, width: 2)
              : null,
        ),
        alignment: Alignment.center,
        child: Icon(
          isBeingFollowed ? Icons.gps_fixed_rounded : Icons.my_location_rounded,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }

  void _toggleFollowTruck(String truckId, Map<dynamic, dynamic> truck) {
    setState(() {
      final String canonicalId = truckId.toUpperCase();
      if (_followedTruckId?.toUpperCase() == canonicalId && _isFollowLocked) {
        _followedTruckId = null;
        _isFollowLocked = false;
        CustomNotification.showTopNotification(context, "Stopped tracking unit $truckId", false);
      } else {
        _followedTruckId = canonicalId;
        _isFollowLocked = true;
        _focusOnTruck(truck, zoom: 17.5);
        CustomNotification.showTopNotification(context, "Now tracking live location of unit $truckId", false);
      }
    });
  }
}

class _HoverZoomCard extends StatefulWidget {
  final Widget child; final VoidCallback? onTap; final double scale;
  const _HoverZoomCard({required this.child, this.onTap, this.scale = 1.02});
  @override
  State<_HoverZoomCard> createState() => _HoverZoomCardState();
}
class _HoverZoomCardState extends State<_HoverZoomCard> {
  bool _active = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(onEnter: (_) => setState(() => _active = true), onExit: (_) => setState(() => _active = false), cursor: SystemMouseCursors.click, child: GestureDetector(onTap: widget.onTap, onTapDown: (_) => setState(() => _active = true), onTapUp: (_) => setState(() => _active = false), child: AnimatedScale(scale: _active ? widget.scale : 1.0, duration: const Duration(milliseconds: 200), child: widget.child)));
  }
}

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double minHeight;
  final double maxHeight;

  _StickyHeaderDelegate({
    required this.child,
    required this.minHeight,
    required this.maxHeight,
  });

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox.expand(child: child);
  }

  @override
  double get maxExtent => maxHeight;

  @override  double get minExtent => minHeight;

  @override
  bool shouldRebuild(_StickyHeaderDelegate oldDelegate) {
    return maxHeight != oldDelegate.maxHeight ||
        minHeight != oldDelegate.minHeight ||
        child != oldDelegate.child;
  }
}
