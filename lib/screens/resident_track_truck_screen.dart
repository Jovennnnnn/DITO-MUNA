import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size, Visibility;
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:geolocator/geolocator.dart' as geo;
import '../utils/prediction_engine.dart';
import '../utils/app_theme.dart';
import '../utils/session_manager.dart';
import '../models/user.dart';
import '../widgets/custom_snackbar.dart';
import '../widgets/fade_slide_entrance.dart';
import '../utils/custom_notification.dart';

class ResidentTrackTruckScreen extends StatefulWidget {
  final bool isEmbedded;
  final VoidCallback? onBack;
  const ResidentTrackTruckScreen({super.key, this.isEmbedded = false, this.onBack});

  @override
  State<ResidentTrackTruckScreen> createState() => _ResidentTrackTruckScreenState();
}

class _ResidentTrackTruckScreenState extends State<ResidentTrackTruckScreen> with TickerProviderStateMixin {
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  MapboxMap? mapboxMap;
  List<Map<dynamic, dynamic>> _trucks = [];
  Map<String, dynamic> _allTrucksRegistry = {};
  Map<String, dynamic> _liveLocations = {};
  final Set<String> _comparingTrucks = {};
  geo.Position? _residentPosition;
  final DraggableScrollableController _sheetController = DraggableScrollableController();

  final Map<String, StreamSubscription> _routeSubscriptions = {};
  final Map<String, Position?> _sessionStartPoints = {};
  final Map<String, List<Map>> _lastRoutePoints = {};

  bool _isUpdatingMarkers = false;
  bool _isFollowLocked = true;
  bool _isMapActive = false;
  bool _isTargetActive = false;
  bool _isFleetPanelVisible = true;
  bool _isRefreshing = false;
  bool _isDataLoading = true;
  bool _isDataExpanded = false;
  late AnimationController _refreshRotationController;
  final Position _balintawakCenter = Position(121.1623, 13.9413);

  // Animation for Header Circles & Pulse Effect
  late AnimationController _circleController;
  Timer? _pulseTimer;
  double _pulseRadius = 8.0;
  double _pulseOpacity = 0.5;
  double _pulseRadius2 = 8.0; // Second pulse ring
  double _pulseOpacity2 = 0.3;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _listenToTrucks();
    _getResidentLocation();
    _circleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat();
    _refreshRotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _startPulseAnimation();
    
