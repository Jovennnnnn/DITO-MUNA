import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size, Visibility;
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:intl/intl.dart';
import '../utils/app_theme.dart';
import '../utils/session_manager.dart';
import '../models/user.dart';
import '../widgets/fade_slide_entrance.dart';

class DriverTrackTruckScreen extends StatefulWidget {
  final bool isEmbedded;
  final VoidCallback? onBack;
  final String? currentSessionId;
  final String? focusTruckId;
  final geo.Position? manualPosition;
  final bool isSimulation;
  final List<Map>? testRoute; 
  final bool isHistorical; 
  final bool isMiniMap;
  final double? currentDistance;
  final double? currentSpeed;
  final String? startTime;

  final DateTime? lastGpsUpdateTime;
  final VoidCallback? onOptimize;
  final bool isOptimizing;
  
  const DriverTrackTruckScreen({
    super.key, 
    this.isEmbedded = false, 
    this.onBack,
    this.currentSessionId,
    this.focusTruckId,
    this.manualPosition,
    this.isSimulation = false,
    this.testRoute,
    this.isHistorical = false,
    this.isMiniMap = false,
    this.currentDistance,
    this.currentSpeed,
    this.startTime,
    this.lastGpsUpdateTime,
    this.onOptimize,
    this.isOptimizing = false,
  });




  @override
  State<DriverTrackTruckScreen> createState() => _DriverTrackTruckScreenState();
}

class _DriverTrackTruckScreenState extends State<DriverTrackTruckScreen> with TickerProviderStateMixin {
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  final FirebaseDatabase _database = FirebaseDatabase.instance;


  MapboxMap? mapboxMap;
  UserData? _user;
  
  PointAnnotationManager? _pointAnnotationManager;
  
  final Map<String, PointAnnotation> _truckMarkers = {};
  List<Map> _lastPoints = [];
  StreamSubscription? _truckSubscription;
  StreamSubscription? _userSubscription;
  StreamSubscription? _routeSubscription;
  StreamSubscription? _routeMetaSubscription;
  StreamSubscription? _localGpsSubscription;
  StreamSubscription? _optimizedRouteSubscription;
  
  Map<dynamic, dynamic>? _lastTruckData;
  geo.Position? _lastLocalPos;

  final Position _balintawakCenter = Position(121.1623, 13.9413);

  bool _managersReady = false;
  bool _driverSourceCreated = false;
  bool _routeSourceCreated = false;
  bool _optimizedRouteSourceCreated = false;
  bool _specialMarkersCreated = false;
  bool _optimizedMarkersCreated = false;
  
  // LIVE DRIVER MARKERS
  PointAnnotation? _liveDriverLabel;

  // Session Meta Persistence
  Map? _lastSessionData;
  Map? _optimizedRouteData;

  // Follow Mode State
  bool _isFollowLocked = true;
  bool _isTargetActive = false;
  bool _isMapActive = false;
  String _currentStatus = "ACTIVE";
  String? _truckPlateNumber;
  StreamSubscription? _truckMetaSubscription;

  // Modal Info State
  String _startTime = "--:--";
  double _distance = 0.0;
  double _currentSpeed = 0.0;

  // Refresh Animation State
  bool _isRefreshing = false;
  late AnimationController _refreshRotationController;

  DateTime? _lastGpsUpdateTime;
  String _currentTime = "";

  Timer? _clockTimer;

  bool _isFleetPanelVisible = true;
  bool _isDataLoading = true;
  bool _isDataExpanded = false;

