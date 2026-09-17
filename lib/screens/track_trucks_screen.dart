import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size, Visibility;
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:geolocator/geolocator.dart' as geo;
import '../utils/app_theme.dart';
import '../widgets/fade_slide_entrance.dart';
import '../utils/custom_notification.dart';
import '../widgets/custom_snackbar.dart';
import '../utils/prediction_engine.dart';

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
  Map<String, dynamic> _liveLocations = {};
  
  String? _selectedTruckId;
  String? _followedTruckId;

  PointAnnotationManager? _pointAnnotationManager;
  final Map<String, PointAnnotation> _truckMarkers = {};
  bool _managersReady = false;

  final Map<String, StreamSubscription> _sharedRouteSubscriptions = {};
  final Map<String, String> _truckPlates = {}; // Cache for plate numbers
  final Map<String, String> _driverCurrentTrucks = {}; // driverId -> truckId
  StreamSubscription? _trucksMetaSubscription;
  StreamSubscription? _usersSubscription;

  final Map<String, List<Map<dynamic, dynamic>>> _lastRoutePoints = {}; 
  final Set<String> _visiblePaths = {};
  final Map<String, Position?> _sessionStartPoints = {};

  bool _truckLayersCreated = false;
  bool _isFollowLocked = false;
  bool _isMapActive = false;
  bool _isTargetActive = false;
  bool _isFleetPanelVisible = true;
  final Position _balintawakCenter = Position(121.1623, 13.9413);

  // Animation for Header Circles & Pulse Effect
  late AnimationController _circleController;
  late AnimationController _refreshRotationController;
  Timer? _pulseTimer;
  double _pulseRadius = 8.0;
  double _pulseOpacity = 0.5;
  double _pulseRadius2 = 8.0; 
  double _pulseOpacity2 = 0.3;
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
      if (locationsSnapshot.exists) {
        _liveLocations = Map<String, dynamic>.from(locationsSnapshot.value as Map);
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

      // 2. Reprocess merged data
      _processMergedTrucks();
      
      // 3. Force UI Feedback (Centered White Box)
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
    _circleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat();
    _refreshRotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _startPulseAnimation();
  }

  void _startPulseAnimation() {
    _pulseTimer?.cancel();
    _pulseTimer = Timer.periodic(const Duration(milliseconds: 35), (timer) {
      if (!mounted || mapboxMap == null) return;
      
      setState(() {
        _pulseRadius += 0.6;
        _pulseOpacity -= 0.015;
        if (_pulseRadius >= 28.0) {
          _pulseRadius = 8.0;
          _pulseOpacity = 0.6;
        }
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
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final sub in _sharedRouteSubscriptions.values) {
      sub.cancel();
    }
    _trucksMetaSubscription?.cancel();
    _usersSubscription?.cancel();
    _circleController.dispose();
    _refreshRotationController.dispose();
    _pulseTimer?.cancel();
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
      final trucksToClear = _sharedRouteSubscriptions.keys.where((id) => !activeTruckIds.contains(id)).toList();
      for (var id in trucksToClear) {
        _sharedRouteSubscriptions[id]?.cancel();
        _sharedRouteSubscriptions.remove(id);
        _clearSharedRoute(id);
      }
      for (var t in mergedList) {
        if (t['isOnline'] != true) continue;
        final String tid = t['truck_id'];
        final String? sid = t['current_session'];
        if (sid != null) {
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
    points.sort((a, b) => (a['timestamp'] as num).compareTo(b['timestamp'] as num));

    final String sourceId = "route-source-$truckId";
    final List<Map<String, dynamic>> features = [];

    // Filter/Smooth logic
    final List<Map<dynamic, dynamic>> filtered = [];
    if (points.isNotEmpty) {
      filtered.add(points.first);
      for (int i = 1; i < points.length; i++) {
        final prev = filtered.last;
        final curr = points[i];
        final double d = geo.Geolocator.distanceBetween((prev['lat'] ?? 0.0).toDouble(), (prev['lng'] ?? 0.0).toDouble(), (curr['lat'] ?? 0.0).toDouble(), (curr['lng'] ?? 0.0).toDouble());
        if (d > 5.0 || i == points.length - 1) filtered.add(curr);
      }
    }

    if (filtered.length >= 2) {
      for (int i = 1; i < filtered.length; i++) {
        final prev = filtered[i - 1];
        final curr = filtered[i];
        final String color = (curr['color'] ?? 'GREEN').toString().toUpperCase();
        features.add({
          "type": "Feature",
          "geometry": { "type": "LineString", "coordinates": [[(prev['lng'] ?? 0.0).toDouble(), (prev['lat'] ?? 0.0).toDouble()], [(curr['lng'] ?? 0.0).toDouble(), (curr['lat'] ?? 0.0).toDouble()]] },
          "properties": {"color": color}
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

  void _recenterToBalintawak() { mapboxMap?.setCamera(CameraOptions(center: Point(coordinates: _balintawakCenter), zoom: 14.5)); }
  void _focusOnTruck(Map<dynamic, dynamic> truck) {
    final double lat = (truck['latitude'] ?? 0.0).toDouble();
    final double lng = (truck['longitude'] ?? 0.0).toDouble();
    if (lat == 0 || lng == 0) return;
    mapboxMap?.setCamera(CameraOptions(center: Point(coordinates: Position(lng, lat)), zoom: 17.5));
  }

  void _onMapCreated(MapboxMap map) {
    mapboxMap = map;
    mapboxMap?.annotations.createPointAnnotationManager().then((manager) {
      if (mounted) setState(() { _pointAnnotationManager = manager; _managersReady = true; });
    });
  }

  void _onStyleLoaded(dynamic data) async {
    mapboxMap?.location.updateSettings(LocationComponentSettings(enabled: false, pulsingEnabled: false));
    mapboxMap?.compass.updateSettings(CompassSettings(position: OrnamentPosition.TOP_LEFT, marginTop: 200.0, marginLeft: 20.0));
    _updateTruckMarkers();
    _recenterToBalintawak();
  }

  bool _isUpdatingMarkers = false;
  void _updateTruckMarkers() async {
    if (mapboxMap == null || _isUpdatingMarkers) return;
    _isUpdatingMarkers = true;
    try {
      final activeTruckIds = <String>{};
      final List<Map<String, dynamic>> pulseFeatures = [];
      for (var truck in _trucks) {
        final double lat = (truck['latitude'] ?? 0.0).toDouble();
        final double lng = (truck['longitude'] ?? 0.0).toDouble();
        if (lat == 0 || lng == 0 || truck['isOnline'] != true) continue;
        final String tid = truck['truck_id'].toString();
        activeTruckIds.add(tid);
        final String status = (truck['status'] ?? "ACTIVE").toString().toUpperCase();
        final point = Point(coordinates: Position(lng, lat));
        int color = Colors.green.toARGB32();
        if (status == "IDLE" || status == "PAUSED") color = Colors.orange.toARGB32();
        if (status == "STOP" || status == "STOPPED" || status == "FULL") color = Colors.red.toARGB32();
        if (status == "COMPLETE" || status == "FINISHED" || status == "COMPLETED") color = Colors.blue.toARGB32();

        if (_managersReady && _pointAnnotationManager != null) {
          if (_truckMarkers.containsKey(tid)) {
            final marker = _truckMarkers[tid]!;
            marker.geometry = point; marker.textField = tid; marker.textColor = color;
            _pointAnnotationManager?.update(marker);
          } else {
            _pointAnnotationManager?.create(PointAnnotationOptions(geometry: point, textField: tid, textOffset: [0, 2.0], textColor: color, textSize: 12, iconSize: 0)).then((m) { if (m != null) _truckMarkers[tid] = m; });
          }
        }
        pulseFeatures.add({ "type": "Feature", "geometry": {"type": "Point", "coordinates": [lng, lat]}, "properties": {"status": status, "type": "TRUCK"} });
      }
      if (_managersReady && _pointAnnotationManager != null) {
        final offlineKeys = _truckMarkers.keys.where((id) => !activeTruckIds.contains(id)).toList();
        for (var key in offlineKeys) {
          final marker = _truckMarkers[key]!;
          _pointAnnotationManager?.delete(marker); _truckMarkers.remove(key);
        }
      }

      final style = mapboxMap!.style;
      final String sourceId = "trucks-live-location-source";
      if (!_truckLayersCreated) {
        try {
          await style.removeStyleLayer("trucks-marker-circle");
          await style.removeStyleLayer("trucks-pulse-layer");
          await style.removeStyleSource(sourceId);
        } catch (_) {}
        await style.addSource(GeoJsonSource(id: sourceId, data: jsonEncode({"type": "FeatureCollection", "features": pulseFeatures})));
        final statusColorExpr = ["match", ["get", "status"], "IDLE", Colors.orange.toARGB32(), "PAUSED", Colors.orange.toARGB32(), "STOP", Colors.red.toARGB32(), "STOPPED", Colors.red.toARGB32(), "FULL", Colors.red.toARGB32(), "COMPLETE", Colors.blue.toARGB32(), "FINISHED", Colors.blue.toARGB32(), "COMPLETED", Colors.blue.toARGB32(), Colors.green.toARGB32()];
        await style.addLayer(CircleLayer(id: "trucks-pulse-layer", sourceId: sourceId, circleRadius: _pulseRadius, circleColor: Colors.green.toARGB32(), circleOpacity: _pulseOpacity, circleSortKey: 200.0));
        await style.setStyleLayerProperty("trucks-pulse-layer", "circle-color", statusColorExpr);
        await style.addLayer(CircleLayer(id: "trucks-marker-circle", sourceId: sourceId, circleRadius: 8.0, circleColor: Colors.green.toARGB32(), circleStrokeWidth: 3.0, circleStrokeColor: Colors.white.toARGB32(), circleSortKey: 2000.0));
        await style.setStyleLayerProperty("trucks-marker-circle", "circle-color", statusColorExpr);
        if (mounted) setState(() => _truckLayersCreated = true);
      } else {
        await style.setStyleSourceProperty(sourceId, "data", jsonEncode({"type": "FeatureCollection", "features": pulseFeatures}));
      }
    } catch (e) { debugPrint("GIS Render Error: $e"); } finally { _isUpdatingMarkers = false; }
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
              onMapCreated: _onMapCreated,
              onStyleLoadedListener: _onStyleLoaded,
              viewport: CameraViewportState(center: Point(coordinates: _balintawakCenter), zoom: 14.5),
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
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 30, spreadRadius: 5, offset: const Offset(-10, 0))],
                  border: Border.all(color: Colors.white.withOpacity(0.6), width: 1.5),
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
    return Stack(children: [
      Positioned.fill(child: Stack(children: [
        Positioned.fill(child: MapWidget(onMapCreated: _onMapCreated, onStyleLoadedListener: _onStyleLoaded, viewport: CameraViewportState(center: Point(coordinates: _balintawakCenter), zoom: 14.5))),
        _buildMapControls(bottom: 200),
      ])),
      _buildFloatingHeader(),
      _buildDebugOverlay(),
      Positioned.fill(child: DraggableScrollableSheet(
        initialChildSize: 0.22, minChildSize: 0.22, maxChildSize: 0.95, snap: true, snapSizes: const [0.22, 0.5, 0.95],
        builder: (context, scrollController) => PointerInterceptor(child: _buildFleetStatusContent(scrollController, isMobile: true))))
    ]);
  }

  Widget _buildCornerHeader() {
    return Positioned(
      top: 24, left: 24,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(24), boxShadow: AppTheme.pulidongShadow, border: Border.all(color: Colors.white, width: 2)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          const Text("Fleet GIS Tracking", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            const Text("Real-time telemetry and monitoring", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
        ]),
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
    final bool isDesktop = MediaQuery.of(context).size.width >= 900;
    return Positioned(
      top: isDesktop ? 125 : 80, left: isDesktop ? 24 : 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
        _buildMapControlButton(icon: _isFollowLocked ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded, isActive: _isFollowLocked || _isTargetActive, size: btnSize, iconSize: iconSize, onTap: () {
          setState(() { _isFollowLocked = !_isFollowLocked; _isTargetActive = true; });
          if (_isFollowLocked && _trucks.isNotEmpty) _focusOnTruck(_trucks.first); // Default to first for admin
          Future.delayed(const Duration(seconds: 2), () { if (mounted) setState(() => _isTargetActive = false); });
        }),
        const SizedBox(height: 12),
        _buildMapControlButton(icon: Icons.map_outlined, isActive: _isMapActive, size: btnSize, iconSize: iconSize, onTap: () { setState(() => _isMapActive = true); _recenterToBalintawak(); Future.delayed(const Duration(seconds: 2), () { if (mounted) setState(() => _isMapActive = false); }); }),
      ]),
    );
  }

  Widget _buildMapControlButton({required IconData icon, required bool isActive, required double size, required double iconSize, required VoidCallback onTap}) {
    return StatefulBuilder(builder: (context, setInnerState) {
      bool isHovered = false;
      return MouseRegion(onEnter: (_) => setInnerState(() => isHovered = true), onExit: (_) => setInnerState(() => isHovered = false), cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: AnimatedContainer(duration: const Duration(milliseconds: 200), width: size, height: size, decoration: BoxDecoration(color: isActive ? const Color(0xFF00796B) : (isHovered ? const Color(0xFFE0F2F1) : Colors.white), shape: BoxShape.circle, boxShadow: AppTheme.pulidongShadow, border: Border.all(color: isActive ? const Color(0xFF00796B) : (isHovered ? const Color(0xFF00796B).withOpacity(0.3) : Colors.transparent), width: 1.5)), child: Icon(icon, color: isActive ? Colors.white : (isHovered ? const Color(0xFF00796B) : const Color(0xFF1A1A1A)), size: iconSize))));
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
    final List<Widget> items = sortedTrucks.isEmpty ? [const Padding(padding: EdgeInsets.all(60), child: Center(child: Text("Scanning for active units...", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500))))] : sortedTrucks.map((truck) => _buildOrganizedTruckCard(truck)).toList();
    
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
                minHeight: 110,
                maxHeight: 110,
                child: Container(
                  color: Colors.white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      // Drag Handle (Still centered)
                      Align(
                        alignment: Alignment.center,
                        child: Container(
                          width: 50,
                          height: 6,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Header Title (Left aligned)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Active Fleet Status", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
                            SizedBox(height: 4),
                            Text("Real-time updates on active units", style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
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
    final String tid = truck['truck_id'].toString();
    final String license = (truck['license_number'] ?? 'N/A').toString();
    final String driver = (truck['driver_name'] ?? 'Driver').toString();
    final String status = (truck['status'] ?? 'IDLE').toString().toUpperCase();
    final bool isActive = status == 'ACTIVE' || status == 'COLLECTING';
    final Color statusColor = isActive ? const Color(0xFF00796B) : Colors.grey.shade400;

    final double speed = (truck['speed'] ?? 0.0).toDouble();
    final double dist = double.tryParse(truck['distance_covered']?.toString() ?? "0.0") ?? 0.0;
    final double fuel = (truck['fuel_level'] ?? 0.0).toDouble();
    final int stops = (truck['stops_count'] ?? 0) as int;
    final bool isPathVisible = _visiblePaths.contains(tid);

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
                (truck['purok'] ?? "Balintawak").toString()),
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
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade100)),
                            child: Row(children: [
                              Container(width: 8, height: 8, decoration: BoxDecoration(color: (point['color'] == 'PINK' ? Colors.pink : const Color(0xFF00796B)), shape: BoxShape.circle)),
                              const SizedBox(width: 16),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text("At ${point['purok'] ?? 'Balintawak'}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
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
    return GestureDetector(onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(vertical: 14), decoration: BoxDecoration(gradient: LinearGradient(colors: [color.withOpacity(0.8), color]), borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: color.withAlpha(60), blurRadius: 10, offset: const Offset(0, 4))]), alignment: Alignment.center, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: Colors.white, size: 16), const SizedBox(width: 8), Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12))])));
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

  @override
  double get minExtent => minHeight;

  @override
  bool shouldRebuild(_StickyHeaderDelegate oldDelegate) {
    return maxHeight != oldDelegate.maxHeight ||
        minHeight != oldDelegate.minHeight ||
        child != oldDelegate.child;
  }
}
