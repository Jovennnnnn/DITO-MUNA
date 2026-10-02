import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size, Visibility;
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/app_theme.dart';
import '../api/api_service.dart';
import '../widgets/fade_slide_entrance.dart';

/// Standalone Web GIS Page for Resident Garbage Truck Tracking
///
/// This application runs independently as a standalone web portal accessible directly
/// through a browser URL (e.g. /tracking or /gis) without requiring users to install
/// or open the mobile application.
class StandaloneGisWebScreen extends StatefulWidget {
  const StandaloneGisWebScreen({super.key});

  @override
  State<StandaloneGisWebScreen> createState() => _StandaloneGisWebScreenState();
}

class _StandaloneGisWebScreenState extends State<StandaloneGisWebScreen> with TickerProviderStateMixin {
  // --- CONFIGURABLE CONSTANTS ---
  /// Hostinger Production Domain
  static const String hostingerDomain = 'https://indigo-bear-885857.hostingersite.com';

  /// URL to redirect users when clicking "Sign In" (Default to system splash entry point)
  static const String loginUrl = '/splash';

  /// Custom Scheme Deep Link URL to open the mobile application directly
  static const String appDeepLinkUrl = 'garbagetracker://login';

  /// URL for residents to download the mobile application directly
  static const String downloadAppUrl = 'https://indigo-bear-885857.hostingersite.com/app-release.apk';

  /// Mapbox Access Token
  static const String mapboxAccessToken =
      "pk.eyJ1IjoicHJpbmNlNjcwMyIsImEiOiJjbW9zeHB2ODIwNDFnMnRwdWxsam9sYWJmIn0.8DQhyf9Z9-yP8lCuP2WS3g";

  // --- STATE MANAGEMENT ---
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final ApiService _apiService = ApiService();
  MapboxMap? _mapboxMap;

  StreamSubscription? _truckLocationsSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _notificationsSubscription;
  Timer? _phpSyncTimer;

  Map<String, dynamic> _firebaseLocations = {};
  Map<String, dynamic> _phpLocations = {};

  List<Map<String, dynamic>> _activeTrucks = [];
  Map<String, dynamic>? _primaryTruck;
  Map<String, dynamic>? _selectedTruck;
  Offset? _selectedTruckScreenPos;
  PointAnnotationManager? _pointAnnotationManager;
  final Map<String, Map<String, dynamic>> _annotationTruckMap = {};

  int _activeTruckCount = 0;
  String _lastUpdatedStr = "Never";
  bool _isLoading = true;
  bool _isUpdatingMarkers = false;

  // Announcement & Alert State
  Map<String, dynamic>? _latestNotification;
  bool _isAlertDismissed = false;
  bool _isAlertExpanded = false;

  // Connection Badge Status
  String _connStatus = "Connecting...";
  Color _connStatusBg = const Color(0xFFFFF9C4);
  Color _connStatusText = const Color(0xFFF57F17);

  // Pulse animation for map pins
  late AnimationController _pulseController;

  // Map viewport default center: Barangay Balintawak, Lipa City, Batangas (Adjusted North)
  final Position _defaultCenter = Position(121.1620, 13.9565);

  @override
  void initState() {
    super.initState();
    MapboxOptions.setAccessToken(mapboxAccessToken);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _pulseController.addListener(_onPulseTick);

    _initFirebase();
    _syncPhpLocations();
    _phpSyncTimer = Timer.periodic(const Duration(seconds: 8), (_) => _syncPhpLocations());
  }

  void _onPulseTick() async {
    if (!mounted || _mapboxMap == null) return;
    try {
      final double progress = _pulseController.value; // 0.0 -> 1.0
      final double radius = 8.0 + (20.0 * progress);  // 8.0 -> 28.0
      final double opacity = ((1.0 - progress) * 0.55).clamp(0.0, 1.0); // 0.55 -> 0.0

      final style = _mapboxMap!.style;
      if (await style.styleLayerExists("web-trucks-pulse-layer")) {
        await style.setStyleLayerProperty("web-trucks-pulse-layer", "circle-radius", radius);
        await style.setStyleLayerProperty("web-trucks-pulse-layer", "circle-opacity", opacity);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _truckLocationsSubscription?.cancel();
    _connectionSubscription?.cancel();
    _notificationsSubscription?.cancel();
    _phpSyncTimer?.cancel();
    _pulseController.removeListener(_onPulseTick);
    _pulseController.dispose();
    super.dispose();
  }

  // --- FIREBASE & REALTIME DATA ---
  void _initFirebase() {
    // 1. Connection status stream
    _connectionSubscription = _database.ref('.info/connected').onValue.listen((event) {
      final bool isConnected = event.snapshot.value == true;
      if (mounted) {
        setState(() {
          if (isConnected) {
            _connStatus = "Live Updates";
            _connStatusBg = const Color(0xFFE8F5E9);
            _connStatusText = const Color(0xFF2E7D32);
          } else {
            _connStatus = "Reconnecting...";
            _connStatusBg = const Color(0xFFFFF3E0);
            _connStatusText = const Color(0xFFE65100);
          }
        });
      }
    }, onError: (error) {
      if (mounted) {
        setState(() {
          _connStatus = "Offline";
          _connStatusBg = const Color(0xFFFFEBEE);
          _connStatusText = const Color(0xFFC62828);
        });
      }
    });

    // 2. Live truck locations stream
    _truckLocationsSubscription = _database.ref('truck_locations').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        _firebaseLocations = Map<String, dynamic>.from(event.snapshot.value as Map);
        _reprocessTruckData();
      } else {
        _handleEmptyTruckData();
      }
    }, onError: (error) {
      debugPrint("[WEB GIS] Firebase error: $error");
      if (mounted) {
        setState(() {
          _connStatus = "Error";
          _connStatusBg = const Color(0xFFFFEBEE);
          _connStatusText = const Color(0xFFC62828);
          _isLoading = false;
        });
      }
    });

    // 3. Live collection notifications / alerts stream
    _notificationsSubscription = _database.ref('notifications').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map rawNotifs = event.snapshot.value as Map;
        Map<String, dynamic>? bestMatch;
        int highestTime = 0;