  @override
  void initState() {
    super.initState();
    _refreshRotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _loadUser();
    if (!widget.isHistorical) {
      _startClock();
    }
    if (widget.manualPosition != null) {
      _lastLocalPos = widget.manualPosition;
    }
    if (widget.currentDistance != null) _distance = widget.currentDistance!;
    if (widget.currentSpeed != null) _currentSpeed = widget.currentSpeed!;
    if (widget.startTime != null) _startTime = widget.startTime!;
    if (widget.lastGpsUpdateTime != null) _lastGpsUpdateTime = widget.lastGpsUpdateTime!;

    if (!widget.isHistorical) {



      _checkPermissionAndStartGps();
      _listenToTrucks();
    }
    _listenToTruckMeta();
    _listenToRoute();

    // Initial Data Loading Animation (Match Resident Experience)
    _isDataLoading = true;
    _isDataExpanded = false;
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) {
        setState(() {
          _isDataLoading = false;
          Future.delayed(const Duration(milliseconds: 50), () => setState(() => _isDataExpanded = true));
        });
      }
    });
  }

  void _loadUser() async {
    _user = await SessionManager.getUser();
    if (mounted) {
      setState(() {});
      _listenToTruckMeta();
    }
    _setupUserListener();
  }

  void _handleManualRefresh() async {
    if (_isRefreshing) return;
    
    setState(() => _isRefreshing = true);
    _refreshRotationController.repeat();
    
    try {
      // 1. Force re-load metadata
      _listenToTruckMeta();
      
      // 2. Clear and re-fetch markers/layers
      if (_managersReady) {
        _pointAnnotationManager?.deleteAll();
        _truckMarkers.clear();
        _driverSourceCreated = false;
        _routeSourceCreated = false;
        _specialMarkersCreated = false;
      }

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
                      Text("Map tracking synchronized", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF1A1A1A))),
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

  void _setupUserListener() {
    if (_user == null) return;
    _userSubscription?.cancel();
    _userSubscription = _database.ref('users/${_user!.userId}').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map data = event.snapshot.value as Map;
        if (mounted) {
          setState(() {
            final Map<String, dynamic> currentData = _user!.toJson();
            data.forEach((k, v) => currentData[k] = v);
            _user = UserData.fromJson(currentData);
          });
          _listenToTruckMeta(); // Refresh plate number if assignment changed
          if (_lastLocalPos != null) _updateLocalDriverMarker(_lastLocalPos!);
          
          // Refresh other truck markers with the new user context
          if (_managersReady && _lastTruckData != null) {
            _lastTruckData!.forEach((k, v) => _updateSingleTruckMarker(k.toString(), v as Map));
          }
        }
      }
    });
  }

  void _startClock() {
    _updateTime();
    _clockTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      _updateTime();
    });
  }

  void _updateTime() {
    final String time = DateFormat('hh:mm:ss a').format(DateTime.now());
    if (mounted && _currentTime != time) {
      setState(() => _currentTime = time);
    }
  }

  @override
  void didUpdateWidget(DriverTrackTruckScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusTruckId != widget.focusTruckId) {
      _listenToTrucks();
      _listenToTruckMeta();
    }
    if (oldWidget.currentSessionId != widget.currentSessionId) {
      _listenToRoute();
    }
    if (oldWidget.manualPosition != widget.manualPosition && widget.manualPosition != null) {
      _lastLocalPos = widget.manualPosition;
      _updateLocalDriverMarker(widget.manualPosition!);
    }
    if (oldWidget.currentDistance != widget.currentDistance && widget.currentDistance != null) {
      setState(() => _distance = widget.currentDistance!);
    }
    if (oldWidget.currentSpeed != widget.currentSpeed && widget.currentSpeed != null) {
      setState(() => _currentSpeed = widget.currentSpeed!);
    }
    if (oldWidget.startTime != widget.startTime && widget.startTime != null) {
      setState(() => _startTime = widget.startTime!);
    }
    if (oldWidget.lastGpsUpdateTime != widget.lastGpsUpdateTime && widget.lastGpsUpdateTime != null) {
      setState(() => _lastGpsUpdateTime = widget.lastGpsUpdateTime!);
    }
  }



  void _listenToTruckMeta() {
    _truckMetaSubscription?.cancel();
    final String? currentAssignedTruck = _user?.preferredTruck;
    final String tid = (widget.focusTruckId ?? currentAssignedTruck ?? "Unknown").toUpperCase();
    
    _truckMetaSubscription = _database.ref('trucks/$tid').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final data = event.snapshot.value as Map;
        if (mounted) {
          setState(() {
            _truckPlateNumber = data['plateNumber']?.toString();
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _refreshRotationController.dispose();
    _clockTimer?.cancel();

    _truckSubscription?.cancel();
    _userSubscription?.cancel();
    _truckMetaSubscription?.cancel();
    _routeSubscription?.cancel();
    _optimizedRouteSubscription?.cancel();
    _routeMetaSubscription?.cancel();
    _localGpsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkPermissionAndStartGps() async {
    geo.LocationPermission permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }
    if (permission == geo.LocationPermission.denied || permission == geo.LocationPermission.deniedForever) {
      return;
    }

    try {
      geo.Position pos = await geo.Geolocator.getCurrentPosition(desiredAccuracy: geo.LocationAccuracy.high);
      if (mounted) {
        setState(() { 
          _lastLocalPos = pos;
          _currentSpeed = pos.speed * 3.6; 
        });
      }
      _updateLocalDriverMarker(pos);
    } catch (e) {}

    _localGpsSubscription = geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(accuracy: geo.LocationAccuracy.bestForNavigation, distanceFilter: 0),
    ).listen((pos) {
      if (widget.isSimulation) return;
      if (mounted) {
        setState(() { 
          _lastLocalPos = pos;
          _currentSpeed = pos.speed * 3.6;
        });
      }
      _updateLocalDriverMarker(pos);
    });
  }

  void _listenToTrucks() {
    _truckSubscription?.cancel();
    _truckSubscription = _database.ref('truck_locations').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        _lastTruckData = event.snapshot.value as Map;
        
        // DEBUG STALE RECORDS
        bool oldGT001Found = _lastTruckData!.containsKey("GT-001");
        bool gt007Found = _lastTruckData!.containsKey("GT-007");
        debugPrint("LIVE RECORDS FOR DRIVER: ${_lastTruckData!.keys.toList()}");
        debugPrint("OLD GT-001 LIVE RECORD FOUND: $oldGT001Found");
        debugPrint("GT-007 LIVE RECORD FOUND: $gt007Found");

        final String tid = (widget.focusTruckId ?? _user?.preferredTruck ?? "Unknown").toUpperCase();
        if (_lastTruckData!.containsKey(tid)) {
          final myData = _lastTruckData![tid] as Map;
          debugPrint("SELECTED CURRENT LIVE RECORD: $tid -> $myData");
          final String newStatus = (myData['status'] ?? "ACTIVE").toString().toUpperCase();
          if (newStatus != _currentStatus) {
            if (mounted) setState(() => _currentStatus = newStatus);
            if (_lastLocalPos != null) _updateLocalDriverMarker(_lastLocalPos!);
          }
        }

        if (_managersReady) {
          _lastTruckData!.forEach((key, value) {
            _updateSingleTruckMarker(key.toString(), value as Map);
          });
        }
      }
    });
  }

  void _listenToRoute() {
    if (widget.currentSessionId == null) return;
    _routeSubscription?.cancel();
    _routeSubscription = _database.ref('driver_routes/${widget.currentSessionId}').onValue.listen((event) {
      if (widget.testRoute != null) return; 
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map data = event.snapshot.value as Map;
        _lastSessionData = data;

        if (mounted) {
          setState(() {
            if (data['start_time'] != null) _startTime = data['start_time'];
            if (data['final_distance'] != null) {
              _distance = (data['final_distance'] as num).toDouble();
            } else if (data['total_distance'] != null) {
              _distance = (data['total_distance'] as num).toDouble();
            }
          });
        }

        if (data['route'] != null) {
          final Map routeData = data['route'] as Map;
          final List<Map> points = [];
          routeData.forEach((key, value) => points.add(value as Map));
          
          points.sort((a, b) => (a['timestamp'] ?? 0).compareTo(b['timestamp'] ?? 0));
          
          if (mounted && points.isNotEmpty) {
            if (points.length != _lastPoints.length) {
              _updateRoutePolyline(points);
              
              if (widget.isHistorical && _lastPoints.isEmpty) {
                _fitHistoricalRoute(points);
              }
            }
            
            // PRIORITY: Use Firebase route points for historical polyline rendering,
            // but NEVER overwrite the current Driver marker with potentially stale Firebase data.
            // Local GPS stream handles real-time marker movement for minimal delay.
            
            _lastPoints = points;
          }
        }
        if (_managersReady) _updateSpecialMarkers(data);
      }
    });

    _optimizedRouteSubscription?.cancel();
    _optimizedRouteSubscription = _database.ref('driver_routes/${widget.currentSessionId}/optimized_route').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map data = event.snapshot.value as Map;
        if (mounted) {
          setState(() {
            _optimizedRouteData = data;
          });
          if (_managersReady) {
            _updateOptimizedRouteLayer(data);
            _updateOptimizedMarkers(data);
            
            // Only fit camera if this is the first time loading the optimized route
            // or if it was explicitly triggered.
            _fitMapToOptimizedRoute(data);
          }
        }
      } else {
        if (mounted) {
          setState(() => _optimizedRouteData = null);
          _clearOptimizedRoute();
        }
      }
    });
  }

  void _fitMapToOptimizedRoute(Map data) async {
    if (data['stops'] == null || mapboxMap == null) return;
    final List stops = data['stops'] as List;
    if (stops.isEmpty) return;

    final List<Point> points = [];
    
    // Include current position in bounds
    if (_lastLocalPos != null) {
      points.add(Point(coordinates: Position(_lastLocalPos!.longitude, _lastLocalPos!.latitude)));
    }

    for (var s in stops) {
      double lat = (s['latitude'] ?? 0.0).toDouble();
      double lng = (s['longitude'] ?? 0.0).toDouble();
      if (lat != 0 && lng != 0) {
        points.add(Point(coordinates: Position(lng, lat)));
      }
    }
    
    if (points.isNotEmpty) {
      final camera = await mapboxMap!.cameraForCoordinates(
        points, 
        MbxEdgeInsets(top: 80, left: 50, bottom: 250, right: 50), // Standard padding for mobile UI
        0, 0
      );
      
      mapboxMap?.setCamera(camera);
    }
  }

  void _onMapCreated(MapboxMap map) { mapboxMap = map; }

  void _onStyleLoaded(dynamic data) async {
    _driverSourceCreated = false;
    _routeSourceCreated = false;
    _specialMarkersCreated = false;

    try {
      await mapboxMap?.location.updateSettings(LocationComponentSettings(enabled: false, pulsingEnabled: false));
    } catch (e) {}
    await mapboxMap?.setCamera(CameraOptions(center: Point(coordinates: _balintawakCenter), zoom: 14.5));
    try {
      await Future.delayed(const Duration(milliseconds: 800));
      _pointAnnotationManager = await mapboxMap!.annotations.createPointAnnotationManager();
    } catch (e) {}
    if (!mounted) return;
    _truckMarkers.clear();
    
    _liveDriverLabel = null;

    setState(() => _managersReady = true);
    
    if (_lastLocalPos != null) _updateLocalDriverMarker(_lastLocalPos!);
    if (_lastTruckData != null) _lastTruckData!.forEach((k, v) => _updateSingleTruckMarker(k.toString(), v as Map));
    if (_lastPoints.isNotEmpty) _updateRoutePolyline(_lastPoints);
    if (_lastSessionData != null) _updateSpecialMarkers(_lastSessionData!);
    if (_optimizedRouteData != null) {
      _updateOptimizedRouteLayer(_optimizedRouteData!);
      _updateOptimizedMarkers(_optimizedRouteData!);
    }
  }

  Future<void> _updateLocalDriverMarker(geo.Position pos) async {
    if (widget.isHistorical) return;
    if (mapboxMap == null) return;

    final String sourceId = "driver-live-location-source";
    
    // DELAY DEBUG LOGS
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int gpsTs = pos.timestamp.millisecondsSinceEpoch;
    final int localDelay = now - gpsTs;

    debugPrint("--- REAL-TIME GPS UPDATE ---");
    debugPrint("GPS POSITION: ${pos.latitude}, ${pos.longitude}");
    debugPrint("GPS TIMESTAMP: ${pos.timestamp}");
    debugPrint("MARKER UPDATE TIME: ${DateTime.now()}");
    debugPrint("LOCAL DELAY: $localDelay ms");
    debugPrint("FOLLOW MODE ACTIVE: $_isFollowLocked");
    
    // Resolve identity info with priority
    // 1. Current Driver assignedTruckId (preferredTruck)
    // 2. Current active trip truckId (from _lastSessionData)
    // 3. Focus Truck ID (if valid)
    
    final String driverName = (_user?.name != null && _user!.name.trim().isNotEmpty) ? _user!.name : "DRIVER";
    String? currentAssignedTruckId = _user?.preferredTruck;
    String? tripTruckId = _lastSessionData?['truck_id']?.toString();
    String? focusTruckId = (widget.focusTruckId != null && widget.focusTruckId!.toUpperCase() != "UNKNOWN") ? widget.focusTruckId : null;
    
    // AUTHORITATIVE RESOLUTION
    String resolvedTruckId = currentAssignedTruckId ?? focusTruckId ?? tripTruckId ?? "N/A";
    
    if (resolvedTruckId.toUpperCase() == "UNKNOWN") {
      resolvedTruckId = "N/A";
    }

    final String labelText = "$driverName\n${resolvedTruckId.toUpperCase()}";
    
    // DEBUG LOGS
    debugPrint("==================================================");
    debugPrint("DRIVER: $driverName");
    debugPrint("CURRENT DRIVER ID: ${_user?.userId}");
    debugPrint("assignedTruckId (preferred): $currentAssignedTruckId");
    debugPrint("TRUCK DOC (tid used for meta): ${(widget.focusTruckId ?? currentAssignedTruckId ?? "Unknown").toUpperCase()}");
    debugPrint("ACTIVE TRIP truckId: $tripTruckId");
    debugPrint("WIDGET focusTruckId: ${widget.focusTruckId}");
    debugPrint("FINAL DISPLAY TRUCK ID: $resolvedTruckId");
    debugPrint("NUMBER OF OTHER TRUCK MARKERS: ${_truckMarkers.length}");
    debugPrint("==================================================");

    final geojson = {
      "type": "FeatureCollection",
      "features": [
        {
          "type": "Feature", 
          "geometry": {"type": "Point", "coordinates": [pos.longitude, pos.latitude]}, 
          "properties": {
            "name": "DRIVER", 
            "label": labelText,
            "status": _currentStatus
          }
        }
      ]
    };

    try {
      final style = mapboxMap!.style;
      bool sourceExists = await style.styleSourceExists(sourceId);
      
      if (!_driverSourceCreated || !sourceExists) {
        if (!sourceExists) {
          await style.addSource(GeoJsonSource(id: sourceId, data: jsonEncode(geojson)));
        }

        if (!(await style.styleLayerExists("driver-live-location-halo"))) {
          await style.addLayer(CircleLayer(
            id: "driver-live-location-halo", 
            sourceId: sourceId, 
            circleRadius: 18.0, 
            circleOpacity: 0.3,
            circleStrokeWidth: 2.0,
            circleSortKey: 3100.0
          ));
        }

        if (!(await style.styleLayerExists("driver-live-location-circle"))) {
          await style.addLayer(CircleLayer(
            id: "driver-live-location-circle", 
            sourceId: sourceId, 
            circleRadius: 8.0, 
            circleColor: Colors.green.toARGB32(), 
            circleStrokeWidth: 3.0, 
            circleStrokeColor: Colors.white.toARGB32(), 
            circleSortKey: 3200.0
          ));
        }

        if (!(await style.styleLayerExists("driver-live-location-label"))) {
          await style.addLayer(SymbolLayer(
            id: "driver-live-location-label", 
            sourceId: sourceId, 
            textField: "{label}",
            textSize: 14.0, 
            textColor: Colors.green.toARGB32(), 
            textHaloColor: Colors.white.toARGB32(), 
            textHaloWidth: 2.0, 
            textAnchor: TextAnchor.BOTTOM, 
            textOffset: [0, -1.5], 
            symbolSortKey: 3300.0,
            textAllowOverlap: true
          ));
        }

        final statusColorExpression = [
          "match", ["get", "status"],
          "IDLE", "#FFFF00",
          "FULL", "#FF1493",
          "FINISHED", "#000000",
          "#00FF00" 
        ];

        await style.setStyleLayerProperty("driver-live-location-halo", "circle-color", statusColorExpression);
        await style.setStyleLayerProperty("driver-live-location-halo", "circle-stroke-color", statusColorExpression);

        if (mounted) setState(() => _driverSourceCreated = true);
      } else {
        await style.setStyleSourceProperty(sourceId, "data", jsonEncode(geojson));
      }

      // ENSURE CAMERA FOLLOWS IF LOCKED - Applied immediately after source update
      if (_isFollowLocked) {
        mapboxMap?.setCamera(CameraOptions(center: Point(coordinates: Position(pos.longitude, pos.latitude))));
      }
    } catch (e) {}
  }

  void _updateSpecialMarkers(Map data) async {
    if (mapboxMap == null) return;
    final String sourceId = "driver-special-markers-source";
    final List<Map<String, dynamic>> features = [];

    if (data['start_lat'] != null && data['start_lng'] != null) {
      features.add({
        "type": "Feature",
        "geometry": {"type": "Point", "coordinates": [data['start_lng'], data['start_lat']]},
        "properties": {"label": "START POINT", "type": "START"}
      });
    }
    if (data['finish_lat'] != null && data['finish_lng'] != null) {
      features.add({
        "type": "Feature",
        "geometry": {"type": "Point", "coordinates": [data['finish_lng'], data['finish_lat']]},
        "properties": {"label": "🏁 FINISH", "type": "FINISH"}
      });
    }

    if (features.isEmpty) return;
    final geojson = {"type": "FeatureCollection", "features": features};

    try {
      final style = mapboxMap!.style;
      bool sourceExists = await style.styleSourceExists(sourceId);
      
      if (!sourceExists) {
        await style.addSource(GeoJsonSource(id: sourceId, data: jsonEncode(geojson)));
        
        if (!(await style.styleLayerExists("driver-special-circles"))) {
          await style.addLayer(CircleLayer(
            id: "driver-special-circles", sourceId: sourceId, 
            circleRadius: 8.0, circleStrokeWidth: 3.0, circleStrokeColor: Colors.white.toARGB32(),
            circleSortKey: 3000.0,
          ));
          await style.setStyleLayerProperty("driver-special-circles", "circle-color", 
            ["match", ["get", "type"], "START", "#2196F3", "#000000"] 
          );
        }
        if (!(await style.styleLayerExists("driver-special-labels"))) {
          await style.addLayer(SymbolLayer(
            id: "driver-special-labels", sourceId: sourceId, 
            textField: "{label}", textSize: 12.0, textHaloColor: Colors.white.toARGB32(), textHaloWidth: 2.5,
            textAnchor: TextAnchor.TOP, textOffset: [0, 1.0], symbolSortKey: 3010.0,
          ));
          await style.setStyleLayerProperty("driver-special-labels", "text-color", 
            ["match", ["get", "type"], "START", "#1976D2", "#000000"]
          );
        }
        if (mounted) setState(() => _specialMarkersCreated = true);
      } else {
        await style.setStyleSourceProperty(sourceId, "data", jsonEncode(geojson));
      }
    } catch (e) {}
  }

  void _fitHistoricalRoute(List<Map> points) async {
    if (points.isEmpty || mapboxMap == null) return;
    
    double? minLat, maxLat, minLng, maxLng;
    for (var p in points) {
      double lat = (p['lat'] ?? 0.0).toDouble();
      double lng = (p['lng'] ?? 0.0).toDouble();
      if (lat == 0 || lng == 0) continue;
      
      if (minLat == null || lat < minLat) minLat = lat;
      if (maxLat == null || lat > maxLat) maxLat = lat;
      if (minLng == null || lng < minLng) minLng = lng;
      if (maxLng == null || lng > maxLng) maxLng = lng;
    }
    
    if (minLat != null && maxLat != null && minLng != null && maxLng != null) {
      if (_lastSessionData != null && _lastSessionData!['start_lat'] != null) {
         double sLat = (_lastSessionData!['start_lat'] as num).toDouble();
         double sLng = (_lastSessionData!['start_lng'] as num).toDouble();
         if (sLat < minLat) minLat = sLat;
         if (sLat > maxLat) maxLat = sLat;
         if (sLng < minLng) minLng = sLng;
         if (sLng > maxLng) maxLng = sLng;
      }

      final centerLat = (minLat + maxLat) / 2;
      final centerLng = (minLng + maxLng) / 2;
      
      mapboxMap?.setCamera(CameraOptions(
        center: Point(coordinates: Position(centerLng, centerLat)),
        zoom: 14.5,
      ));
    }
  }

  void _updateOptimizedRouteLayer(Map data) async {
    if (mapboxMap == null || data['geometry'] == null) return;
    final String sourceId = "optimized-route-source";
    
    try {
      final style = mapboxMap!.style;
      final geometry = jsonDecode(data['geometry'] as String);
      final geojson = {
        "type": "Feature",
        "geometry": geometry,
        "properties": {}
      };

      bool sourceExists = await style.styleSourceExists(sourceId);
      if (!sourceExists) {
        await style.addSource(GeoJsonSource(id: sourceId, data: jsonEncode(geojson)));
        if (!(await style.styleLayerExists("optimized-route-layer"))) {
          await style.addLayer(LineLayer(
            id: "optimized-route-layer",
            sourceId: sourceId,
            lineColor: Colors.blue.toARGB32(),
            lineWidth: 6.0,
            lineOpacity: 0.8,
            lineCap: LineCap.ROUND,
            lineJoin: LineJoin.ROUND,
            lineDasharray: [1.5, 1.5],
          ));
        }
        if (mounted) setState(() => _optimizedRouteSourceCreated = true);
      } else {
        await style.setStyleSourceProperty(sourceId, "data", jsonEncode(geojson));
      }
    } catch (e) {}
  }

  void _updateOptimizedMarkers(Map data) async {
    if (mapboxMap == null || data['stops'] == null) return;
    final String sourceId = "optimized-stops-source";
    final List stops = data['stops'] as List;
    
    final List<Map<String, dynamic>> features = [];
    for (int i = 0; i < stops.length; i++) {
      final s = stops[i];
      features.add({
        "type": "Feature",
        "geometry": {"type": "Point", "coordinates": [s['longitude'], s['latitude']]},
        "properties": {
          "label": "${s['sequence']}",
          "name": s['area_name']
        }
      });
    }

    final geojson = {"type": "FeatureCollection", "features": features};

    try {
      final style = mapboxMap!.style;
      bool sourceExists = await style.styleSourceExists(sourceId);
      
      if (!sourceExists) {
        await style.addSource(GeoJsonSource(id: sourceId, data: jsonEncode(geojson)));
        
        if (!(await style.styleLayerExists("optimized-stops-circles"))) {
          await style.addLayer(CircleLayer(
            id: "optimized-stops-circles", sourceId: sourceId, 
            circleRadius: 10.0, circleColor: Colors.blue.toARGB32(), 
            circleStrokeWidth: 2.0, circleStrokeColor: Colors.white.toARGB32(),
            circleSortKey: 4000.0,
          ));
        }
        if (!(await style.styleLayerExists("optimized-stops-labels"))) {
          await style.addLayer(SymbolLayer(
            id: "optimized-stops-labels", sourceId: sourceId, 
            textField: "{label}", textSize: 10.0, textColor: Colors.white.toARGB32(),
            textAnchor: TextAnchor.CENTER, symbolSortKey: 4100.0,
          ));
        }
        if (!(await style.styleLayerExists("optimized-stops-names"))) {
          await style.addLayer(SymbolLayer(
            id: "optimized-stops-names", sourceId: sourceId, 
            textField: "{name}", textSize: 9.0, textColor: Colors.blue.toARGB32(),
            textHaloColor: Colors.white.toARGB32(), textHaloWidth: 1.5,
            textAnchor: TextAnchor.TOP, textOffset: [0, 1.2], symbolSortKey: 4200.0,
          ));
        }
        if (mounted) setState(() => _optimizedMarkersCreated = true);
      } else {
        await style.setStyleSourceProperty(sourceId, "data", jsonEncode(geojson));
      }
    } catch (e) {}
  }

  void _clearOptimizedRoute() async {
    if (mapboxMap == null) return;
    try {
      final style = mapboxMap!.style;
      if (await style.styleSourceExists("optimized-route-source")) {
        await style.setStyleSourceProperty("optimized-route-source", "data", jsonEncode({"type": "FeatureCollection", "features": []}));
      }
      if (await style.styleSourceExists("optimized-stops-source")) {
        await style.setStyleSourceProperty("optimized-stops-source", "data", jsonEncode({"type": "FeatureCollection", "features": []}));
      }
    } catch (e) {}
  }

  void _updateSingleTruckMarker(String id, Map data) {
    if (!_managersReady || _pointAnnotationManager == null) return;
    
    // DEDUPLICATION: Do not render markers for the CURRENT driver or CURRENT truck
    final String currentDriverId = _user?.userId.toString() ?? "";
    final String recordDriverId = data['driver_id']?.toString() ?? "";
    
    final String truckId = (data['truck_id'] ?? id).toString().toUpperCase();
    final String targetId = (widget.focusTruckId ?? "Unknown").toUpperCase();
    final String assignedTruckId = (_user?.preferredTruck ?? "").toUpperCase();

    bool isCurrentDriver = (currentDriverId.isNotEmpty && recordDriverId == currentDriverId);
    bool isCurrentTruck = (truckId == targetId || (assignedTruckId.isNotEmpty && truckId == assignedTruckId));

    // DEBUG LOGS FOR DEDUPLICATION
    if (truckId.contains("GT-001") || truckId.contains("GT-007")) {
      debugPrint("DEDUPLICATION CHECK [$id / $truckId]: isCurrentDriver=$isCurrentDriver (Rec:$recordDriverId vs Cur:$currentDriverId), isCurrentTruck=$isCurrentTruck (Rec:$truckId vs Target:$targetId or Assigned:$assignedTruckId)");
    }

    if (isCurrentDriver || isCurrentTruck) {
      // If it's a stale record for the current driver/truck, REMOVE it from the map
      if (_truckMarkers.containsKey(id)) {
        debugPrint("DEDUPLICATION: Removing stale/current marker for $id ($truckId)");
        final marker = _truckMarkers[id]!;
        _pointAnnotationManager?.delete(marker);
        _truckMarkers.remove(id);
      }
      return;
    }

    final double lat = (data['latitude'] ?? 0.0).toDouble();
    final double lng = (data['longitude'] ?? 0.0).toDouble();
    if (lat == 0.0 || lng == 0.0) return;
    final point = Point(coordinates: Position(lng, lat));
    final String status = (data['status'] ?? "OFFLINE").toString().toUpperCase();
    final int color = status == "IDLE" ? Colors.orange.toARGB32() : Colors.green.toARGB32();

    if (_truckMarkers.containsKey(id)) {
      final marker = _truckMarkers[id]!;
      marker.geometry = point; marker.textField = "$truckId ($status)"; marker.textColor = color;
      _pointAnnotationManager?.update(marker);
    } else {
      _pointAnnotationManager?.create(PointAnnotationOptions(geometry: point, textField: "$truckId ($status)", textOffset: [0, 3.0], textColor: color, textSize: 11, iconSize: 0)).then((m) { if (m != null) _truckMarkers[id] = m; });
    }
  }

  void _updateRoutePolyline(List<Map> points) async {
    if (mapboxMap == null) return;
    if (points.isEmpty && _lastSessionData == null) {
      _clearRoute();
      return;
    }

    final List<Map> allPoints = [];
    if (_lastSessionData != null && _lastSessionData!['start_lat'] != null) {
      allPoints.add({
        'lat': _lastSessionData!['start_lat'],
        'lng': _lastSessionData!['start_lng'],
        'status': 'START',
        'color': 'BLUE',
        'timestamp': _lastSessionData!['timestamp'] ?? 0
      });
    }

    allPoints.addAll(points);

    if (!widget.isHistorical && _lastLocalPos != null) {
      allPoints.add({
        'lat': _lastLocalPos!.latitude,
        'lng': _lastLocalPos!.longitude,
        'status': _currentStatus,
        'color': _currentStatus == "IDLE" ? "YELLOW" : (_currentStatus == "FULL" ? "PINK" : "GREEN"),
        'timestamp': DateTime.now().millisecondsSinceEpoch
      });
    }

    allPoints.sort((a, b) => (a['timestamp'] as num).compareTo(b['timestamp'] as num));

    final List<Map> filtered = [];
    if (allPoints.isNotEmpty) {
      filtered.add(allPoints.first);
      for (int i = 1; i < allPoints.length; i++) {
        final prev = filtered.last;
        final curr = allPoints[i];
        
        final double lat = (curr['lat'] ?? 0.0).toDouble();
        final double lng = (curr['lng'] ?? 0.0).toDouble();
        final double prevLat = (prev['lat'] ?? 0.0).toDouble();
        final double prevLng = (prev['lng'] ?? 0.0).toDouble();

        final double d = geo.Geolocator.distanceBetween(prevLat, prevLng, lat, lng);
        final int timeDiff = (curr['timestamp'] as int) - (prev['timestamp'] as int);
        final double speedKmH = (curr['speed'] ?? 0.0).toDouble() * 3.6;

        // 1. FILTER: Outlier jump detection (Speed check)
        if (timeDiff > 0 && timeDiff < 10000 && d > 150) continue;

        // 2. FILTER: Jitter reduction (Speed + Distance)
        bool isStationary = speedKmH < 2.0;
        double threshold = isStationary ? 8.0 : 4.0;
        if (d < threshold && i != allPoints.length - 1 && prev['status'] == curr['status']) continue;

        filtered.add(curr);
      }
    }

    final List<Map> processed = [];
    if (filtered.isNotEmpty) {
      int start = 0;
      for (int i = 1; i <= filtered.length; i++) {
        if (i == filtered.length || filtered[i]['status'] != filtered[start]['status']) {
          final segment = filtered.sublist(start, i);
          // Epsilon 0.00004 (~4.5 meters) helps snap shaky trails into clean straight lines
          final simplified = _simplifyPoints(segment, 0.00004);
          if (processed.isNotEmpty) {
            processed.addAll(simplified.skip(1));
          } else {
            processed.addAll(simplified);
          }
          start = i;
        }
      }
    }

    final String sourceId = "driver-route-source";
    final List<Map<String, dynamic>> features = [];

    if (processed.length >= 2) {
      for (int i = 1; i < processed.length; i++) {
        final prev = processed[i - 1];
        final curr = processed[i];
        
        String color = (curr['color'] ?? 'GREEN').toString().toUpperCase();

        if (features.isNotEmpty && features.last['properties']['color'] == color) {
          final List coords = features.last['geometry']['coordinates'];
          coords.add([(curr['lng'] ?? 0.0).toDouble(), (curr['lat'] ?? 0.0).toDouble()]);
        } else {
          features.add({
            "type": "Feature",
            "geometry": {
              "type": "LineString",
              "coordinates": [
                [(prev['lng'] ?? 0.0).toDouble(), (prev['lat'] ?? 0.0).toDouble()],
                [(curr['lng'] ?? 0.0).toDouble(), (curr['lat'] ?? 0.0).toDouble()]
              ]
            },
            "properties": {"color": color}
          });
        }
      }
    }

    final featureCollection = {"type": "FeatureCollection", "features": features};

    try {
      final style = mapboxMap!.style;
      bool sourceCreated = await style.styleSourceExists(sourceId);
      if (!sourceCreated) {
        await style.addSource(GeoJsonSource(id: sourceId, data: jsonEncode(featureCollection)));
        
        if (!(await style.styleLayerExists("driver-route-layer"))) {
          await style.addLayer(LineLayer(
            id: "driver-route-layer", sourceId: sourceId, 
            lineColor: Colors.green.toARGB32(), lineWidth: 6.0, lineOpacity: 1.0, 
            lineCap: LineCap.ROUND, lineJoin: LineJoin.ROUND
          ));
          
          await style.setStyleLayerProperty("driver-route-layer", "line-color", [
            "match", ["get", "color"],
            "BLUE", "#2196F3",
            "GREEN", "#4CAF50", 
            "YELLOW", "#FFEB3B", 
            "PINK", "#E91E63", 
            "BLACK", "#212121", 
            "#4CAF50"
          ]);
        }
        if (mounted) setState(() => _routeSourceCreated = true);
      } else { 
        await style.setStyleSourceProperty(sourceId, "data", jsonEncode(featureCollection)); 
      }
    } catch (e) {}
  }

  List<Map> _simplifyPoints(List<Map> points, double epsilon) {
    if (points.length < 3) return points;
    int index = -1;
    double maxDist = 0;
    for (int i = 1; i < points.length - 1; i++) {
      double d = _perpendicularDistance(points[i], points.first, points.last);
      if (d > maxDist) { index = i; maxDist = d; }
    }
    if (maxDist > epsilon) {
      List<Map> res1 = _simplifyPoints(points.sublist(0, index + 1), epsilon);
      List<Map> res2 = _simplifyPoints(points.sublist(index), epsilon);
      return [...res1.sublist(0, res1.length - 1), ...res2];
    }
    return [points.first, points.last];
  }

  double _perpendicularDistance(Map p, Map start, Map end) {
    double x = (p['lng'] as num).toDouble(); double y = (p['lat'] as num).toDouble();
    double x1 = (start['lng'] as num).toDouble(); double y1 = (start['lat'] as num).toDouble();
    double x2 = (end['lng'] as num).toDouble(); double y2 = (end['lat'] as num).toDouble();
    double dx = x2 - x1; double dy = y2 - y1;
    if (dx == 0 && dy == 0) return sqrt(pow(x - x1, 2) + pow(y - y1, 2));
    double t = ((x - x1) * dx + (y - y1) * dy) / (dx * dx + dy * dy);
    if (t < 0) return sqrt(pow(x - x1, 2) + pow(y - y1, 2));
    if (t > 1) return sqrt(pow(x - x2, 2) + pow(y - y2, 2));
    return sqrt(pow(x - (x1 + t * dx), 2) + pow(y - (y1 + t * dy), 2));
  }

  void _clearRoute() async {
    if (mapboxMap == null) return;
    try { await mapboxMap!.style.setStyleSourceProperty("driver-route-source", "data", jsonEncode({"type": "FeatureCollection", "features": []})); } catch (e) {}
  }

  Widget _buildLegendItem(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
    );
  }


  String _calculateEstimatedEnd() {
    if (_startTime == "--:--" || _lastSessionData == null || widget.currentSessionId == null) {
      return "--:--";
    }
    DateTime start;
    if (_lastSessionData!['server_start_time'] != null) {
      start = DateTime.fromMillisecondsSinceEpoch(_lastSessionData!['server_start_time'] as int);
    } else if (_lastSessionData!['timestamp'] != null) {
      start = DateTime.fromMillisecondsSinceEpoch(_lastSessionData!['timestamp'] as int);
    } else {
      start = DateTime.now();
    }
    final end = start.add(const Duration(hours: 4));
    return DateFormat('h:mm a').format(end);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isMiniMap) {
      return _buildEmbeddedLayout();
    }
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

  Widget _buildEmbeddedLayout() {
    return Stack(
      children: [
        Positioned.fill(child: _buildMap()),
        _buildMapControls(bottom: 20),
      ],
    );
  }

  Widget _buildMap() {
    return MapWidget(
      onMapCreated: _onMapCreated, 
      onStyleLoadedListener: _onStyleLoaded, 
      viewport: CameraViewportState(center: Point(coordinates: _balintawakCenter), zoom: 14.5)
    );
  }

  Widget _buildSwipeUpContent(ScrollController scrollController) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double titleFontSize = (screenWidth * 0.055).clamp(18.0, 22.0);
    final double subtitleFontSize = (screenWidth * 0.035).clamp(11.0, 13.0);

    return Column(
      children: [
        // FIXED HEADER SECTION (Hindi sumasama sa scroll, parang sa resident view)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (details) {
            if (_sheetController.isAttached) {
              _sheetController.jumpTo((_sheetController.size - details.delta.dy / MediaQuery.of(context).size.height).clamp(0.22, 0.85));
            }
          },
          onVerticalDragEnd: (details) {
            if (_sheetController.isAttached) {
              final double current = _sheetController.size;
              if (current < 0.35) {
                _sheetController.animateTo(0.22, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
              } else if (current < 0.65) {
                _sheetController.animateTo(0.45, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
              } else {
                _sheetController.animateTo(0.85, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
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
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _lastSessionData == null ? "Searching Tracking..." : "Trip Details", 
                      style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.w900, color: const Color(0xFF1A1A1A))
                    ),

                    Text(
                      _lastSessionData == null ? "Establishing GPS connection" : "Tracking assigned truck", 
                      style: TextStyle(fontSize: subtitleFontSize, color: Colors.grey, fontWeight: FontWeight.w600)
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Divider(height: 1, color: Colors.grey.shade100, thickness: 1),
            ],
          ),
        ),
        
        // SCROLLABLE BODY CONTENT
        Expanded(
          child: ListView(
            controller: scrollController,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(0, 20, 0, 120),
            children: [
              _buildInfoCard(
                title: "Trip Information",
                icon: Icons.info_outline_rounded,
                color: AppColors.tealText,
                content: [
                  _buildInfoRow("Truck Number", _user?.preferredTruck ?? "Unknown", color: AppColors.tealText),
                  const Divider(height: 24),
                  _buildInfoRow("Plate Number", _truckPlateNumber ?? "N/A", isBold: true),
                  const Divider(height: 24),
                  _buildInfoRow("Start Time", _startTime),
                  const Divider(height: 24),
                  _buildInfoRow("Estimated End", _calculateEstimatedEnd()),
                  const Divider(height: 24),
                  _buildInfoRow("Total Distance", "${_distance.toStringAsFixed(1)} km", color: Colors.orangeAccent.shade200),
                ],
              ),
              
              const SizedBox(height: 20),
              
              _buildInfoCard(
                title: "GPS Status",
                icon: Icons.gps_fixed_rounded,
                color: Colors.green, 
                content: [
                  _buildGpsSignalRow(),
                  const Divider(height: 24),
                  _buildInfoRow("Accuracy", _lastLocalPos == null ? "Waiting for fix..." : "±${_lastLocalPos!.accuracy.toInt()} meters"),
                  const Divider(height: 24),
                  _buildInfoRow("Speed", "${_currentSpeed.toStringAsFixed(1)} km/h"),
                  const Divider(height: 24),
                  _buildInfoRow("Last Update", _lastGpsUpdateTime != null ? DateFormat('hh:mm:ss a').format(_lastGpsUpdateTime!) : (_lastLocalPos != null ? DateFormat('hh:mm:ss a').format(_lastLocalPos!.timestamp) : "Waiting...")),
                ],

              ),
            ],
          ),
        ),
      ],
    );
  }


  Widget _buildInfoCard({required String title, required IconData icon, required Color color, required List<Widget> content, bool isDesktop = false}) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double titleFontSize = isDesktop ? 18.0 : (screenWidth * 0.045).clamp(15.0, 18.0);

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isDesktop ? 16 : 20),
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 24 : 28, // Left
        isDesktop ? 24 : 28, // Top
        isDesktop ? 24 : 28, // Right
        isDesktop ? 40 : 36, // Increased Bottom Padding
      ),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(32),
        boxShadow: AppTheme.pulidongShadow, 
        border: Border.all(color: Colors.grey.shade100, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 12),
              Text(title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: titleFontSize, color: color == Colors.black ? Colors.black : color.darken(0.3))),
            ],
          ),
          const SizedBox(height: 24),
          ...content,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? color, bool isBold = false}) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double labelFontSize = (screenWidth * 0.035).clamp(12.0, 14.0);
    final double valueFontSize = (screenWidth * 0.04).clamp(13.0, 15.0);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600, fontSize: labelFontSize)),
        Text(
          value,
          style: TextStyle(
            color: color ?? const Color(0xFF2C3E50),
            fontWeight: isBold ? FontWeight.w900 : FontWeight.w700,
            fontSize: valueFontSize,
          ),
        ),
      ],
    );
  }

  Widget _buildGpsSignalRow() {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double labelFontSize = (screenWidth * 0.035).clamp(12.0, 14.0);
    final double statusFontSize = (screenWidth * 0.035).clamp(11.0, 13.0);

    bool isSearching = _lastLocalPos == null;
    Color statusColor = isSearching ? Colors.orange : Colors.green;
    String statusText = isSearching ? "Searching..." : "Strong";

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text("Signal Strength", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600, fontSize: labelFontSize)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20), 
            border: Border.all(color: statusColor.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(statusText, style: TextStyle(fontWeight: FontWeight.w900, color: statusColor, fontSize: statusFontSize)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMapControls({double bottom = 240}) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth >= 900;
    
    // Control sizes: smaller for mini-map to match Resident experience
    final double btnSize = widget.isMiniMap 
        ? 42.0 
        : (isDesktop ? 56.0 : (screenWidth * 0.15).clamp(48.0, 60.0));
    final double iconSize = widget.isMiniMap 
        ? 20.0 
        : (isDesktop ? 24.0 : (screenWidth * 0.065).clamp(22.0, 26.0));

    final bool isSimplified = widget.isMiniMap;
    // Tiyak na responsive na effectiveBottom gamit ang absolute pixel margin para sa desktop/web view upang mapababa ito nang maayos sa tabi ng Mapbox logo
    final double effectiveBottom = widget.isMiniMap 
        ? 12 
        : (isDesktop 
            ? 24.0 // Saktong-sakto na ibaba sa gilid ng Mapbox attribution text sa Desktop interface
            : (widget.isEmbedded ? (MediaQuery.of(context).size.height * 0.26).clamp(190.0, 220.0) : (MediaQuery.of(context).size.height * 0.32).clamp(240.0, 270.0)));
    
    // Layout Logic:
    // Web (Desktop) -> Kaliwa (LEFT)
    // Mobile Full/Embedded Map Page -> Kanan (RIGHT) katulad ng sa resident view
    // Mini Map (Dashboard) -> Kanan (RIGHT)
    final double? effectiveLeft = isDesktop ? 24 : null;
    final double? effectiveRight = isDesktop ? null : (widget.isMiniMap ? 12 : 20);






    return Positioned(
      bottom: effectiveBottom,
      left: effectiveLeft,
      right: effectiveRight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
              if (_isFollowLocked && _lastLocalPos != null) {
                mapboxMap?.setCamera(CameraOptions(
                    center: Point(coordinates: Position(_lastLocalPos!.longitude, _lastLocalPos!.latitude)),
                    zoom: 16.5));
              }
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) setState(() => _isTargetActive = false);
              });
            },
          ),
          const SizedBox(height: 8), // Tighter gap for mini-map
          _buildMapControlButton(
            icon: Icons.map_outlined,
            isActive: _isMapActive,
            size: btnSize,
            iconSize: iconSize,
            onTap: () {
              setState(() => _isMapActive = true);
              mapboxMap?.setCamera(CameraOptions(center: Point(coordinates: _balintawakCenter), zoom: 14.5));
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) setState(() => _isMapActive = false);
              });
            },
          ),
          if (!widget.isMiniMap && !widget.isHistorical) ...[
            const SizedBox(height: 8),
            _buildMapControlButton(
              icon: Icons.alt_route_rounded, // Mas related na icon para sa route optimization
              isActive: widget.isOptimizing,

              size: btnSize,
              iconSize: iconSize,
              showLoading: widget.isOptimizing,
              onTap: widget.onOptimize,
            ),
          ],
        ],
      ),
    );
  }


  Widget _buildMapControlButton({
    required IconData icon,
    required bool isActive,
    required double size,
    required double iconSize,
    VoidCallback? onTap, // Optional onTap for flexibility
    bool showLoading = false, // Added loading support
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
              child: showLoading
                ? Center(
                    child: SizedBox(
                      width: iconSize * 0.8,
                      height: iconSize * 0.8,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: isActive ? Colors.white : const Color(0xFF00796B),
                      ),
                    ),
                  )
                : Icon(
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
          Positioned.fill(child: _buildMap()),
          _buildCornerHeader(),
          _buildMapControls(bottom: 32),
          _buildDebugOverlay(),

          // Floating Info Panel
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
                  children: [
                    _buildFixedPanelHeader(),
                    const Divider(height: 1),
                    if (_isDataLoading)
                      const Expanded(child: Center(child: CircularProgressIndicator(color: Color(0xFF00796B))))
                    else
                      Expanded(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 400),
                            opacity: _isDataExpanded ? 1.0 : 0.0,
                            child: _buildPanelContent(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Toggle Tab
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
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                      boxShadow: AppTheme.pulidongShadow,
                    ),
                    child: Icon(
                      _isFleetPanelVisible ? Icons.keyboard_arrow_right_rounded : Icons.keyboard_arrow_left_rounded,
                      size: 18, color: Colors.white,
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

  Widget _buildPanelContent() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 60), // Increased bottom padding to 60
      physics: const BouncingScrollPhysics(),
      children: [
        _buildInfoCard(
          title: "Trip Information",
          icon: Icons.info_outline_rounded,
          color: AppColors.tealText,
          isDesktop: true,
          content: [
            _buildInfoRow("Truck Number", _user?.preferredTruck ?? "Unknown", color: AppColors.tealText),
            const Divider(height: 24),
            _buildInfoRow("Plate Number", _truckPlateNumber ?? "N/A", isBold: true),
            const Divider(height: 24),
            _buildInfoRow("Start Time", _startTime),
            const Divider(height: 24),
            _buildInfoRow("Estimated End", _calculateEstimatedEnd()),
            const Divider(height: 24),
            _buildInfoRow("Total Distance", "${_distance.toStringAsFixed(1)} km", color: Colors.orangeAccent.shade200),
          ],
        ),
        const SizedBox(height: 20),
        _buildInfoCard(
          title: "GPS Status",
          icon: Icons.gps_fixed_rounded,
          color: Colors.green, 
          isDesktop: true,
          content: [
            _buildGpsSignalRow(),
            const Divider(height: 24),
            _buildInfoRow("Accuracy", _lastLocalPos == null ? "Waiting for fix..." : "±${_lastLocalPos!.accuracy.toInt()} meters"),
            const Divider(height: 24),
            _buildInfoRow("Speed", "${_currentSpeed.toStringAsFixed(1)} km/h"),
            const Divider(height: 24),
            _buildInfoRow("Last Update", _lastGpsUpdateTime != null ? DateFormat('hh:mm:ss a').format(_lastGpsUpdateTime!) : (_lastLocalPos != null ? DateFormat('hh:mm:ss a').format(_lastLocalPos!.timestamp) : "Waiting...")),
          ],

        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildCornerHeader() {
    return Positioned(
      top: 24, left: 24,
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
            const Text("Unit GIS Tracking", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                const Text("Live telemetry and route monitoring", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w700)),
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
        crossAxisAlignment: CrossAxisAlignment.center, // I-center ang header para sa Web interface
        children: [
          Text("Trip Details", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF00796B))),
          SizedBox(height: 4),
          Text("Live session telemetry details", textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildDebugOverlay() {
    final bool isDesktop = MediaQuery.of(context).size.width >= 900;
    return Positioned(
      top: isDesktop ? 125 : 155,
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
            _buildHUDSeparator("SPEED", "${_currentSpeed.toStringAsFixed(0)} km/h"),
            const SizedBox(width: 12),
            Container(width: 1.5, height: 16, color: Colors.grey.shade300),
            const SizedBox(width: 12),
            _buildHUDSeparator("DIST", "${_distance.toStringAsFixed(1)} km"),
          ],
        ),
      ),
    );
  }

  Widget _buildHUDSeparator(String label, String value) {
    return Row(
      children: [
        Text("$label: ", style: TextStyle(color: Colors.grey.shade600, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
        Text(value, style: const TextStyle(color: Color(0xFF00796B), fontSize: 12, fontWeight: FontWeight.w900)),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return Stack(
      children: [
        Positioned.fill(child: _buildMap()),
        _buildFloatingHeader(),
        _buildLegend(),
        _buildDebugOverlay(), // Added Telemetry Overlay (Speed and Distance) for mobile layout
        _buildMapControls(bottom: 200),

        
        Positioned.fill(
          child: DraggableScrollableSheet(
            controller: _sheetController, // Inilagay ang controller dito para gumana ang vertical swipe gesture sa header panel!
            initialChildSize: 0.22,
            minChildSize: 0.22,
            maxChildSize: 0.85,
            snap: true,
            snapSizes: const [0.22, 0.45, 0.85],
            builder: (context, scrollController) => PointerInterceptor(

              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
                  boxShadow: [
                    BoxShadow(color: Colors.black26, blurRadius: 25, spreadRadius: 5, offset: Offset(0, -5))
                  ],
                ),
                child: _buildSwipeUpContent(scrollController),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFloatingHeader() {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double headerFontSize = (screenWidth * 0.045).clamp(16.0, 18.0);
    final double subFontSize = (screenWidth * 0.025).clamp(9.0, 10.0);
    final double iconSize = (screenWidth * 0.065).clamp(22.0, 26.0);

    return Positioned(
      top: 12, left: 16, right: 16,
      child: SafeArea(
        child: Row(
          children: [
            if (widget.onBack != null) 
              _HoverZoomLink(
                onTap: widget.onBack!, 
                child: Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white, 
                    shape: BoxShape.circle,
                    boxShadow: AppTheme.pulidongShadow,
                  ), 
                  child: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1A1A1A), size: 18)
                )
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: AppTheme.pulidongShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Live Tracking", 
                      style: TextStyle(fontSize: headerFontSize, fontWeight: FontWeight.w900, color: const Color(0xFF1A1A1A), letterSpacing: -0.5)
                    ),
                    Text(
                      _isRefreshing ? "Refreshing map data..." : "Real-time GPS connected", 
                      style: TextStyle(fontSize: subFontSize, color: _isRefreshing ? const Color(0xFF00796B) : Colors.grey.shade600, fontWeight: FontWeight.w700)
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            _HoverZoomLink(
              onTap: _handleManualRefresh,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white, 
                  shape: BoxShape.circle,
                  boxShadow: AppTheme.pulidongShadow,
                ), 
                child: RotationTransition(
                  turns: _refreshRotationController,
                  child: Icon(Icons.refresh_rounded, color: const Color(0xFF00796B), size: iconSize)
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Positioned(
      top: 160, right: 16,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9), 
          borderRadius: BorderRadius.circular(20), 
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))]
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLegendItem(Colors.green, "Active"),
            _buildLegendItem(Colors.yellow, "Idle"),
            _buildLegendItem(Colors.pinkAccent, "Full"),
            _buildLegendItem(Colors.black, "Finish"),
            _buildLegendItem(Colors.blue, "Start"),
          ],
        ),
      ),
    );
  }
}

class _HoverZoomLink extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _HoverZoomLink({required this.child, this.onTap});
  @override
  State<_HoverZoomLink> createState() => _HoverZoomLinkState();
}
class _HoverZoomLinkState extends State<_HoverZoomLink> {
  bool _isActive = false;

  @override
  Widget build(BuildContext context) {
    bool isEnabled = widget.onTap != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _isActive = isEnabled),
      onExit: (_) => setState(() => _isActive = false),
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isActive = isEnabled),
        onTapUp: (_) => setState(() => _isActive = false),
        onTapCancel: () => setState(() => _isActive = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isActive ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: widget.child,
        ),
      ),
    );
  }
}

class _HoverZoomCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  const _HoverZoomCard({required this.child, this.onTap, this.scale = 1.02});
  @override
  State<_HoverZoomCard> createState() => _HoverZoomCardState();
}
class _HoverZoomCardState extends State<_HoverZoomCard> {
  bool _isActive = false;

  @override
  Widget build(BuildContext context) {
    bool isEnabled = widget.onTap != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _isActive = isEnabled),
      onExit: (_) => setState(() => _isActive = false),
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isActive = isEnabled),
        onTapUp: (_) => setState(() => _isActive = false),
        onTapCancel: () => setState(() => _isActive = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isActive ? widget.scale : 1.0,
          duration: const Duration(milliseconds: 200),
          child: widget.child,
        ),
      ),
    );
  }
}
