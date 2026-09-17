import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size, Visibility;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mbox show Visibility;
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart' as geo;

class MapboxView extends StatefulWidget {
  final String mode; 
  final String? selectedTruckId;
  final VoidCallback? onTap;

  const MapboxView({super.key, required this.mode, this.selectedTruckId, this.onTap});

  @override
  State<MapboxView> createState() => _MapboxViewState();
}

class _MapboxViewState extends State<MapboxView> {
  MapboxMap? _map;
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  geo.Position? _residentPosition;
  bool _truckLayersCreated = false;
  bool _managersReady = false;
  bool _isUpdatingMarkers = false;
  bool _isFollowLocked = false;
  bool _isMapActive = false;
  bool _isTargetActive = false;

  // Pulse Animation State
  Timer? _pulseTimer;
  double _pulseRadius = 8.0;
  double _pulseOpacity = 0.5;
  double _pulseRadius2 = 14.0;
  double _pulseOpacity2 = 0.3;

  // Resident Pin Animation
  double _resPulseRadius = 8.0;
  double _resPulseOpacity = 0.5;

  @override
  void initState() {
    super.initState();
    _getResidentLocation();
    _startPulseAnimation();
  }

  void _startPulseAnimation() {
    _pulseTimer?.cancel();
    _pulseTimer = Timer.periodic(const Duration(milliseconds: 35), (timer) {
      if (!mounted || _map == null) return;
      
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

        // Resident Pulse
        _resPulseRadius += 0.5;
        _resPulseOpacity -= 0.012;
        if (_resPulseRadius >= 24.0) {
          _resPulseRadius = 8.0;
          _resPulseOpacity = 0.5;
        }
      });
      _updateMapLayers();
    });
  }

  void _updateMapLayers() async {
    if (_map == null) return;
    try {
      final style = _map!.style;
      
      // Truck Pulses
      if (await style.styleLayerExists("trucks-pulse-layer")) {
        await style.setStyleLayerProperty("trucks-pulse-layer", "circle-radius", _pulseRadius);
        await style.setStyleLayerProperty("trucks-pulse-layer", "circle-opacity", _pulseOpacity.clamp(0.0, 1.0));
      }
      if (await style.styleLayerExists("trucks-pulse-layer-2")) {
        await style.setStyleLayerProperty("trucks-pulse-layer-2", "circle-radius", _pulseRadius2);
        await style.setStyleLayerProperty("trucks-pulse-layer-2", "circle-opacity", _pulseOpacity2.clamp(0.0, 1.0));
      }

      // Resident Pulse
      if (await style.styleLayerExists("resident-pulse-layer")) {
        await style.setStyleLayerProperty("resident-pulse-layer", "circle-radius", _resPulseRadius);
        await style.setStyleLayerProperty("resident-pulse-layer", "circle-opacity", _resPulseOpacity.clamp(0.0, 1.0));
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _pulseTimer?.cancel();
    super.dispose();
  }

  Future<void> _getResidentLocation() async {
    geo.LocationPermission permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) permission = await geo.Geolocator.requestPermission();
    if (permission == geo.LocationPermission.always || permission == geo.LocationPermission.whileInUse) {
      final pos = await geo.Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() => _residentPosition = pos);
        _updateResidentMarker();
      }
    }
  }

  void _updateResidentMarker() async {
    if (_map == null || _residentPosition == null) return;
    final style = _map!.style;
    final sourceId = "resident-source";
    final feature = {
      "type": "FeatureCollection",
      "features": [{
        "type": "Feature",
        "geometry": {"type": "Point", "coordinates": [_residentPosition!.longitude, _residentPosition!.latitude]},
        "properties": {"name": "YOU"}
      }]
    };

    try {
      if (!(await style.styleSourceExists(sourceId))) {
        await style.addSource(GeoJsonSource(id: sourceId, data: jsonEncode(feature)));
        
        // Pulse layer for resident
        await style.addLayer(CircleLayer(
          id: "resident-pulse-layer",
          sourceId: sourceId,
          circleRadius: _resPulseRadius,
          circleColor: const Color(0xFF00796B).toARGB32(),
          circleOpacity: _resPulseOpacity,
        ));

        // Main pin layer for resident
        await style.addLayer(CircleLayer(
          id: "resident-layer",
          sourceId: sourceId,
          circleRadius: 10.0,
          circleColor: const Color(0xFF00796B).toARGB32(),
          circleStrokeWidth: 4.0,
          circleStrokeColor: Colors.white.toARGB32(),
        ));

        // Inner dot
        await style.addLayer(CircleLayer(
          id: "resident-inner-dot",
          sourceId: sourceId,
          circleRadius: 3.5,
          circleColor: Colors.white.toARGB32(),
        ));
      } else {
        await style.setStyleSourceProperty(sourceId, "data", jsonEncode(feature));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MapWidget(
          key: const ValueKey("mapbox_map"),
          onMapCreated: (map) => _map = map,
          onStyleLoadedListener: (data) async {
             if (_map == null) return;
             _map!.location.updateSettings(LocationComponentSettings(enabled: false, pulsingEnabled: false));
             
             // Initial focus on resident
             if (_residentPosition != null) {
               _map?.setCamera(CameraOptions(center: Point(coordinates: Position(_residentPosition!.longitude, _residentPosition!.latitude)), zoom: 15.5));
               _updateResidentMarker();
             }

             if (mounted) setState(() => _managersReady = true);
             _setupFirebaseSync();
          },
          viewport: CameraViewportState(center: Point(coordinates: Position(121.1623, 13.9413)), zoom: 14.5),
        ),
        if (widget.mode == 'dashboard')
          Positioned(
            bottom: 10,
            right: 10,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildMiniMapAction(
                  icon: _isFollowLocked ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded,
                  isActive: _isFollowLocked || _isTargetActive,
                  onTap: () {
                    setState(() {
                      _isFollowLocked = !_isFollowLocked;
                      _isTargetActive = true;
                    });
                    if (_isFollowLocked && _residentPosition != null) {
                      _map?.setCamera(CameraOptions(center: Point(coordinates: Position(_residentPosition!.longitude, _residentPosition!.latitude)), zoom: 16.5));
                      _map?.gestures.updateSettings(GesturesSettings(scrollEnabled: false, rotateEnabled: false, pitchEnabled: false));
                    } else {
                      _map?.gestures.updateSettings(GesturesSettings(scrollEnabled: true, rotateEnabled: true, pitchEnabled: true));
                    }
                    Future.delayed(const Duration(seconds: 2), () {
                      if (mounted) setState(() => _isTargetActive = false);
                    });
                  },
                ),
                const SizedBox(height: 8),
                _buildMiniMapAction(
                  icon: Icons.map_outlined,
                  isActive: _isMapActive,
                  onTap: () {
                    setState(() => _isMapActive = true);
                    _map?.setCamera(CameraOptions(center: Point(coordinates: Position(121.1623, 13.9413)), zoom: 14.5));
                    Future.delayed(const Duration(seconds: 2), () {
                      if (mounted) setState(() => _isMapActive = false);
                    });
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildMiniMapAction({required IconData icon, required VoidCallback onTap, bool isActive = false}) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double btnSize = (screenWidth * 0.12).clamp(40.0, 48.0);
    final double iconSize = (screenWidth * 0.06).clamp(20.0, 24.0);

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
              width: btnSize,
              height: btnSize,
              decoration: BoxDecoration(
                color: isActive 
                    ? const Color(0xFF00796B) 
                    : (isHovered ? const Color(0xFFE0F2F1) : Colors.white),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 8, offset: const Offset(0, 2))],
                border: Border.all(
                  color: isActive ? const Color(0xFF00796B) : (isHovered ? const Color(0xFF00796B).withOpacity(0.3) : Colors.transparent),
                  width: 1.5,
                ),
              ),
              child: Icon(
                icon, 
                color: isActive ? Colors.white : (isHovered ? const Color(0xFF00796B) : const Color(0xFF1A1A1A)), 
                size: iconSize
              ),
            ),
          ),
        );
      },
    );
  }

  void _setupFirebaseSync() {
    _database.ref('truck_locations').onValue.listen((event) {
      if (event.snapshot.exists) {
        final Map data = event.snapshot.value as Map;
        final Map<String, Map<dynamic, dynamic>> trucks = {};
        data.forEach((key, value) {
          final val = value as Map;
          if (val['isOnline'] == true) {
            trucks[key.toString()] = val;
          }
        });
        _updateTruckMarkers(trucks);
      }
    });
  }

  void _updateTruckMarkers(Map<String, Map<dynamic, dynamic>> trucksData) async {
    if (_map == null || !_managersReady || _isUpdatingMarkers) return;
    _isUpdatingMarkers = true;
    final String sourceId = "trucks-source";
    final String layerId = "trucks-layer";

    final featureCollection = {
      "type": "FeatureCollection",
      "features": trucksData.entries.map((e) => {
        "type": "Feature",
        "geometry": {"type": "Point", "coordinates": [e.value['longitude'], e.value['latitude']]},
        "properties": {
          "truckId": e.key, 
          "status": (e.value['status'] ?? "ACTIVE").toString().toUpperCase(),
          "label": "DRIVER\n${e.key}"
        }
      }).toList()
    };

    final statusColorExpr = [
      "match", ["get", "status"],
      "IDLE", Colors.orange.toARGB32(),
      "FULL", Colors.redAccent.toARGB32(),
      "FINISHED", Colors.blueAccent.toARGB32(),
      "COMPLETED", Colors.blueAccent.toARGB32(),
      Colors.green.toARGB32()
    ];

    try {
      final style = _map!.style;
      if (!_truckLayersCreated || !(await style.styleLayerExists(layerId))) {
        try { await style.removeStyleLayer(layerId); } catch (_) {}
        try { await style.removeStyleLayer("trucks-pulse-layer"); } catch (_) {}
        try { await style.removeStyleLayer("trucks-pulse-layer-2"); } catch (_) {}
        try { await style.removeStyleSource(sourceId); } catch (_) {}
        await style.addSource(GeoJsonSource(id: sourceId, data: jsonEncode(featureCollection)));

        // PULSE LAYERS
        await style.addLayer(CircleLayer(
          id: "trucks-pulse-layer", 
          sourceId: sourceId, 
          circleRadius: _pulseRadius, 
          circleColor: Colors.green.toARGB32(), 
          circleOpacity: _pulseOpacity
        ));
        await style.addLayer(CircleLayer(
          id: "trucks-pulse-layer-2", 
          sourceId: sourceId, 
          circleRadius: _pulseRadius2, 
          circleColor: Colors.green.toARGB32(), 
          circleOpacity: _pulseOpacity2
        ));

        await style.setStyleLayerProperty("trucks-pulse-layer", "circle-color", statusColorExpr);
        await style.setStyleLayerProperty("trucks-pulse-layer-2", "circle-color", statusColorExpr);

        await style.addLayer(CircleLayer(
          id: layerId, 
          sourceId: sourceId, 
          circleRadius: 10.0, // Slightly larger for better visibility
          circleColor: Colors.green.toARGB32(), 
          circleStrokeWidth: 4.0, 
          circleStrokeColor: Colors.white.toARGB32(), 
          visibility: mbox.Visibility.VISIBLE
        ));
        await style.setStyleLayerProperty(layerId, "circle-color", statusColorExpr);
        
        // Inner dot for premium look
        await style.addLayer(CircleLayer(
          id: "trucks-inner-dot", 
          sourceId: sourceId, 
          circleRadius: 3.5, 
          circleColor: Colors.white.toARGB32(),
          circleSortKey: 10.0
        ));
        if (mounted) setState(() => _truckLayersCreated = true);
      } else {
        await style.setStyleSourceProperty(sourceId, "data", jsonEncode(featureCollection));
        await style.setStyleLayerProperty("trucks-pulse-layer", "circle-color", statusColorExpr);
        await style.setStyleLayerProperty("trucks-pulse-layer-2", "circle-color", statusColorExpr);
        await style.setStyleLayerProperty(layerId, "circle-color", statusColorExpr);
      }
    } catch (e) {
      debugPrint("Map Error: $e");
      if (mounted) setState(() => _truckLayersCreated = false);
    } finally { _isUpdatingMarkers = false; }
  }
}