        rawNotifs.forEach((key, val) {
          if (val is Map) {
            final notifMap = Map<String, dynamic>.from(val);
            final String purok = (notifMap['purok'] ?? notifMap['area'] ?? '').toString().toLowerCase();
            final dynamic ts = notifMap['timestamp'];
            int timeMs = ts is num ? ts.toInt() : 0;

            if (purok.contains('balintawak') || purok.isEmpty) {
              if (timeMs >= highestTime) {
                highestTime = timeMs;
                bestMatch = notifMap;
              }
            }
          }
        });

        if (mounted) {
          setState(() {
            _latestNotification = bestMatch;
          });
        }
      }
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
          final int secondsAgo = secondsAgoRaw is num ? secondsAgoRaw.toInt() : (timestampMs > 0 ? ((now - timestampMs) / 1000).abs().toInt() : -1);

          final bool isOnline = loc['isOnline'] == true || loc['is_online'] == true || loc['is_online'] == 1;

          if (tid.isNotEmpty) {
            phpMap[tid] = {
              'truck_id': tid,
              'driver_name': driverName.isEmpty ? 'Driver' : driverName,
              'plate_number': loc['plate_number'] ?? loc['plateNumber'] ?? '',
              'latitude': lat,
              'longitude': lng,
              'speed': double.tryParse(loc['speed']?.toString() ?? '0') ?? 0.0,
              'status': status,
              'isOnline': isOnline,
              'lastSeen': timestampMs > 0 ? timestampMs : now,
              'seconds_ago': secondsAgo >= 0 ? secondsAgo : null,
              'updatedAt': loc['updated_at'] ?? loc['updatedAt'] ?? now,
            };
          }
        }
        if (mounted) {
          _phpLocations = phpMap;
          _reprocessTruckData();
        }
      }
    } catch (e) {
      debugPrint("[WEB GIS] PHP locations sync error: $e");
    }
  }

  void _reprocessTruckData() {
    final List<Map<String, dynamic>> parsedTrucks = [];
    final int now = DateTime.now().millisecondsSinceEpoch;

    // 1. Merge Firebase RTDB (authoritative) and PHP fallback locations
    final Map<String, Map<String, dynamic>> canonicalMap = {};

    _firebaseLocations.forEach((key, val) {
      if (val is! Map) return;
      final Map<String, dynamic> truckData = Map<String, dynamic>.from(val);
      final String tid = (truckData['truck_id'] ?? truckData['truckId'] ?? key).toString().toUpperCase().trim();
      if (tid.isNotEmpty && tid != "UNKNOWN" && tid != "N/A") {
        canonicalMap[tid] = truckData;
      }
    });

    _phpLocations.forEach((tid, phpData) {
      if (!canonicalMap.containsKey(tid)) {
        canonicalMap[tid] = phpData;
      }
    });

    // 2. Filter ONLY genuinely online/active drivers with valid coordinates and fresh timestamps
    canonicalMap.forEach((tid, val) {
      final Map<String, dynamic> truckData = Map<String, dynamic>.from(val);
      final String status = (truckData['status'] ?? 'ACTIVE').toString().toUpperCase();

      final String driverName = (truckData['driver_name'] ?? truckData['driverName'] ?? '').toString();
      if (driverName.toLowerCase().contains("john driver")) return;

      final double lat = double.tryParse(truckData['latitude']?.toString() ?? truckData['lat']?.toString() ?? '0') ?? 0.0;
      final double lng = double.tryParse(truckData['longitude']?.toString() ?? truckData['lng']?.toString() ?? '0') ?? 0.0;

      final bool isValidCoords = lat != 0.0 && lng != 0.0 && lat >= -90.0 && lat <= 90.0 && lng >= -180.0 && lng <= 180.0;

      final bool isActiveStatus = status == 'ACTIVE' || status == 'IDLE' || status == 'COLLECTING' || status == 'FULL';
      final bool isOfflineStatus = status == 'OFFLINE' || status == 'COMPLETED' || status == 'FINISHED';

      final bool isOnlineFlag = truckData['isOnline'] == true || truckData['is_online'] == true || truckData['is_online'] == 1;

      final dynamic lastSeenRaw = truckData['lastSeen'] ?? truckData['last_seen'] ?? truckData['timestamp'];
      int lastSeenMs = 0;
      if (lastSeenRaw is num) {
        lastSeenMs = lastSeenRaw.toInt();
      } else if (lastSeenRaw != null) {
        String str = lastSeenRaw.toString().trim();
        if (str.contains(' ')) str = str.replaceAll(' ', 'T');
        final parsed = DateTime.tryParse(str);
        if (parsed != null) lastSeenMs = parsed.millisecondsSinceEpoch;
      }

      int secondsAgo = -1;
      final dynamic secondsAgoRaw = truckData['seconds_ago'] ?? truckData['secondsAgo'];
      if (secondsAgoRaw is num) {
        secondsAgo = secondsAgoRaw.toInt();
      } else if (lastSeenMs > 0) {
        secondsAgo = ((now - lastSeenMs) / 1000).abs().toInt();
      }

      // Freshness check: location update must be within last 120 seconds
      final bool isFresh = (secondsAgo >= 0 && secondsAgo <= 120) || (lastSeenMs > 0 && (now - lastSeenMs).abs() <= 120000);

      final bool isGenuinelyActive = isValidCoords && isActiveStatus && !isOfflineStatus && isOnlineFlag && isFresh;

      if (isGenuinelyActive) {
        parsedTrucks.add({
          'truck_id': tid,
          'status': status,
          'latitude': lat,
          'longitude': lng,
          'driver_name': driverName,
          'plate_number': truckData['plate_number'] ?? truckData['plateNumber'] ?? truckData['license_number'] ?? '',
          'speed': double.tryParse(truckData['speed']?.toString() ?? '0') ?? 0.0,
          'updatedAt': truckData['updatedAt'] ?? lastSeenMs,
        });
      }
    });

    if (mounted) {
      setState(() {
        _activeTrucks = parsedTrucks;
        _activeTruckCount = parsedTrucks.length;
        _isLoading = false;

        if (parsedTrucks.isNotEmpty) {
          _primaryTruck = parsedTrucks.first;
          final dynamic rawTime = _primaryTruck!['updatedAt'];
          if (rawTime is int) {
            _lastUpdatedStr = DateFormat('h:mm:ss a').format(DateTime.fromMillisecondsSinceEpoch(rawTime));
          } else if (rawTime is String) {
            final parsed = DateTime.tryParse(rawTime);
            _lastUpdatedStr = parsed != null ? DateFormat('h:mm:ss a').format(parsed) : "Just now";
          } else {
            _lastUpdatedStr = "Just now";
          }
        } else {
          _primaryTruck = null;
          _lastUpdatedStr = "Never";
        }

        if (_selectedTruck != null) {
          final updated = parsedTrucks.firstWhere(
            (t) => t['truck_id'] == _selectedTruck!['truck_id'],
            orElse: () => {},
          );
          if (updated.isNotEmpty) {
            _selectedTruck = updated;
          } else {
            _selectedTruck = null;
            _selectedTruckScreenPos = null;
          }
        }
      });

      _updateMapMarkers();
    }
  }

  void _handleEmptyTruckData() {
    if (mounted) {
      setState(() {
        _firebaseLocations = {};
        _activeTrucks = [];
        _primaryTruck = null;
        _activeTruckCount = 0;
        _lastUpdatedStr = "Never";
        _isLoading = false;
        _selectedTruck = null;
        _selectedTruckScreenPos = null;
      });
      _updateMapMarkers();
    }
  }

  // --- MAPBOX MAP CREATION & MARKER RENDERING ---
  void _onMapCreated(MapboxMap map) {
    _mapboxMap = map;
  }

  void _onStyleLoaded(dynamic data) async {
    if (_mapboxMap == null) return;
    try {
      await _mapboxMap!.location.updateSettings(LocationComponentSettings(enabled: false, pulsingEnabled: false));
      await _mapboxMap!.compass.updateSettings(
        CompassSettings(
          position: OrnamentPosition.TOP_LEFT,
          marginTop: 100.0,
          marginLeft: 20.0,
        ),
      );

      _pointAnnotationManager ??= await _mapboxMap!.annotations.createPointAnnotationManager();
      _pointAnnotationManager!.tapEvents(
        onTap: (annotation) {
          final truck = _annotationTruckMap[annotation.id];
          if (truck != null) {
            setState(() {
              _selectedTruck = truck;
            });
            _updateSelectedTruckScreenPos();
          }
        },
      );
    } catch (_) {}

    _updateMapMarkers(context);
    _recenterMap(context);
  }

  double _getResponsiveZoom(double screenWidth) {
    if (screenWidth >= 1024) {
      return 14.2; // Desktop view
    } else if (screenWidth >= 600) {
      return 13.8; // Tablet view
    } else {
      return 13.1; // Mobile / iOS view (wider area so full Balintawak fits nicely)
    }
  }

  Future<void> _updateMapMarkers([BuildContext? ctx]) async {
    if (_mapboxMap == null || _isUpdatingMarkers) return;
    _isUpdatingMarkers = true;

    final BuildContext? activeContext = ctx ?? (mounted ? context : null);
    final double screenWidth = activeContext != null
        ? MediaQuery.of(activeContext).size.width
        : 1000.0;
    final bool isMobile = screenWidth < 600;

    try {
      final style = _mapboxMap!.style;
      final String sourceId = "web-trucks-source";
      final String circleLayerId = "web-trucks-circle-layer";

      final List<Map<String, dynamic>> features = _activeTrucks.map((truck) {
        final String tid = truck['truck_id'];
        final String status = truck['status'];
        final double lat = truck['latitude'];
        final double lng = truck['longitude'];

        return {
          "type": "Feature",
          "geometry": {
            "type": "Point",
            "coordinates": [lng, lat]
          },
          "properties": {
            "truckId": tid,
            "status": status,
            "label": "🚛 $tid\n$status",
          }
        };
      }).toList();

      final featureCollection = {
        "type": "FeatureCollection",
        "features": features,
      };

      final geoJsonStr = jsonEncode(featureCollection);

      final statusColorExpr = [
        "match", ["get", "status"],
        "IDLE", "#FF9800",
        "FULL", "#F44336",
        "COLLECTING", "#4CAF50",
        "ACTIVE", "#4CAF50",
        "#4CAF50"
      ];

      final double markerRadius = isMobile ? 8.0 : 9.5;
      final double strokeWidth = isMobile ? 3.0 : 3.5;
      final double innerDotRadius = isMobile ? 2.5 : 3.0;
      final double textSize = isMobile ? 11.5 : 13.0;

      if (!(await style.styleSourceExists(sourceId))) {
        await style.addSource(GeoJsonSource(id: sourceId, data: geoJsonStr));

        // 1. Smooth Expanding Pulse Ring Layer
        await style.addLayer(CircleLayer(
          id: "web-trucks-pulse-layer",
          sourceId: sourceId,
          circleRadius: 8.0,
          circleColor: const Color(0xFF4CAF50).toARGB32(),
          circleOpacity: 0.5,
        ));
        await style.setStyleLayerProperty("web-trucks-pulse-layer", "circle-color", statusColorExpr);

        // 2. High-Precision Circular Marker Layer (Main Circular Pinpoint)
        await style.addLayer(CircleLayer(
          id: circleLayerId,
          sourceId: sourceId,
          circleRadius: markerRadius,
          circleColor: const Color(0xFF4CAF50).toARGB32(),
          circleStrokeWidth: strokeWidth,
          circleStrokeColor: Colors.white.toARGB32(),
        ));
        await style.setStyleLayerProperty(circleLayerId, "circle-color", statusColorExpr);

        // 3. Inner White Core Dot
        await style.addLayer(CircleLayer(
          id: "web-trucks-inner-dot",
          sourceId: sourceId,
          circleRadius: innerDotRadius,
          circleColor: Colors.white.toARGB32(),
        ));

        // 4. Text Label Layer
        await style.addLayer(SymbolLayer(
          id: "web-trucks-label-layer",
          sourceId: sourceId,
          textSize: textSize,
          textColor: const Color(0xFF4CAF50).toARGB32(),
          textHaloColor: Colors.white.toARGB32(),
          textHaloWidth: 3.5,
          textAnchor: TextAnchor.BOTTOM,
          textOffset: [0, -2.2],
          symbolSortKey: 100.0,
          textAllowOverlap: true,
          textJustify: TextJustify.CENTER,
        ));
        await style.setStyleLayerProperty("web-trucks-label-layer", "text-field", ["get", "label"]);
        await style.setStyleLayerProperty("web-trucks-label-layer", "text-color", statusColorExpr);
      } else {
        await style.setStyleSourceProperty(sourceId, "data", geoJsonStr);
        await style.setStyleLayerProperty("web-trucks-pulse-layer", "circle-color", statusColorExpr);
        await style.setStyleLayerProperty(circleLayerId, "circle-color", statusColorExpr);
        await style.setStyleLayerProperty(circleLayerId, "circle-radius", markerRadius);
        await style.setStyleLayerProperty("web-trucks-label-layer", "text-field", ["get", "label"]);
        await style.setStyleLayerProperty("web-trucks-label-layer", "text-color", statusColorExpr);
      }

      // 5. Interactive Point Annotations for Tap Detection
      try {
        _pointAnnotationManager ??= await _mapboxMap!.annotations.createPointAnnotationManager();
        await _pointAnnotationManager!.deleteAll();
        _annotationTruckMap.clear();

        for (var truck in _activeTrucks) {
          final double lat = (truck['latitude'] as num).toDouble();
          final double lng = (truck['longitude'] as num).toDouble();
          final String tid = truck['truck_id'].toString();
          final String status = (truck['status'] ?? 'ACTIVE').toString().toUpperCase();
          
          Color statusColor;
          if (status == 'IDLE') {
            statusColor = Colors.orange;
          } else if (status == 'FULL') {
            statusColor = Colors.redAccent;
          } else {
            statusColor = Colors.green;
          }

          final options = PointAnnotationOptions(
            geometry: Point(coordinates: Position(lng, lat)),
            textField: "🚛 $tid",
            textSize: textSize,
            textOffset: [0.0, -2.2],
            textColor: statusColor.toARGB32(),
            textHaloColor: Colors.white.toARGB32(),
            textHaloWidth: 3.5,
          );

          final annotation = await _pointAnnotationManager!.create(options);
          _annotationTruckMap[annotation.id] = truck;
        }
      } catch (_) {}
    } catch (e) {
      debugPrint("[WEB GIS] Marker update error: $e");
    } finally {
      _isUpdatingMarkers = false;
    }
  }

  void _recenterMap([BuildContext? ctx]) {
    final BuildContext? activeContext = ctx ?? (mounted ? context : null);
    final double screenWidth = activeContext != null
        ? MediaQuery.of(activeContext).size.width
        : 1000.0;

    _mapboxMap?.setCamera(
      CameraOptions(
        center: Point(coordinates: _defaultCenter),
        zoom: _getResponsiveZoom(screenWidth),
      ),
    );
  }

  void _updateSelectedTruckScreenPos() async {
    if (_mapboxMap == null || _selectedTruck == null) return;
    try {
      final double lat = (_selectedTruck!['latitude'] as num).toDouble();
      final double lng = (_selectedTruck!['longitude'] as num).toDouble();

      final screenCoord = await _mapboxMap!.pixelForCoordinate(
        Point(coordinates: Position(lng, lat)),
      );

      if (mounted) {
        setState(() {
          _selectedTruckScreenPos = Offset(screenCoord.x.toDouble(), screenCoord.y.toDouble());
        });
      }
    } catch (_) {}
  }

  void _checkHoverOnDesktop(Offset localPosition) async {
    final bool isMobileWeb = kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
         defaultTargetPlatform == TargetPlatform.iOS);

    if (isMobileWeb || _mapboxMap == null || _activeTrucks.isEmpty) return;

    Map<String, dynamic>? hoveredTruck;
    double minDistanceSq = double.infinity;

    for (var truck in _activeTrucks) {
      final double lat = (truck['latitude'] as num).toDouble();
      final double lng = (truck['longitude'] as num).toDouble();

      try {
        final screenCoord = await _mapboxMap!.pixelForCoordinate(
          Point(coordinates: Position(lng, lat)),
        );

        final double dx = localPosition.dx - screenCoord.x;
        final double dy = localPosition.dy - screenCoord.y;
        final double distSq = dx * dx + dy * dy;

        // 40px hover hit test around the marker
        if (distSq <= 40 * 40 && distSq < minDistanceSq) {
          minDistanceSq = distSq;
          hoveredTruck = truck;
        }
      } catch (_) {}
    }

    if (hoveredTruck != null) {
      if (_selectedTruck?['truck_id'] != hoveredTruck['truck_id']) {
        setState(() {
          _selectedTruck = hoveredTruck;
        });
        _updateSelectedTruckScreenPos();
      }
    } else {
      if (_selectedTruck != null) {
        setState(() {
          _selectedTruck = null;
          _selectedTruckScreenPos = null;
        });
      }
    }
  }

  void _handleMapTap(Point tapPoint) {
    if (_activeTrucks.isEmpty) return;

    final double tapLng = tapPoint.coordinates.lng.toDouble();
    final double tapLat = tapPoint.coordinates.lat.toDouble();

    Map<String, dynamic>? clickedTruck;
    double minDistanceSq = double.infinity;

    for (var truck in _activeTrucks) {
      final double truckLat = (truck['latitude'] as num).toDouble();
      final double truckLng = (truck['longitude'] as num).toDouble();

      final double dLat = (tapLat - truckLat).abs();
      final double dLng = (tapLng - truckLng).abs();

      if (dLat < 0.0035 && dLng < 0.0035) {
        final double distSq = dLat * dLat + dLng * dLng;
        if (distSq < minDistanceSq) {
          minDistanceSq = distSq;
          clickedTruck = truck;
        }
      }
    }

    if (clickedTruck != null) {
      setState(() {
        _selectedTruck = clickedTruck;
      });
      _updateSelectedTruckScreenPos();
    } else {
      if (_selectedTruck != null) {
        setState(() {
          _selectedTruck = null;
          _selectedTruckScreenPos = null;
        });
      }
    }
  }

  void _fitMapToActiveTrucks([BuildContext? ctx]) {
    if (_mapboxMap == null || _activeTrucks.isEmpty) return;

    final BuildContext? activeContext = ctx ?? (mounted ? context : null);
    final double screenWidth = activeContext != null
        ? MediaQuery.of(activeContext).size.width
        : 1000.0;

    if (_activeTrucks.length == 1) {
      final truck = _activeTrucks.first;
      _mapboxMap?.setCamera(
        CameraOptions(
          center: Point(
            coordinates: Position(truck['longitude'], truck['latitude']),
          ),
          zoom: _getResponsiveZoom(screenWidth),
        ),
      );
    } else {
      // Calculate bounding box for all active trucks
      double minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;
      for (var t in _activeTrucks) {
        final double lat = t['latitude'];
        final double lng = t['longitude'];
        if (lat < minLat) minLat = lat;
        if (lat > maxLat) maxLat = lat;
        if (lng < minLng) minLng = lng;
        if (lng > maxLng) maxLng = lng;
      }
      final double centerLat = (minLat + maxLat) / 2;
      final double centerLng = (minLng + maxLng) / 2;

      final double zoomLevel = screenWidth < 600 ? 11.8 : 12.5;

      _mapboxMap?.setCamera(
        CameraOptions(
          center: Point(coordinates: Position(centerLng, centerLat)),
          zoom: zoomLevel,
        ),
      );
    }
  }

  // --- ACTIONS ---
  void _launchSignIn() async {
    final bool isMobileWeb = kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
         defaultTargetPlatform == TargetPlatform.iOS);

    if (isMobileWeb) {
      final Uri appUri = Uri.parse(appDeepLinkUrl);
      bool launched = false;
      try {
        if (await canLaunchUrl(appUri)) {
          launched = await launchUrl(appUri, mode: LaunchMode.externalNonBrowserApplication);
        }
      } catch (e) {
        debugPrint("[WEB GIS] Mobile deep link launch error: $e");
      }

      if (!launched) {
        _openWebLogin(openInNewTab: false);
      }
    } else {
      _openWebLogin(openInNewTab: true);
    }
  }

  void _openWebLogin({required bool openInNewTab}) async {
    final String origin = Uri.base.origin;
    String path = Uri.base.path;
    if (!path.endsWith('/')) {
      path = '$path/';
    }
    final String targetUrl = '$origin$path#/splash';
    final Uri uri = Uri.parse(targetUrl);

    try {
      if (openInNewTab) {
        await launchUrl(
          uri,
          webOnlyWindowName: '_blank',
          mode: LaunchMode.externalApplication,
        );
      } else {
        await launchUrl(
          uri,
          webOnlyWindowName: '_self',
          mode: LaunchMode.platformDefault,
        );
      }
    } catch (e) {
      debugPrint("[WEB GIS] Open login error: $e");
    }
  }

  void _launchDownloadApp() async {
    if (!mounted) return;
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 600;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(isMobile ? 20 : 28)),
        child: Container(
          padding: EdgeInsets.all(isMobile ? 20 : 28),
          constraints: BoxConstraints(maxWidth: (screenWidth - 32.0).clamp(280.0, 420.0)),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(isMobile ? 20 : 28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(isMobile ? 12 : 16),
                decoration: const BoxDecoration(
                  color: Color(0xFFE0F2F1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.get_app_rounded, color: const Color(0xFF00796B), size: isMobile ? 28 : 36),
              ),
              SizedBox(height: isMobile ? 12 : 16),
              Text(
                "Download Garbage Truck Tracker",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isMobile ? 17 : 20,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
              SizedBox(height: isMobile ? 8 : 12),
              Text(
                "Access live route notifications, file garbage complaints, and track truck ETAs directly on your mobile device.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isMobile ? 12 : 13,
                  color: Colors.grey,
                  height: 1.4,
                ),
              ),
              SizedBox(height: isMobile ? 18 : 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: isMobile ? 10 : 14),
                        side: const BorderSide(color: Color(0xFF00796B), width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Close", style: TextStyle(color: Color(0xFF00796B), fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: isMobile ? 10 : 14),
                        backgroundColor: const Color(0xFF00796B),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _triggerFileDownload();
                      },
                      child: const Text("Download App", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  void _triggerFileDownload() async {
    String apkUrl = downloadAppUrl;
    if (!apkUrl.startsWith('http://') && !apkUrl.startsWith('https://')) {
      final String origin = Uri.base.origin;
      apkUrl = '$origin/$downloadAppUrl';
    }

    final Uri uri = Uri.parse(apkUrl);
    try {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint("[WEB GIS] Direct app download error: $e");
    }
  }

  // --- BUILD UI ---
  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth >= 1024;
    final bool isMobile = screenWidth < 600;

    final double initialZoom = _getResponsiveZoom(screenWidth);

    return Scaffold(
      backgroundColor: Colors.white,
      body: FadeSlideEntrance(
        child: Column(
          children: [
            // Modern Web Header
            _buildWebHeader(context, screenWidth),

            // Main GIS Content
            Expanded(
              child: Stack(
                children: [
                  // GIS Map Area
                  Positioned.fill(
                    child: MouseRegion(
                      onHover: (event) => _checkHoverOnDesktop(event.localPosition),
                      child: MapWidget(
                        onMapCreated: _onMapCreated,
                        onStyleLoadedListener: _onStyleLoaded,
                        onCameraChangeListener: (_) {
                          if (_selectedTruck != null) {
                            _updateSelectedTruckScreenPos();
                          }
                        },
                        viewport: CameraViewportState(
                          center: Point(coordinates: _defaultCenter),
                          zoom: initialZoom,
                        ),
                      ),
                    ),
                  ),

                  // Information Panel Overlay & Announcement Alert Card
                  if (isDesktop)
                    Positioned(
                      top: 18,
                      left: 18,
                      child: PointerInterceptor(
                        child: SizedBox(
                          width: 310,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildInformationCard(isMobile: false),
                              _buildCollectionAnnouncementCard(isMobile: false),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: PointerInterceptor(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildInformationCard(isMobile: true),
                            _buildCollectionAnnouncementCard(isMobile: true),
                          ],
                        ),
                      ),
                    ),

                  // Floating Map Action Controls (Recenter / Reset)
                  Positioned(
                    bottom: isMobile ? 16 : 24,
                    right: isMobile ? 12 : 24,
                    child: PointerInterceptor(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildMapControlButton(
                            icon: Icons.gps_fixed_rounded,
                            tooltip: "Recenter to Fleet",
                            isMobile: isMobile,
                            onTap: () => _fitMapToActiveTrucks(context),
                          ),
                          SizedBox(height: isMobile ? 8 : 10),
                          _buildMapControlButton(
                            icon: Icons.map_outlined,
                            tooltip: "Reset Map Center",
                            isMobile: isMobile,
                            onTap: () => _recenterMap(context),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Selected Garbage Truck Popup Card
                  if (_selectedTruck != null)
                    _buildAnchoredTruckPopup(context, isMobile),

                  // Loading / Empty Status Overlay
                  if (_isLoading || _activeTruckCount == 0)
                    Positioned.fill(
                      child: PointerInterceptor(
                        child: Container(
                          color: Colors.white.withValues(alpha: _isLoading ? 0.85 : 0.0),
                          child: Center(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 20),
                              padding: EdgeInsets.symmetric(
                                horizontal: isMobile ? 18 : 28,
                                vertical: isMobile ? 14 : 20,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: AppTheme.pulidongShadow,
                                border: Border.all(color: const Color(0xFFE0F2F1), width: 1.5),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_isLoading) ...[
                                    SizedBox(
                                      width: isMobile ? 16 : 20,
                                      height: isMobile ? 16 : 20,
                                      child: const CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Color(0xFF00796B),
                                      ),
                                    ),
                                    SizedBox(width: isMobile ? 12 : 16),
                                    Text(
                                      "Connecting to live truck location...",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: isMobile ? 12 : 13,
                                        color: const Color(0xFF1A1A1A),
                                      ),
                                    ),
                                  ] else ...[
                                    Icon(Icons.info_outline_rounded, color: Colors.orange, size: isMobile ? 18 : 22),
                                    SizedBox(width: isMobile ? 10 : 12),
                                    Text(
                                      "No garbage truck is currently online.",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: isMobile ? 12 : 13,
                                        color: const Color(0xFF1A1A1A),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- HEADER WIDGET ---
  Widget _buildWebHeader(BuildContext context, double screenWidth) {
    final bool isDesktop = screenWidth >= 1024;
    final bool isTablet = screenWidth >= 600 && screenWidth < 1024;
    final bool isMobile = screenWidth < 600;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 32.0 : (isTablet ? 20.0 : 12.0),
        vertical: isMobile ? 10.0 : 14.0,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Logo & Title
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(isMobile ? 8 : 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.loginButtonStart, AppColors.loginButtonEnd],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.loginButtonEnd.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      )
                    ],
                  ),
                  child: Icon(
                    Icons.local_shipping_rounded,
                    size: isMobile ? 18 : 22,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: isMobile ? 8 : 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Garbage Truck Tracker",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isDesktop ? 20 : (isTablet ? 17 : 14),
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF1A1A1A),
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: _connStatusBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: _connStatusText,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  _connStatus,
                                  style: TextStyle(
                                    color: _connStatusText,
                                    fontSize: isMobile ? 9.0 : 10.0,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Right: Action Buttons
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Download App Button
              _buildHeaderActionButton(
                label: isDesktop ? "Download App" : "App",
                icon: Icons.smartphone_rounded,
                isOutlined: true,
                isMobile: isMobile,
                tooltip: "Directly download the mobile app",
                onTap: _launchDownloadApp,
              ),

              SizedBox(width: isMobile ? 6 : 10),

              // Login to App Button
              _buildHeaderActionButton(
                label: isDesktop ? "Login to App" : "Login",
                icon: Icons.login_rounded,
                isOutlined: false,
                isMobile: isMobile,
                tooltip: "Login to the App. Click to open full system in a new tab.",
                onTap: _launchSignIn,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderActionButton({
    required String label,
    required IconData icon,
    required bool isOutlined,
    bool isMobile = false,
    String? tooltip,
    required VoidCallback onTap,
  }) {
    bool isHovered = false;
    bool isPressed = false;

    return StatefulBuilder(
      builder: (context, setHover) {
        final bool isHighlight = isHovered || isPressed;

        Widget buttonContent = MouseRegion(
          onEnter: (_) => setHover(() => isHovered = true),
          onExit: (_) => setHover(() => isHovered = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTapDown: (_) => setHover(() => isPressed = true),
            onTapUp: (_) => setHover(() => isPressed = false),
            onTapCancel: () => setHover(() => isPressed = false),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 10.0 : 16.0,
                vertical: isMobile ? 8.0 : 10.0,
              ),
              decoration: BoxDecoration(
                color: isOutlined
                    ? (isHighlight ? const Color(0xFFE0F2F1) : Colors.white)
                    : (isHighlight ? const Color(0xFF004D40) : const Color(0xFF00796B)),
                borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
                border: isOutlined
                    ? Border.all(color: const Color(0xFF00796B), width: 1.5)
                    : null,
                boxShadow: isOutlined
                    ? null
                    : [
                        BoxShadow(
                          color: const Color(0xFF00796B).withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        )
                      ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: isMobile ? 14 : 16,
                    color: isOutlined ? const Color(0xFF00796B) : Colors.white,
                  ),
                  SizedBox(width: isMobile ? 4 : 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: isMobile ? 11.5 : 13.0,
                      fontWeight: FontWeight.w800,
                      color: isOutlined ? const Color(0xFF00796B) : Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        if (tooltip != null) {
          return Tooltip(message: tooltip, child: buttonContent);
        }
        return buttonContent;
      },
    );
  }

  // --- INFORMATION CARD WIDGET ---
  Widget _buildInformationCard({bool isMobile = false}) {
    final String truckDisplay = _activeTruckCount > 1
        ? "$_activeTruckCount Trucks Active"
        : (_primaryTruck != null
            ? (_primaryTruck!['truck_id'] ?? 'GT-001')
            : "--");

    final String statusDisplay = _activeTruckCount > 1
        ? "FLEET ONLINE"
        : (_primaryTruck != null
            ? (_primaryTruck!['status'] ?? 'ACTIVE')
            : "OFFLINE");

    final bool isOnline = _activeTruckCount > 0;
    final Color statusColor = isOnline ? const Color(0xFF00796B) : Colors.grey.shade500;

    if (isMobile) {
      Color badgeBg;
      Color badgeText;
      if (statusDisplay == 'IDLE') {
        badgeBg = const Color(0xFFFFF3E0);
        badgeText = Colors.orange.shade800;
      } else if (statusDisplay == 'FULL') {
        badgeBg = const Color(0xFFFFEBEE);
        badgeText = Colors.redAccent;
      } else if (isOnline) {
        badgeBg = const Color(0xFFE8F5E9);
        badgeText = const Color(0xFF2E7D32);
      } else {
        badgeBg = const Color(0xFFF5F5F5);
        badgeText = Colors.grey.shade600;
      }

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(18),
          boxShadow: AppTheme.pulidongShadow,
          border: Border.all(color: const Color(0xFFE0F2F1), width: 1.5),
        ),
        child: Row(
          children: [
            // Truck ID & Live Subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          truckDisplay,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1A1A1A),
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isOnline ? const Color(0xFF00E676) : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isOnline ? "Fleet Online • Updated $_lastUpdatedStr" : "No active truck online",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Right: Status Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                statusDisplay,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: badgeText,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(15.0),
      decoration: AppDecorations.cardDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        radius: 20.0,
      ).copyWith(
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: AppTheme.pulidongShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.local_shipping_outlined, color: statusColor, size: 17),
                  const SizedBox(width: 6),
                  const Text(
                    "CURRENT TRUCK",
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF00796B),
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isOnline ? const Color(0xFFE8F5E9) : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  statusDisplay,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    color: statusColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Primary Truck Value
          Text(
            truckDisplay,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1A1A1A),
              letterSpacing: -0.5,
            ),
          ),

          const SizedBox(height: 10),
          Divider(height: 1, color: Colors.grey.shade200),
          const SizedBox(height: 10),

          // Details Grid
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildInfoSubItem(
                label: "Fleet Status",
                value: isOnline ? "ONLINE" : "OFFLINE",
                valueColor: statusColor,
                isMobile: false,
              ),
              _buildInfoSubItem(
                label: "Last Updated",
                value: _lastUpdatedStr,
                valueColor: const Color(0xFF1A1A1A),
                isMobile: false,
              ),
            ],
          ),

          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: const Row(
              children: [
                Icon(Icons.sync_rounded, size: 14, color: Color(0xFF00796B)),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "The map updates automatically in real-time.",
                    style: TextStyle(fontSize: 10.5, color: Colors.grey, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSubItem({required String label, required String value, required Color valueColor, bool isMobile = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: isMobile ? 9 : 10, color: Colors.grey, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(fontSize: isMobile ? 12 : 13, fontWeight: FontWeight.w900, color: valueColor),
        ),
      ],
    );
  }

  // --- ANNOUNCEMENT / GARBAGE COLLECTION ALERT WIDGET ---
  Widget _buildCollectionAnnouncementCard({bool isMobile = false}) {
    if (_isAlertDismissed) {
      // Small re-open button when dismissed
      return Container(
        margin: EdgeInsets.only(top: isMobile ? 6 : 10),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _isAlertDismissed = false),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF00796B), width: 1.2),
                boxShadow: AppTheme.pulidongShadow,
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.campaign_rounded, size: 14, color: Color(0xFF00796B)),
                  SizedBox(width: 5),
                  Text(
                    "Show Collection Alert",
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF00796B),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Determine Alert Content based on active truck status or real-time notifications
    final bool isTruckActive = _activeTruckCount > 0;
    final String truckId = _primaryTruck != null ? (_primaryTruck!['truck_id'] ?? 'GT-001') : 'TR-005';

    String alertTitle;
    String alertMessage;
    String statusTag;
    Color statusTagBg;
    Color statusTagText;
    IconData alertIcon;

    if (isTruckActive) {
      alertTitle = "Garbage Collection Ongoing";
      alertMessage = "Garbage truck ($truckId) is actively collecting in Barangay Balintawak. Please place your waste at designated pickup points.";
      statusTag = "Ongoing";
      statusTagBg = const Color(0xFFE8F5E9);
      statusTagText = const Color(0xFF2E7D32);
      alertIcon = Icons.delete_outline_rounded;
    } else if (_latestNotification != null && (_latestNotification!['title'] != null || _latestNotification!['message'] != null)) {
      alertTitle = (_latestNotification!['title'] ?? "Collection Announcement").toString();
      alertMessage = (_latestNotification!['message'] ?? "Notice for Barangay Balintawak residents.").toString();
      statusTag = "Notice";
      statusTagBg = const Color(0xFFE3F2FD);
      statusTagText = const Color(0xFF1565C0);
      alertIcon = Icons.campaign_rounded;
    } else {
      alertTitle = "Barangay Collection Schedule";
      alertMessage = "Regular garbage collection is scheduled for Barangay Balintawak. Please prepare segregated waste in proper bins.";
      statusTag = "Mon - Sat";
      statusTagBg = const Color(0xFFFFF3E0);
      statusTagText = const Color(0xFFE65100);
      alertIcon = Icons.schedule_rounded;
    }

    if (isMobile) {
      // Mobile Compact Collapsible Card
      return Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppTheme.pulidongShadow,
          border: Border.all(color: const Color(0xFF00796B).withValues(alpha: 0.25), width: 1.2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2F1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(alertIcon, size: 14, color: const Color(0xFF00796B)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    alertTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1A1A1A),
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusTagBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusTag,
                    style: TextStyle(
                      fontSize: 9.0,
                      fontWeight: FontWeight.w900,
                      color: statusTagText,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => setState(() => _isAlertExpanded = !_isAlertExpanded),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      _isAlertExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => _isAlertDismissed = true),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.close_rounded, size: 15, color: Colors.grey.shade500),
                  ),
                ),
              ],
            ),
            if (_isAlertExpanded) ...[
              const SizedBox(height: 6),
              Divider(height: 1, color: Colors.grey.shade200),
              const SizedBox(height: 6),
              Text(
                alertMessage,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade800,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      );
    }

    // Desktop / Tablet Announcement Card
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16.0),
        boxShadow: AppTheme.pulidongShadow,
        border: Border.all(color: const Color(0xFF00796B).withValues(alpha: 0.25), width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2F1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(alertIcon, size: 14, color: const Color(0xFF00796B)),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    alertTitle,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1A1A1A),
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: statusTagBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      statusTag,
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                        color: statusTagText,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  InkWell(
                    onTap: () => setState(() => _isAlertDismissed = true),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, size: 13, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 8),
          Text(
            alertMessage,
            style: TextStyle(
              fontSize: 10.5,
              color: Colors.grey.shade800,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // --- ANCHORED TRUCK POPUP WIDGET ---
  Widget _buildAnchoredTruckPopup(BuildContext context, bool isMobile) {
    if (_selectedTruck == null) return const SizedBox.shrink();

    final double screenWidth = MediaQuery.of(context).size.width;
    final double screenHeight = MediaQuery.of(context).size.height;
    final double popupWidth = isMobile ? (screenWidth - 24.0).clamp(260.0, 310.0) : 310.0;
    final double popupHeight = isMobile ? 210.0 : 230.0;

    double left = (screenWidth - popupWidth) / 2;
    double top = isMobile ? (screenHeight - popupHeight - 20.0) : 100.0;

    if (_selectedTruckScreenPos != null) {
      // Center popup horizontally over truck marker pin
      left = _selectedTruckScreenPos!.dx - (popupWidth / 2);
      // Position popup directly ABOVE the truck pin
      top = _selectedTruckScreenPos!.dy - popupHeight - 40.0;

      // Keep popup 100% inside screen viewport bounds
      left = left.clamp(12.0, (screenWidth - popupWidth - 12.0).clamp(12.0, screenWidth));
      top = top.clamp(60.0, (screenHeight - popupHeight - 12.0).clamp(60.0, screenHeight));
    }

    return Positioned(
      left: left,
      top: top,
      child: PointerInterceptor(
        child: SizedBox(
          width: popupWidth,
          child: _buildTruckPopupCard(_selectedTruck!, isMobile),
        ),
      ),
    );
  }

  // --- TRUCK POPUP CARD WIDGET ---
  Widget _buildTruckPopupCard(Map<String, dynamic> truck, bool isMobile) {
    final String truckId = (truck['truck_id'] ?? 'GT-001').toString();
    final String status = (truck['status'] ?? 'ACTIVE').toString().toUpperCase();
    final String driverName = (truck['driver_name'] ?? '').toString();
    final String plateNumber = (truck['plate_number'] ?? truck['plateNumber'] ?? '').toString();
    final double speed = double.tryParse(truck['speed']?.toString() ?? '0') ?? 0.0;

    final dynamic rawTime = truck['updatedAt'];
    String lastUpdated = "Just now";
    if (rawTime is int) {
      lastUpdated = DateFormat('h:mm:ss a').format(DateTime.fromMillisecondsSinceEpoch(rawTime));
    } else if (rawTime is String) {
      final parsed = DateTime.tryParse(rawTime);
      if (parsed != null) lastUpdated = DateFormat('h:mm:ss a').format(parsed);
    }

    final bool isOnline = status == 'ACTIVE' || status == 'COLLECTING' || status == 'IDLE';
    final Color statusColor = isOnline ? const Color(0xFF00796B) : Colors.grey;

    return Container(
      width: isMobile ? double.infinity : 310,
      padding: EdgeInsets.all(isMobile ? 14 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 18 : 24),
        boxShadow: AppTheme.pulidongShadow,
        border: Border.all(color: const Color(0xFFE0F2F1), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(isMobile ? 6 : 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2F1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text("🚛", style: TextStyle(fontSize: isMobile ? 15 : 18)),
                  ),
                  SizedBox(width: isMobile ? 8 : 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Garbage Truck",
                        style: TextStyle(
                          fontSize: isMobile ? 9 : 10,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF00796B),
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        truckId,
                        style: TextStyle(
                          fontSize: isMobile ? 16 : 18,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF1A1A1A),
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isOnline ? const Color(0xFFE8F5E9) : const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status == 'ACTIVE' ? 'On Route' : status,
                      style: TextStyle(
                        fontSize: isMobile ? 8.5 : 9.0,
                        fontWeight: FontWeight.w900,
                        color: statusColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => setState(() => _selectedTruck = null),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, size: 14, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ],
          ),

          SizedBox(height: isMobile ? 10 : 14),
          Divider(height: 1, color: Colors.grey.shade200),
          SizedBox(height: isMobile ? 10 : 14),

          _buildPopupDetailRow("Truck ID", truckId, Icons.badge_outlined, isMobile),

          if (driverName.isNotEmpty && driverName.toLowerCase() != 'driver')
            _buildPopupDetailRow("Driver", driverName, Icons.person_outline_rounded, isMobile),

          if (plateNumber.isNotEmpty && plateNumber.toLowerCase() != 'n/a')
            _buildPopupDetailRow("Plate Number", plateNumber, Icons.directions_car_outlined, isMobile),

          _buildPopupDetailRow("Status", status == 'ACTIVE' ? 'On Route' : status, Icons.info_outline_rounded, isMobile),

          if (speed > 0)
            _buildPopupDetailRow("Speed", "${speed.toStringAsFixed(0)} km/h", Icons.speed_rounded, isMobile),

          _buildPopupDetailRow("Last Updated", lastUpdated, Icons.access_time_rounded, isMobile),
        ],
      ),
    );
  }

  Widget _buildPopupDetailRow(String label, String value, IconData icon, [bool isMobile = false]) {
    return Padding(
      padding: EdgeInsets.only(bottom: isMobile ? 5.0 : 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: isMobile ? 12 : 14, color: Colors.grey.shade600),
              SizedBox(width: isMobile ? 4 : 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: isMobile ? 10 : 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isMobile ? 11 : 12,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF1A1A1A),
            ),
          ),
        ],
      ),
    );
  }

  // --- MAP CONTROL BUTTON WIDGET ---
  Widget _buildMapControlButton({
    required IconData icon,
    required String tooltip,
    bool isMobile = false,
    required VoidCallback onTap,
  }) {
    bool isHovered = false;
    bool isPressed = false;
    final double buttonSize = isMobile ? 40.0 : 48.0;
    final double iconSize = isMobile ? 18.0 : 20.0;

    return StatefulBuilder(
      builder: (context, setHover) {
        final bool isHighlight = isHovered || isPressed;

        return MouseRegion(
          onEnter: (_) => setHover(() => isHovered = true),
          onExit: (_) => setHover(() => isHovered = false),
          cursor: SystemMouseCursors.click,
          child: Tooltip(
            message: tooltip,
            child: GestureDetector(
              onTapDown: (_) => setHover(() => isPressed = true),
              onTapUp: (_) => setHover(() => isPressed = false),
              onTapCancel: () => setHover(() => isPressed = false),
              onTap: onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: buttonSize,
                height: buttonSize,
                decoration: BoxDecoration(
                  color: isHighlight ? const Color(0xFFE0F2F1) : Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: isHighlight
                      ? [
                          BoxShadow(
                            color: const Color(0xFF00796B).withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ]
                      : AppTheme.pulidongShadow,
                  border: Border.all(
                    color: isHighlight ? const Color(0xFF00796B) : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  icon,
                  size: iconSize,
                  color: isHighlight ? const Color(0xFF00796B) : const Color(0xFF1A1A1A),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