    // Initial Data Loading Animation
    _isDataLoading = true;
    _isDataExpanded = false;
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() {
          _isDataLoading = false;
          Future.delayed(const Duration(milliseconds: 50), () => setState(() => _isDataExpanded = true));
        });
      }
    });
  }

  void _handleManualRefresh() async {
    if (_isRefreshing) return;
    
    setState(() => _isRefreshing = true);
    _refreshRotationController.repeat();
    
    try {
      // 1. Force re-fetch Resident Location
      await _getResidentLocation();
      
      // 2. Force re-fetch Trucks and Locations
      final trucksSnapshot = await _database.ref('trucks').get();
      if (trucksSnapshot.exists) {
        _allTrucksRegistry = Map<String, dynamic>.from(trucksSnapshot.value as Map);
      }
      
      final locSnapshot = await _database.ref('truck_locations').get();
      _liveLocations = locSnapshot.exists ? Map<String, dynamic>.from(locSnapshot.value as Map) : {};
      
      _processMergedTrucks();

      // 3. UI Feedback (Centered White Box)
      if (mounted) {
        showDialog(
          context: context,
          barrierColor: Colors.black.withOpacity(0.1),
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
                    BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, 5))
                  ],
                ),
                child: const Material(
                  color: Colors.transparent,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                      SizedBox(width: 12),
                      Text("Tracking data refreshed", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF1A1A1A))),
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

  void _startPulseAnimation() {
    _pulseTimer?.cancel();
    _pulseTimer = Timer.periodic(const Duration(milliseconds: 35), (timer) {
      if (!mounted || mapboxMap == null) return;
      
      setState(() {
        // Pulse 1
        _pulseRadius += 0.6;
        _pulseOpacity -= 0.015;
        if (_pulseRadius >= 28.0) {
          _pulseRadius = 8.0;
          _pulseOpacity = 0.6;
        }

        // Pulse 2 (offset)
        _pulseRadius2 += 0.6;
        _pulseOpacity2 -= 0.015;
        if (_pulseRadius2 >= 28.0) {
          _pulseRadius2 = 8.0;
          _pulseOpacity2 = 0.4;
        } else if (_pulseRadius2 < 8.0) {
          _pulseRadius2 = 18.0;
          _pulseOpacity2 = 0.4;
        }
      });
      _updatePulseLayers();
    });
  }

  void _updatePulseLayers() async {
    if (mapboxMap == null) return;
    try {
      final style = mapboxMap!.style;
      if (await style.styleLayerExists("trucks-pulse-layer")) {
        await style.setStyleLayerProperty("trucks-pulse-layer", "circle-radius", _pulseRadius);
        await style.setStyleLayerProperty("trucks-pulse-layer", "circle-opacity", _pulseOpacity.clamp(0.0, 1.0));
      }
      if (await style.styleLayerExists("trucks-pulse-layer-2")) {
        await style.setStyleLayerProperty("trucks-pulse-layer-2", "circle-radius", _pulseRadius2);
        await style.setStyleLayerProperty("trucks-pulse-layer-2", "circle-opacity", _pulseOpacity2.clamp(0.0, 1.0));
      }
      if (await style.styleLayerExists("resident-pulse-layer")) {
        await style.setStyleLayerProperty("resident-pulse-layer", "circle-radius", _pulseRadius);
        await style.setStyleLayerProperty("resident-pulse-layer", "circle-opacity", _pulseOpacity.clamp(0.0, 1.0));
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _routeSubscriptions.forEach((key, sub) => sub.cancel());
    _circleController.dispose();
    _refreshRotationController.dispose();
    _pulseTimer?.cancel();
    super.dispose();
  }

  void _loadUser() async {
    // Note: _user was marked unused, keeping it removed to clean up
  }

  Future<void> _getResidentLocation() async {
    geo.LocationPermission permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }

    geo.Geolocator.getPositionStream().listen((pos) {
      if (mounted) {
        setState(() => _residentPosition = pos);
        _updateTruckMarkers();
        if (_isFollowLocked && mapboxMap != null) {
          mapboxMap?.setCamera(CameraOptions(center: Point(coordinates: Position(pos.longitude, pos.latitude))));
        }
      }
    });

    geo.Position startPos = await geo.Geolocator.getCurrentPosition();
    if (mounted) {
      setState(() => _residentPosition = startPos);
      _updateTruckMarkers();
    }
  }

  void _listenToTrucks() {
    _database.ref('trucks').onValue.listen((event) {
      if (event.snapshot.exists) {
        _allTrucksRegistry = Map<String, dynamic>.from(event.snapshot.value as Map);
        _processMergedTrucks();
      }
    });

    _database.ref('truck_locations').onValue.listen((event) {
      _liveLocations = event.snapshot.exists ? Map<String, dynamic>.from(event.snapshot.value as Map) : {};
      _processMergedTrucks();
    });
  }

  void _processMergedTrucks() {
    final List<Map<dynamic, dynamic>> mergedList = [];

    _allTrucksRegistry.forEach((id, truckData) {
      final String tid = id.toString().toUpperCase();
      final Map rawLive = _liveLocations[tid] ?? {};
      final liveData = Map<String, dynamic>.from(rawLive);

      mergedList.add({
        ...Map<String, dynamic>.from(truckData as Map),
        ...liveData,
        'truck_id': tid,
        'status': liveData['isOnline'] == true ? (liveData['status'] ?? 'ACTIVE') : 'OFFLINE',
      });
    });

    if (mounted) {
      setState(() => _trucks = mergedList);
      _updateTruckMarkers();
      
      final activeTruckIds = mergedList.where((t) => t['isOnline'] == true).map((t) => t['truck_id'] as String).toSet();
      final trucksToClear = _routeSubscriptions.keys.where((id) => !activeTruckIds.contains(id)).toList();

      for (var id in trucksToClear) {
        _routeSubscriptions[id]?.cancel();
        _routeSubscriptions.remove(id);
        _clearTruckRoute(id);
      }

      for (var t in mergedList) {
        if (t['isOnline'] != true) continue;
        final String tid = t['truck_id'];
        final String? sid = t['current_session'];
        if (sid != null) {
          if (!_routeSubscriptions.containsKey(tid)) _setupRouteSubscription(tid, sid);
        } else {
          _routeSubscriptions[tid]?.cancel();
          _routeSubscriptions.remove(tid);
          _clearTruckRoute(tid);
        }
      }
    }
  }

  void _setupRouteSubscription(String truckId, String sessionId) {
    _routeSubscriptions[truckId]?.cancel();
    _routeSubscriptions[truckId] = _database.ref('driver_routes/$sessionId/route').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map data = event.snapshot.value as Map;
        final List<Map> points = [];
        data.forEach((key, value) => points.add(value as Map));
        points.sort((a, b) => (a['timestamp'] ?? 0).compareTo(b['timestamp'] ?? 0));

        _lastRoutePoints[truckId] = points;

        if (_comparingTrucks.contains(truckId)) {
          _updateRoutePolyline(truckId, points);
        }
      }
    });

    _database.ref('driver_routes/$sessionId').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map data = event.snapshot.value as Map;
        if (data['start_lat'] != null && data['start_lng'] != null) {
          if (mounted) {
            setState(() => _sessionStartPoints[truckId] = Position(data['start_lng'], data['start_lat']));
            _updateTruckMarkers();
          }
        }
      }
    });
  }

  void _clearTruckRoute(String truckId) async {
     if (mapboxMap == null) return;
     try {
       final style = mapboxMap!.style;
       final String sourceId = "route-source-$truckId";
       if (await style.styleSourceExists(sourceId)) {
         await style.setStyleSourceProperty(sourceId, "data", jsonEncode({"type": "FeatureCollection", "features": []}));
       }
     } catch (_) {}
     if (mounted) {
       setState(() => _sessionStartPoints.remove(truckId));
       _updateTruckMarkers();
     }
  }

  void _updateRoutePolyline(String truckId, List<Map> points) async {
    if (mapboxMap == null || points.length < 2) return;
    points.sort((a, b) => (a['timestamp'] as num).compareTo(b['timestamp'] as num));

    final String sourceId = "route-source-$truckId";
    final List<Map<String, dynamic>> segments = [];

    final List<Map> smoothedPoints = [];
    if (points.isNotEmpty) {
      smoothedPoints.add(points.first);
      for (int i = 1; i < points.length; i++) {
        final prev = smoothedPoints.last;
        final curr = points[i];
        final double d = geo.Geolocator.distanceBetween(
          (prev['lat'] ?? 0.0).toDouble(), (prev['lng'] ?? 0.0).toDouble(),
          (curr['lat'] ?? 0.0).toDouble(), (curr['lng'] ?? 0.0).toDouble()
        );
        if (d > 5.0 || i == points.length - 1) smoothedPoints.add(curr);
      }
    }

    for (int i = 1; i < smoothedPoints.length; i++) {
      final prev = smoothedPoints[i - 1];
      final curr = smoothedPoints[i];
      final double prevLng = (prev['lng'] ?? 0.0).toDouble();
      final double prevLat = (prev['lat'] ?? 0.0).toDouble();
      final double currLng = (curr['lng'] ?? 0.0).toDouble();
      final double currLat = (curr['lat'] ?? 0.0).toDouble();
      final int prevTs = (prev['timestamp'] ?? 0) as int;
      final int currTs = (curr['timestamp'] ?? 0) as int;
      final String color = (curr['color'] ?? 'GREEN').toString().toUpperCase();
      final bool isGap = (currTs - prevTs) > 60000;

      if (!isGap) {
        if (segments.isNotEmpty && segments.last['properties']['color'] == color) {
          final List coords = segments.last['geometry']['coordinates'];
          if (coords.isEmpty || coords.last[0] != currLng || coords.last[1] != currLat) coords.add([currLng, currLat]);
        } else {
          segments.add({
            "type": "Feature",
            "geometry": { "type": "LineString", "coordinates": [[prevLng, prevLat], [currLng, currLat]] },
            "properties": {"color": color}
          });
        }
      }
    }

    final featureCollection = {"type": "FeatureCollection", "features": segments};
    try {
      final style = mapboxMap!.style;
      if (!(await style.styleSourceExists(sourceId))) {
        await style.addSource(GeoJsonSource(id: sourceId, data: jsonEncode(featureCollection)));
        await style.addLayer(LineLayer(id: "route-layer-$truckId", sourceId: sourceId, lineColor: Colors.green.toARGB32(), lineWidth: 8.0, lineOpacity: 0.9, lineCap: LineCap.ROUND, lineJoin: LineJoin.ROUND));
        await style.setStyleLayerProperty("route-layer-$truckId", "line-color", ["match", ["get", "color"], "GREEN", "#00FF00", "YELLOW", "#FFFF00", "PINK", "#FF1493", "BLACK", "#000000", "BLUE", "#0000FF", "#00FF00"]);
      } else { await style.setStyleSourceProperty(sourceId, "data", jsonEncode(featureCollection)); }
    } catch (_) {}
  }

  void _recenterToBalintawak() { mapboxMap?.setCamera(CameraOptions(center: Point(coordinates: _balintawakCenter), zoom: 14.5)); }
  void _recenterToResident() { if (_residentPosition == null) return; mapboxMap?.setCamera(CameraOptions(center: Point(coordinates: Position(_residentPosition!.longitude, _residentPosition!.latitude)), zoom: 16.5)); }
  void _focusOnTruck(Map<dynamic, dynamic> truck) {
    final double lat = (truck['latitude'] ?? 0.0).toDouble();
    final double lng = (truck['longitude'] ?? 0.0).toDouble();
    if (lat == 0 || lng == 0) return;
    mapboxMap?.setCamera(CameraOptions(center: Point(coordinates: Position(lng, lat)), zoom: 17.5));
  }

  void _onMapCreated(MapboxMap map) { mapboxMap = map; }
  void _onStyleLoaded(dynamic data) async {
    mapboxMap?.location.updateSettings(LocationComponentSettings(enabled: false, pulsingEnabled: false));

    // Relocate compass to top left, below the HUD (UNITS/GPS) bar
    // HUD is at top: 155. MarginTop 200.0 places it clearly below.
    mapboxMap?.compass.updateSettings(CompassSettings(
      position: OrnamentPosition.TOP_LEFT,
      marginTop: 200.0,
      marginLeft: 20.0,
    ));

    _updateTruckMarkers();
    _recenterToBalintawak();
  }

  void _updateTruckMarkers() async {
    if (mapboxMap == null || _isUpdatingMarkers) return;
    _isUpdatingMarkers = true;

    try {
      final style = mapboxMap!.style;
      final String sourceId = "trucks-live-location-source";
      final String residentSourceId = "resident-marker-source";

      final List<Map<String, dynamic>> features = _trucks.where((t) => (t['latitude'] ?? 0) != 0 && (t['longitude'] ?? 0) != 0).map((truck) {
        final String status = (truck['status'] ?? "ACTIVE").toString().toUpperCase();
        return {
          "type": "Feature",
          "geometry": {"type": "Point", "coordinates": [(truck['longitude'] ?? 0.0).toDouble(), (truck['latitude'] ?? 0.0).toDouble()]},
          "properties": {
            "type": "TRUCK",
            "truckId": truck['truck_id'].toString(),
            "status": status,
            "label": "${truck['truck_id']}\n$status"
          }
        };
      }).toList();

      for (var entry in _sessionStartPoints.entries) {
        if (entry.value != null && _comparingTrucks.contains(entry.key)) {
          features.add({ "type": "Feature", "geometry": {"type": "Point", "coordinates": [entry.value!.lng, entry.value!.lat]}, "properties": {"type": "SESSION_START", "label": "START / ${entry.key}"} });
        }
      }

      final residentFeature = _residentPosition == null ? null : {
        "type": "Feature",
        "geometry": {"type": "Point", "coordinates": [_residentPosition!.longitude, _residentPosition!.latitude]},
        "properties": {"label": "YOU"}
      };

      // 1. ENSURE SOURCES EXIST
      if (!(await style.styleSourceExists(sourceId))) {
        await style.addSource(GeoJsonSource(id: sourceId, data: jsonEncode({"type": "FeatureCollection", "features": features})));
      } else {
        await style.setStyleSourceProperty(sourceId, "data", jsonEncode({"type": "FeatureCollection", "features": features}));
      }

      if (!(await style.styleSourceExists(residentSourceId))) {
        await style.addSource(GeoJsonSource(id: residentSourceId, data: jsonEncode({"type": "FeatureCollection", "features": residentFeature != null ? [residentFeature] : []})));
      } else {
        await style.setStyleSourceProperty(residentSourceId, "data", jsonEncode({"type": "FeatureCollection", "features": residentFeature != null ? [residentFeature] : []}));
      }

      // 2. ENSURE LAYERS EXIST (Check every time to prevent "disappearing" on refresh)
      if (!(await style.styleLayerExists("trucks-marker-circle")) || !(await style.styleLayerExists("resident-marker-label"))) {
        final statusColorExpr = [
          "match", ["get", "status"],
          "IDLE", Colors.orange.toARGB32(),
          "PAUSED", Colors.orange.toARGB32(),
          "STOP", Colors.red.toARGB32(),
          "STOPPED", Colors.red.toARGB32(),
          "FULL", Colors.red.toARGB32(),
          "COMPLETE", Colors.blue.toARGB32(),
          "FINISHED", Colors.blue.toARGB32(),
          "COMPLETED", Colors.blue.toARGB32(),
          Colors.green.toARGB32()
        ];

        // REMOVE OLD TO BE SAFE
        try { await style.removeStyleLayer("resident-pulse-layer"); } catch (_) {}
        try { await style.removeStyleLayer("trucks-pulse-layer"); } catch (_) {}
        try { await style.removeStyleLayer("resident-marker-circle"); } catch (_) {}
        try { await style.removeStyleLayer("trucks-marker-circle"); } catch (_) {}
        try { await style.removeStyleLayer("resident-marker-label"); } catch (_) {}
        try { await style.removeStyleLayer("trucks-live-location-label"); } catch (_) {}

        // A. Pulse Halos (Bottom layer)
        await style.addLayer(CircleLayer(id: "resident-pulse-layer", sourceId: residentSourceId, circleRadius: _pulseRadius, circleColor: const Color(0xFF2196F3).toARGB32(), circleOpacity: _pulseOpacity, circleSortKey: 10.0));
        await style.addLayer(CircleLayer(id: "trucks-pulse-layer", sourceId: sourceId, circleRadius: _pulseRadius, circleColor: Colors.green.toARGB32(), circleOpacity: _pulseOpacity, circleSortKey: 20.0, filter: ["==", ["get", "type"], "TRUCK"]));
        await style.setStyleLayerProperty("trucks-pulse-layer", "circle-color", statusColorExpr);

        // B. Solid Center Pins (Middle layer)
        await style.addLayer(CircleLayer(id: "resident-marker-circle", sourceId: residentSourceId, circleRadius: 10.0, circleColor: const Color(0xFF2196F3).toARGB32(), circleStrokeWidth: 4.0, circleStrokeColor: Colors.white.toARGB32(), circleSortKey: 100.0));
        await style.addLayer(CircleLayer(id: "trucks-marker-circle", sourceId: sourceId, circleRadius: 10.0, circleColor: Colors.green.toARGB32(), circleStrokeWidth: 4.0, circleStrokeColor: Colors.white.toARGB32(), circleSortKey: 110.0, filter: ["==", ["get", "type"], "TRUCK"]));
        await style.setStyleLayerProperty("trucks-marker-circle", "circle-color", statusColorExpr);

        // C. Bolder Labels (Top layer)
        await style.addLayer(SymbolLayer(
          id: "resident-marker-label",
          sourceId: residentSourceId,
          textSize: 14.0,
          textColor: const Color(0xFF2196F3).toARGB32(),
          textHaloColor: Colors.white.toARGB32(),
          textHaloWidth: 3.5,
          textAnchor: TextAnchor.BOTTOM,
          textOffset: [0, -3.2],
          symbolSortKey: 200.0,
          textAllowOverlap: true,
          textIgnorePlacement: true,
        ));
        await style.setStyleLayerProperty("resident-marker-label", "text-field", ["get", "label"]);

        await style.addLayer(SymbolLayer(
          id: "trucks-live-location-label",
          sourceId: sourceId,
          textSize: 15.0,
          textColor: Colors.green.toARGB32(),
          textHaloColor: Colors.white.toARGB32(),
          textHaloWidth: 3.5,
          textAnchor: TextAnchor.BOTTOM,
          textOffset: [0, -3.2],
          symbolSortKey: 210.0,
          textAllowOverlap: true,
          textIgnorePlacement: true,
          textJustify: TextJustify.CENTER,
          filter: ["==", ["get", "type"], "TRUCK"]
        ));
        await style.setStyleLayerProperty("trucks-live-location-label", "text-field", ["get", "label"]);
        await style.setStyleLayerProperty("trucks-live-location-label", "text-color", statusColorExpr);
      }
    } catch (e) {
      debugPrint("GIS Sync Error: $e");
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
          backgroundColor: AppColors.dashboardBg,
          body: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
        ),
      );
    });
  }

  Widget _buildMapControls({double bottom = 240}) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth >= 900;
    final double btnSize = isDesktop ? 56.0 : (screenWidth * 0.15).clamp(48.0, 60.0);
    final double iconSize = isDesktop ? 24.0 : (screenWidth * 0.065).clamp(22.0, 26.0);

    // Dynamic positioning: Controls on Left for Web/Desktop, Right for Mobile
    final double effectiveBottom = bottom;
    final double? effectiveLeft = isDesktop ? 24 : null;
    final double? effectiveRight = isDesktop ? null : 16;

    return Positioned(
      bottom: effectiveBottom,
      left: effectiveLeft,
      right: effectiveRight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // FOLLOW TOGGLE (TARGET ICON)
          _buildMapControlButton(
            icon: _isFollowLocked ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded,
            isActive: _isFollowLocked || _isTargetActive,
            size: btnSize,
            iconSize: iconSize,
            onTap: () {
              setState(() {
                _isFollowLocked = !_isFollowLocked;
                _isTargetActive = true;
              });
              if (_isFollowLocked && _residentPosition != null) {
                mapboxMap?.setCamera(CameraOptions(
                    center: Point(coordinates: Position(_residentPosition!.longitude, _residentPosition!.latitude)),
                    zoom: 16.5));
                mapboxMap?.gestures.updateSettings(
                    GesturesSettings(scrollEnabled: false, rotateEnabled: false, pitchEnabled: false));
              } else {
                mapboxMap?.gestures.updateSettings(
                    GesturesSettings(scrollEnabled: true, rotateEnabled: true, pitchEnabled: true));
              }
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) setState(() => _isTargetActive = false);
              });
            },
          ),
          const SizedBox(height: 12),
          // RECENTER (MAP ICON)
          _buildMapControlButton(
            icon: Icons.map_outlined,
            isActive: _isMapActive,
            size: btnSize,
            iconSize: iconSize,
            onTap: () {
              setState(() => _isMapActive = true);
              _recenterToBalintawak();
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) setState(() => _isMapActive = false);
              });
            },
          ),
          const SizedBox(height: 12),
          // GUIDE ICON
          _buildMapControlButton(
            icon: Icons.description_outlined,
            isActive: false,
            size: btnSize,
            iconSize: iconSize,
            onTap: _showTrackingGuide,
          ),
        ],
      ),
    );
  }

  Widget _buildMapControlButton({
    required IconData icon,
    required bool isActive,
    required double size,
    required double iconSize,
    required VoidCallback onTap,
  }) {
    return StatefulBuilder(
      builder: (context, setInnerState) {
        bool isHovered = false;
        return MouseRegion(
          onEnter: (_) => setInnerState(() => isHovered = true),
          onExit: (_) => setInnerState(() => isHovered = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFF00796B)
                    : (isHovered ? const Color(0xFFE0F2F1) : Colors.white),
                shape: BoxShape.circle,
                boxShadow: AppTheme.pulidongShadow,
                border: Border.all(
                  color: isActive ? const Color(0xFF00796B) : (isHovered ? const Color(0xFF00796B).withOpacity(0.3) : Colors.transparent),
                  width: 1.5,
                ),
              ),
              child: Icon(
                icon,
                color: isActive ? Colors.white : (isHovered ? const Color(0xFF00796B) : const Color(0xFF1A1A1A)),
                size: iconSize,
              ),
            ),
          ),
        );
      },
    );
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
          // 1. Full GIS Map Background
          Positioned.fill(
            child: MapWidget(
              onMapCreated: _onMapCreated,
              onStyleLoadedListener: _onStyleLoaded,
              viewport: CameraViewportState(
                center: Point(coordinates: _balintawakCenter),
                zoom: 14.5,
              ),
            ),
          ),

          // 2. Corner Header (Top-Left)
          _buildCornerHeader(),

          // 3. Map Controls HUD (Bottom Left)
          _buildMapControls(bottom: 32),

          // 4. Debug / Units Info Overlay
          _buildDebugOverlay(),

          // 5. Floating Fleet Status Panel (Right Aligned)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOutQuart,
            top: 24,
            bottom: 24,
            right: _isFleetPanelVisible ? 24 : -450,
            child: PointerInterceptor(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeInOutCubic,
                width: 420,
                height: _isDataLoading ? 200 : null,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 30,
                      spreadRadius: 5,
                      offset: const Offset(-10, 0),
                    )
                  ],
                  border: Border.all(color: Colors.white.withOpacity(0.6), width: 1.5),
                ),
                child: Column(
                  mainAxisSize: _isDataLoading ? MainAxisSize.min : MainAxisSize.max,
                  children: [
                    // Fixed Header for Panel (No X Button)
                    _buildFixedPanelHeader(),
                    const Divider(height: 1),
                    if (_isDataLoading)
                      const Expanded(
                        child: Center(
                          child: CircularProgressIndicator(color: Color(0xFF00796B)),
                        ),
                      )
                    else
                      // Scrolling content with internal scroll containment
                      Expanded(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 400),
                            opacity: _isDataExpanded ? 1.0 : 0.0,
                            child: _buildFleetStatusContent(null),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Toggle Tab for panel
          AnimatedPositioned(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOutQuart,
            top: 0,
            bottom: 0,
            right: _isFleetPanelVisible ? 444 : 0,
            child: Center(
              child: PointerInterceptor(
                child: GestureDetector(
                  onTap: () => setState(() => _isFleetPanelVisible = !_isFleetPanelVisible),
                  child: Container(
                    width: 24,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00695C),
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                      boxShadow: AppTheme.pulidongShadow,
                    ),
                    child: Icon(
                      _isFleetPanelVisible
                          ? Icons.keyboard_arrow_right_rounded
                          : Icons.keyboard_arrow_left_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCornerHeader() {
    return Positioned(
      top: 24,
      left: 24,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppTheme.pulidongShadow,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Fleet GIS Tracking",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                const Text("Real-time telemetry and monitoring",
                    style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w700)),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Active Fleet Status",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF00796B))),
          SizedBox(height: 4),
          Text("Live collection unit updates",
              style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildMobilePanelHeader() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(28, 20, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Active Fleet Status",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
          SizedBox(height: 4),
          Text("Real-time updates on active units",
              style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Stack(children: [
      Positioned.fill(child: Stack(
        children: [
          Positioned.fill(child: MapWidget(onMapCreated: _onMapCreated, onStyleLoadedListener: _onStyleLoaded, viewport: CameraViewportState(center: Point(coordinates: _balintawakCenter), zoom: 14.5))),
          _buildMapControls(bottom: 200),
        ],
      )),
      _buildFloatingHeader(),
      _buildDebugOverlay(),
      Positioned.fill(child: DraggableScrollableSheet(
        controller: _sheetController,
        initialChildSize: 0.22,
        minChildSize: 0.22,
        maxChildSize: 0.95,
        snap: true,
        snapSizes: const [0.22, 0.5, 0.95],
        builder: (context, scrollController) => PointerInterceptor(
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 25, spreadRadius: 5, offset: Offset(0, -5))]
            ),
            child: Column(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (details) {
                    if (_sheetController.isAttached) {
                      _sheetController.jumpTo((_sheetController.size - details.delta.dy / MediaQuery.of(context).size.height).clamp(0.22, 0.95));
                    }
                  },
                  onVerticalDragEnd: (details) {
                    if (_sheetController.isAttached) {
                      final double current = _sheetController.size;
                      if (current < 0.36) {
                        _sheetController.animateTo(0.22, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                      } else if (current < 0.72) {
                        _sheetController.animateTo(0.5, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                      } else {
                        _sheetController.animateTo(0.95, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                      }
                    }
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          width: 50,
                          height: 6,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(10)
                          )
                        )
                      ),
                      _buildMobilePanelHeader(),
                    ],
                  ),
                ),
                Divider(height: 1, color: Colors.grey.shade100, thickness: 1),
                if (_isDataLoading)
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height * 0.5),
                        child: const Center(
                          child: CircularProgressIndicator(color: Color(0xFF00796B)),
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 400),
                      opacity: _isDataExpanded ? 1.0 : 0.0,
                      child: _buildFleetStatusContent(scrollController, isMobile: true)
                    ),
                  ),
              ],
            )
          )
        )
      ))
    ]);
  }

  Widget _buildDebugOverlay() {
    final active = _trucks.where((t) => (t['latitude'] ?? 0) != 0).toList();
    final bool isDesktop = MediaQuery.of(context).size.width >= 900;
    return Positioned(
      top: isDesktop ? 125 : 155, // Lowered from 110 to 125 for desktop
      left: isDesktop ? 24 : 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppTheme.pulidongShadow,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHUDSeparator("TOTAL UNITS", "${_trucks.length}", isGreen: true),
            const SizedBox(width: 12),
            Container(width: 1.5, height: 16, color: Colors.grey.shade300),
            const SizedBox(width: 12),
            _buildHUDSeparator("ONLINE", "${active.length}", isGreen: true),
          ],
        ),
      ),
    );
  }

  Widget _buildHUDSeparator(String label, String value, {bool isGreen = false}) {
    return Row(
      children: [
        Text("$label: ",
            style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5)),
        Text(value,
            style: TextStyle(
                color: isGreen ? const Color(0xFF00796B) : const Color(0xFF1A1A1A),
                fontSize: 12,
                fontWeight: FontWeight.w900)),
      ],
    );
  }

  Widget _buildFloatingHeader() {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double titleFontSize = (screenWidth * 0.045).clamp(16.0, 18.0);
    final double subtitleFontSize = (screenWidth * 0.025).clamp(9.0, 10.0);
    final double btnSize = (screenWidth * 0.12).clamp(44.0, 50.0);
    final double iconSize = (screenWidth * 0.045).clamp(18.0, 20.0);

    return Positioned(
      top: 12, left: 16, right: 16,
      child: SafeArea(
        child: Row(
          children: [
            if (widget.onBack != null)
              _HoverZoomLink(
                onTap: widget.onBack!,
                child: Container(
                  width: btnSize,
                  height: btnSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: AppTheme.pulidongShadow,
                  ),
                  child: Icon(Icons.arrow_back_ios_new_rounded, color: const Color(0xFF1A1A1A), size: iconSize)
                )
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: btnSize,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: AppTheme.pulidongShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Track Fleet", style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.w800, color: const Color(0xFF1A1A1A), letterSpacing: -0.5)),
                    Text("Live GPS connected", style: TextStyle(fontSize: subtitleFontSize, color: Colors.grey, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            _HoverZoomCard(
              onTap: _handleManualRefresh,
              child: Container(
                width: btnSize,
                height: btnSize,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: AppTheme.pulidongShadow,
                  border: Border.all(color: Colors.black.withOpacity(0.15), width: 1.5),
                ),
                child: RotationTransition(
                  turns: _refreshRotationController,
                  child: Icon(Icons.refresh_rounded, color: Colors.black87, size: iconSize)
                )
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildFleetStatusContent(ScrollController? scrollController, {bool isMobile = false}) {
    // Sorting: Online/Active trucks first
    final List sortedTrucks = List.from(_trucks);
    sortedTrucks.sort((a, b) {
      final bool aOnline = a['isOnline'] == true;
      final bool bOnline = b['isOnline'] == true;
      if (aOnline && !bOnline) return -1;
      if (!aOnline && bOnline) return 1;
      return 0;
    });

    final activeTrucks = sortedTrucks.where((t) => t['isOnline'] == true).toList();

    final List<Widget> items = sortedTrucks.isEmpty
        ? [
            const Padding(
                padding: EdgeInsets.all(60),
                child: Center(
                    child: Text("Scanning for active units...",
                        style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500))))
          ]
        : sortedTrucks.map((truck) => _buildOrganizedTruckCard(truck)).toList();

    if (isMobile) {
      return ListView(
          controller: scrollController,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(top: 16),
          children: [
            ...items,
            const SizedBox(height: 120)
          ]);
    }

    return ListView(
      controller: scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(top: 12),
      children: [
        ...items,
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildOrganizedTruckCard(Map<dynamic, dynamic> truck) {
    final String tid = truck['truck_id'].toString();
    final String license = (truck['license_number'] ?? 'N/A').toString();
    final String driver = (truck['driver_name'] ?? 'Driver').toString();
    final String status = (truck['status'] ?? 'IDLE').toString().toUpperCase();
    final bool isActive = status == 'ACTIVE' || status == 'COLLECTING';
    final Color statusColor = isActive ? const Color(0xFF00796B) : Colors.grey.shade400;

    final double speed = (truck['speed'] ?? 0.0).toDouble();
    final double dist = (truck['distance'] ?? 0.0).toDouble();
    final double fuel = (truck['fuel_level'] ?? 0.0).toDouble();
    final int stops = (truck['stops_count'] ?? 0) as int;

    String eta = isActive
        ? "${PredictionEngine.estimateArrivalTime(dist > 0 ? dist : 2.5, [
            speed > 5 ? speed : 15.0
          ]).toStringAsFixed(0)} mins"
        : "--";
    String lastUpdate = truck['updatedAt'] != null ? "just now" : "Offline";

    return _HoverZoomCard(
      onTap: () => _focusOnTruck(truck),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 20,
                offset: const Offset(0, 0),
                spreadRadius: 2,
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
                spreadRadius: 0,
              ),
            ],
            border: Border.all(color: Colors.grey.shade50, width: 1)),
        child: Column(children: [
          // Top Row: Icon, Name/License, Status
          Row(children: [
            Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: const Color(0xFFE3F2FD), borderRadius: BorderRadius.circular(16)),
                child:
                    const Icon(Icons.local_shipping_rounded, color: Color(0xFF2196F3), size: 28)),
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
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: statusColor.withAlpha(20), borderRadius: BorderRadius.circular(12)),
                child: Text(status,
                    style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.w900))),
          ]),

          const SizedBox(height: 24),

          // Middle Info: Location, Speed, Driver
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _buildMetricsInfo(Icons.location_on_rounded, Colors.redAccent, "Location",
                (truck['current_purok'] ?? "Balintawak").toString()),
            _buildMetricsInfo(Icons.speed_rounded, Colors.blueAccent, "Speed",
                "${speed.toStringAsFixed(0)} km/h"),
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
                    color: Colors.black.withOpacity(0.05),
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

          const SizedBox(height: 20),

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
                  _comparingTrucks.contains(tid) ? "HIDE PATH" : "COMPARE PATH",
                  Icons.near_me_rounded,
                  _comparingTrucks.contains(tid) ? Colors.orange : const Color(0xFF00796B),
                  () => _togglePath(tid)),
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

  Widget _buildMetricsInfo(IconData icon, Color color, String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF1A1A1A))),
    ]);
  }

  Widget _buildPillMetric(IconData icon, Color color, String label, String value) {
    return Column(children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
      ]),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Color(0xFF2196F3))),
    ]);
  }

  Widget _buildFooterInfo(IconData? icon, String text, {bool isTeal = false}) {
    return Row(children: [
      if (icon != null) ...[Icon(icon, size: 12, color: Colors.grey), const SizedBox(width: 4)],
      Text(text, style: TextStyle(
        fontSize: 10,
        color: isTeal ? const Color(0xFF00796B) : Colors.grey,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2
      )),
    ]);
  }

  Widget _buildSecondaryButton(String label, IconData icon, VoidCallback onTap) {
    return _HoverZoomLink(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F2F5),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: const Color(0xFF1A1A1A), size: 16),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.w900, fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _buildPrimaryButton(String label, IconData icon, Color color, VoidCallback onTap) {
    bool isOrange = label.contains("HIDE");
    return _HoverZoomLink(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isOrange
              ? [const Color(0xFFFF9800), const Color(0xFFE65100)] // Orange Gradient
              : [AppColors.loginButtonStart, AppColors.loginButtonEnd], // Green Gradient (Logout Style)
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: (isOrange ? const Color(0xFFE65100) : AppColors.loginButtonEnd).withAlpha(60),
              blurRadius: 10,
              offset: const Offset(0, 4)
            )
          ],
        ),
        alignment: Alignment.center,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
        ]),
      ),
    );
  }

  void _togglePath(String truckId) {
    if (!_comparingTrucks.contains(truckId) && !_lastRoutePoints.containsKey(truckId)) {
      CustomNotification.showTopNotification(
        context,
        "No active path data for $truckId",
        true,
      );
      return;
    }
    setState(() {
      if (_comparingTrucks.contains(truckId)) {
        _comparingTrucks.remove(truckId);
        _clearTruckRoute(truckId);
        CustomNotification.showTopNotification(
          context,
          "Path hidden for unit $truckId",
          false,
        );
      } else {
        _comparingTrucks.add(truckId);
        if (_lastRoutePoints.containsKey(truckId)) {
          _updateRoutePolyline(truckId, _lastRoutePoints[truckId]!);
        }
        CustomNotification.showTopNotification(
          context,
          "Comparing path for unit $truckId",
          false,
        );
      }
      _updateTruckMarkers();
    });
  }

  void _showHistoryOverlay(BuildContext context, String truckId) {
    final List<Map> history = _lastRoutePoints[truckId] ?? [];
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
                const Text("Activity Log",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF00796B))),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded))
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text("Recent route history and status updates.",
                    style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
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
                      Text("Synchronizing log data...", style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                ),
              )
            else
              Flexible(
                child: history.isEmpty
                    ? const Center(child: Text("No recent data recorded.", style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: history.length > 5 ? 5 : history.length,
                        itemBuilder: (context, index) {
                          final point = history.reversed.toList()[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F9FA),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade100),
                            ),
                            child: Row(children: [
                              Container(
                                width: 10, height: 10,
                                decoration: BoxDecoration(
                                  color: (point['color'] == 'PINK' ? Colors.pink : const Color(0xFF00796B)),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("At ${point['purok'] ?? 'Balintawak'}",
                                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                                    Text("Recorded recently",
                                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  ],
                                ),
                              ),
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
                maxHeight: MediaQuery.of(context).size.height * (isModalLoading ? 0.45 : 0.7),
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
                height: isModalLoading ? 350 : 550,
                child: contentBody(ScrollController(), setModalState),
              ),
            );
          },
        ),
      );
    }
  }

  void _showTrackingGuide() {
    final bool isDesktop = MediaQuery.of(context).size.width >= 900;
    bool isLoading = true;
    bool isExpanded = false;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          if (isLoading) {
            Future.delayed(const Duration(milliseconds: 500), () {
              if (context.mounted) {
                setState(() {
                  isLoading = false;
                  Future.delayed(const Duration(milliseconds: 50), () => setState(() => isExpanded = true));
                });
              }
            });
          }

          Widget header = Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  "GIS Tracking Guide",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF00796B)),
                ),
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded))
            ],
          );

          Widget content = SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isDesktop)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildGuideSection(
                          "Telemetry Status",
                          [
                            _buildGuideItem(Icons.circle, "Active: Collection", color: Colors.green),
                            _buildGuideItem(Icons.circle, "Idle: Stationary", color: Colors.yellow),
                            _buildGuideItem(Icons.circle, "Full: High Load", color: Colors.pinkAccent),
                          ],
                          hasShadow: false,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: _buildGuideSection(
                          "Map Controls",
                          [
                            _buildGuideItem(Icons.gps_fixed_rounded, "Lock/Follow", color: Colors.blue),
                            _buildGuideItem(Icons.map_outlined, "Recenter Map", color: Colors.blue),
                          ],
                          hasShadow: false,
                        ),
                      ),
                    ],
                  )
                else
                  Column(
                    children: [
                      _buildGuideSection(
                        "Telemetry Status",
                        [
                          _buildGuideItem(Icons.circle, "Active: Collection", color: Colors.green),
                          _buildGuideItem(Icons.circle, "Idle: Stationary", color: Colors.yellow),
                          _buildGuideItem(Icons.circle, "Full: High Load", color: Colors.pinkAccent),
                        ],
                        hasShadow: false,
                      ),
                      const SizedBox(height: 16),
                      _buildGuideSection(
                        "Map Controls",
                        [
                          _buildGuideItem(Icons.gps_fixed_rounded, "Lock/Follow", color: Colors.blue),
                          _buildGuideItem(Icons.map_outlined, "Recenter Map", color: Colors.blue),
                        ],
                        hasShadow: false,
                      ),
                    ],
                  ),
                const SizedBox(height: 20),
                _buildGuideSection(
                  "Advanced Features",
                  [
                    _buildGuideText("• Smart Paths: View AI-optimized collection routes."),
                    _buildGuideText("• Live Pulse: Indicators show unit connection health."),
                    _buildGuideText("• Fleet Intel: Access driver data in the side panel."),
                  ],
                  hasShadow: false,
                ),
              ],
            ),
          );

          return Dialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOutCubic,
              width: isDesktop ? 550 : MediaQuery.of(context).size.width * 0.9,
              constraints: BoxConstraints(
                maxHeight: isLoading ? 350 : MediaQuery.of(context).size.height * 0.85,
              ),
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  header,
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Comprehensive guide to real-time fleet telemetry and map interactions.",
                      style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ),
                  const Divider(height: 48),
                  if (isLoading)
                    const Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Color(0xFF00796B)),
                            SizedBox(height: 16),
                            Text("Preparing GIS guide...",
                                style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 300),
                        opacity: isExpanded ? 1.0 : 0.0,
                        child: content,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGuideSection(String title, List<Widget> items, {bool hasShadow = true}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: hasShadow ? AppTheme.pulidongShadow : null,
        border: Border.all(color: Colors.grey.shade300, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF1A1A1A))),
          const SizedBox(height: 16),
          ...items,
        ],
      ),
    );
  }

  Widget _buildGuideItem(IconData icon, String text, {required Color color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 12),
          Text(text, style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildGuideText(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w600)),
    );
  }

  void _showStyledBottomSheet({required String title, required List<Widget> children}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        padding: EdgeInsets.fromLTRB(0, 12, 0, MediaQuery.of(context).viewInsets.bottom),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 12), decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.tealText))),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.grey)),
                ],
              ),
            ),
            if (title == "Activity Log")
              const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    "View the recent route history and status updates for this vehicle.",
                    textAlign: TextAlign.left,
                    style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 32), child: Divider(height: 32)),
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                child: Column(mainAxisSize: MainAxisSize.min, children: children),
              ),
            ),
          ],
        ),
      ),
    );
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

class _HoverZoomLink extends StatefulWidget {
  final Widget child; final VoidCallback onTap;
  const _HoverZoomLink({required this.child, required this.onTap});
  @override
  State<_HoverZoomLink> createState() => _HoverZoomLinkState();
}
class _HoverZoomLinkState extends State<_HoverZoomLink> {
  bool _active = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(onEnter: (_) => setState(() => _active = true), onExit: (_) => setState(() => _active = false), cursor: SystemMouseCursors.click, child: GestureDetector(onTap: widget.onTap, onTapDown: (_) => setState(() => _active = true), onTapUp: (_) => setState(() => _active = false), onTapCancel: () => setState(() => _active = false), child: AnimatedScale(scale: _active ? 1.05 : 1.0, duration: const Duration(milliseconds: 200), child: widget.child)));
  }
}
