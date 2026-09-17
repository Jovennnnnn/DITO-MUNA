import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/session_manager.dart';
import '../models/user.dart';
import '../utils/app_theme.dart';
import 'driver_settings_screen.dart';
import 'driver_track_truck_screen.dart';
import 'view_daily_routes_screen.dart';
import '../services/route_optimization_service.dart';
import '../utils/responsive.dart';
import '../utils/app_localizations.dart';
import '../utils/custom_notification.dart';

import '../widgets/header_circle_painter.dart';
import '../widgets/hover_action_button.dart';
import '../widgets/fade_slide_entrance.dart';
import '../widgets/data_management_modal.dart';
import '../widgets/custom_snackbar.dart';

class DriverDashboard extends StatefulWidget {
  const DriverDashboard({super.key});

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> with TickerProviderStateMixin {
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  UserData? _user;
  String _status = "OFFLINE";
  String _startTime = "--:--";
  DateTime? _startDateTime;
  double _distance = 0.0;
  double _speed = 0.0;
  int _completedCount = 0;

  int _totalPuroks = 13;
  int _selectedIndex = 0;
  bool _isPuroksExpanded = false;
  bool _isNavigating = false;
  int _unreadNotifications = 0;
  bool _isSimulationMode = false;
  Timer? _simulationTimer;
  bool _isDebugPanelExpanded = false; // Collapsible Debug Panel
  String _currentTime = "";
  Timer? _clockTimer;
  Map<String, dynamic> _maintenanceData = {};
  String? _truckPlateNumber;
  StreamSubscription? _truckSubscription;
  StreamSubscription? _userSubscription;

  // Header Animation
  late AnimationController _circleController;

  // DEVELOPER TEST OVERRIDE
  String _testStatusOverride = "AUTO"; // AUTO, FORCE ACTIVE, FORCE IDLE, FORCE FULL

  final List<Map<String, dynamic>> _purokConfigs = [];

  Map<String, dynamic> _purokStatus = {};
  bool _isWeeklyProgressLoading = true;

  // Tracking & Session
  StreamSubscription<Position>? _positionSubscription;
  Position? _currentPosition;
  String? _sessionId;
  DateTime? _lastGpsUpdateTime;
  Timer? _idleDetectionTimer;
  bool _isInitializing = true;
  StreamSubscription? _statusSubscription;
  StreamSubscription? _purokStatusSubscription;
  StreamSubscription? _notificationSubscription;
  StreamSubscription? _routePointsSubscription;

  List<Map> _tripRoutePoints = [];
  List<Map>? _debugTestRoute; // NEW: For web testing

  final RouteOptimizationService _optimizationService = RouteOptimizationService();
  bool _isOptimizing = false;
  Map? _optimizedData;
  StreamSubscription? _optimizedSubscription;

  // Weekly Progress
  String? _currentWeekKey;
  final Map<String, int> _purokConsecutivePoints = {}; // Robust proximity tracking

  final ScrollController _scrollController = ScrollController();
  bool _showHeaderShadow = true;

  bool _isRefreshing = false;
  bool _showRefreshSpinner = false;
  double _manualPullDepth = 0.0;
  late AnimationController _refreshRotationController;

  @override
  void initState() {
    super.initState();
    _startClock();
    _circleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat();

    _refreshRotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    _scrollController.addListener(() {
      if (_scrollController.offset <= 0 && !_showHeaderShadow) {
        setState(() => _showHeaderShadow = true);
      } else if (_scrollController.offset > 0 && _showHeaderShadow) {
        setState(() => _showHeaderShadow = false);
      }
    });

    _loadUser();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _truckSubscription?.cancel();
    _userSubscription?.cancel();
    _statusSubscription?.cancel();
    _purokStatusSubscription?.cancel();
    _notificationSubscription?.cancel();
    _routePointsSubscription?.cancel();
    _optimizedSubscription?.cancel();
    _positionSubscription?.cancel();
    _idleDetectionTimer?.cancel();
    _simulationTimer?.cancel();
    _circleController.dispose();
    _refreshRotationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshDashboard({bool manual = false}) async {
    if (_isRefreshing) return;
    
    if (manual && mounted) {
      setState(() {
        _isRefreshing = true;
        _showRefreshSpinner = true;
        _manualPullDepth = 80.0;
      });
    }
    _refreshRotationController.repeat();

    await Future.wait([
      _loadPuroks(),
      _refreshUserData(),
      Future.delayed(const Duration(milliseconds: 1500)),
    ]);

    if (manual) {
      await Future.delayed(const Duration(seconds: 1));
    }

    if (mounted) {
      setState(() {
        _isRefreshing = false;
      });
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) {
        setState(() {
          _showRefreshSpinner = false;
          _manualPullDepth = 0.0;
        });

        if (manual) {
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
                      BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 15,
                          offset: const Offset(0, 5))
                    ],
                  ),
                  child: const Material(
                    color: Colors.transparent,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                        SizedBox(width: 12),
                        Text("Duty metrics synchronized",
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: Color(0xFF1A1A1A))),
                      ],

                    ),
                  ),
                ),
              );
            },
          );
        }
      }
      _refreshRotationController.stop();
    }
  }

  Future<void> _refreshUserData() async {
    final sessionUser = await SessionManager.getUser();
    if (sessionUser != null) {
      if (mounted) {
        setState(() {
          _user = sessionUser;
        });
      }
      _setupUserListener();
    }
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
      setState(() {
        _currentTime = time;
      });
      
      // Periodically verify week key (e.g., at midnight)
      if (DateTime.now().minute % 30 == 0 && DateTime.now().second == 0) {
        _updateWeekKey();
      }
    }
  }

  void _updateWeekKey() {
    // Week identifier: Monday to Sunday in Asia/Manila
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    // Find previous Monday
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final String key = "W${DateFormat('yyyy-MM-dd').format(monday)}";
    
    if (_currentWeekKey != key) {
      debugPrint("[WEEKLY] New Week Key Detected: $key (Previous: $_currentWeekKey)");
      setState(() {
        _currentWeekKey = key;
        _purokStatus = {};
        _completedCount = 0;
      });
      
      // Re-setup listener for the new week
      if (_user != null) {
        _setupPurokListener();
      }
    }
  }

  String _generatePurokConfigHash() {
    if (_purokConfigs.isEmpty) return "empty";
    // Sort by ID to ensure deterministic hash regardless of loading order
    final sorted = List<Map<String, dynamic>>.from(_purokConfigs);
    sorted.sort((a, b) => a['id'].toString().compareTo(b['id'].toString()));
    
    final StringBuffer buffer = StringBuffer();
    for (var p in sorted) {
      buffer.write("${p['id']}:${p['lat']},${p['lng']},${p['radius']}|");
    }
    // Simple fast hash of the configuration string
    return buffer.toString().hashCode.toString();
  }

  bool _isLoadingPuroks = false; // State to prevent redundant fetches

  Future<void> _loadPuroks({bool showFeedback = false}) async {
    if (_isLoadingPuroks) return; // Skip if already loading
    
    if (showFeedback && mounted) {
      CustomSnackBar.show(context, message: "Loading collection areas...");
    }

    setState(() => _isLoadingPuroks = true);

    try {
      debugPrint("========== AUTHORITATIVE AREA LOAD ==========");

      debugPrint("SOURCE: Firebase Realtime Database (puroks/)");
      
      final snapshot = await _database.ref('puroks').get();
      
      if (snapshot.exists && snapshot.value != null) {
        final Map data = snapshot.value as Map;
        final List<Map<String, dynamic>> loaded = [];
        
        data.forEach((key, value) {
          if (value is Map) {
            // STRICT CANONICAL FIELDS
            final double lat = (value['latitude'] ?? value['lat'] ?? 0.0).toDouble();
            final double lng = (value['longitude'] ?? value['lng'] ?? 0.0).toDouble();
            final String name = (value['name'] ?? key).toString();
            final double radius = (value['radius'] ?? 60.0).toDouble();
            
            if (lat != 0.0 && lng != 0.0) {
              loaded.add({
                'id': key.toString(),
                'name': name,
                'lat': lat,
                'lng': lng,
                'radius': radius,
              });
            } else {
              debugPrint("[WARNING] Skipping area '$name' due to missing/zero coordinates.");
            }
          }
        });

        debugPrint("LOADED COUNT: ${loaded.length}");
        
        if (loaded.isNotEmpty) {
          _updatePurokConfigs(loaded);
          _tryAutoOptimizeRoute("AREAS_LOADED");
          return;
        }
      }

      // If we reached here, the node is empty or has no valid coordinates
      debugPrint("[CRITICAL] Collection area coordinates have not been configured.");
      if (mounted) {
        setState(() {
          _purokConfigs.clear();
          _totalPuroks = 0;
        });
        if (showFeedback) {
          CustomSnackBar.show(context, message: "Collection area coordinates have not been configured.", isError: true);
        }
      }
      
    } catch (e) {
      debugPrint("========== MASTER AREA LOAD ERROR ==========");
      debugPrint("ERROR: $e");
      if (showFeedback && mounted) {
        CustomSnackBar.show(context, message: "Error loading areas: $e", isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoadingPuroks = false);
    }
  }

  void _updatePurokConfigs(List<Map<String, dynamic>> loaded) {
    debugPrint("--- PARSED AREAS ---");
    for (var area in loaded) {
      debugPrint("ID: ${area['id']}, NAME: ${area['name']}, LAT: ${area['lat']}, LNG: ${area['lng']}");
    }
    debugPrint("PARSED COUNT: ${loaded.length}");
    
    // ========== CURRENT MASTER PUROKS ==========
    debugPrint("========== CURRENT MASTER PUROKS ==========");
    debugPrint("SOURCE: puroks");
    debugPrint("COUNT: ${loaded.length}");
    for (var area in loaded) {
      debugPrint("ID: ${area['id']}");
      debugPrint("NAME: ${area['name']}");
      debugPrint("LAT: ${area['lat']}");
      debugPrint("LNG: ${area['lng']}");
      debugPrint("RADIUS: ${area['radius']}");
      debugPrint("------------------------------------------");
    }
    debugPrint("============================================");

    _auditPurokCoordinates(loaded);

    debugPrint("======================================");

    if (mounted) {
      setState(() {
        _purokConfigs.clear();
        _purokConfigs.addAll(loaded);
        _totalPuroks = loaded.length;
      });
    }
  }

  void _auditPurokCoordinates(List<Map<String, dynamic>> loaded) {
    debugPrint("========== PUROK COORDINATE AUDIT ==========");
    
    final Map<String, List<String>> coordinateMap = {};

    for (int i = 0; i < loaded.length; i++) {
      final a = loaded[i];
      final String coordKey = "${a['lat'].toStringAsFixed(5)},${a['lng'].toStringAsFixed(5)}";
      
      coordinateMap.putIfAbsent(coordKey, () => []).add(a['name']);

      debugPrint("AREA: ${a['name']}");
      debugPrint("LAT: ${a['lat']}");
      debugPrint("LNG: ${a['lng']}");
      debugPrint("RADIUS: ${a['radius']}m"); // Use configured radius

      if (i > 0) {
        final prev = loaded[i-1];
        double dist = Geolocator.distanceBetween(a['lat'], a['lng'], prev['lat'], prev['lng']);
        debugPrint("DISTANCE FROM PREVIOUS (${prev['name']}): ${dist.toStringAsFixed(2)}m");
      }
      debugPrint("------------------------------------------");
    }

    // Duplicate detection
    bool duplicatesFound = false;
    coordinateMap.forEach((coord, names) {
      if (names.length > 1) {
        duplicatesFound = true;
        debugPrint("[CRITICAL] DUPLICATE COORDINATES FOUND: $coord");
        debugPrint("   Used by: ${names.join(', ')}");
      }
    });

    if (!duplicatesFound) {
      debugPrint("No exact coordinate duplicates found.");
    }

    // Near-duplicate detection (within 10 meters)
    for (int i = 0; i < loaded.length; i++) {
      for (int j = i + 1; j < loaded.length; j++) {
        double d = Geolocator.distanceBetween(
          loaded[i]['lat'], loaded[i]['lng'], 
          loaded[j]['lat'], loaded[j]['lng']
        );
        if (d < 10) {
          debugPrint("[WARNING] NEAR-DUPLICATE COORDINATES: ${loaded[i]['name']} and ${loaded[j]['name']} are only ${d.toStringAsFixed(2)}m apart.");
        }
      }
    }

    debugPrint("=============================================");
  }

  bool _isRestoringSession = false;

  void _loadUser() async {
    if (!mounted) return;
    
    debugPrint("========== LOGIN SUCCESS AT: ${DateTime.now()} ==========");

    // 1. Resolve Driver ID immediately from session (Fastest)
    _user = await SessionManager.getUser();
    if (_user == null) {
       debugPrint("ERROR: No user found in SessionManager");
       return;
    }
    
    final String driverIdStr = _user!.userId.toString();
    final String truckId = _user?.preferredTruck ?? "Unknown";
    debugPrint("DRIVER RESOLVED AT: ${DateTime.now()} (ID: $driverIdStr, Truck: $truckId)");

    if (mounted) {
      setState(() {
        _isInitializing = true;
        _isRestoringSession = true;
        _startTime = "Restoring...";
        _status = "ACTIVE"; // Immediate operational status
      });
    }

    // 2. Start essential listeners and background tasks in PARALLEL
    // We don't await individual listener setups to prevent sequential blocking
    _loadPuroks(); // Ensure purok configs are loaded as early as possible
    _setupUserListener();

    _loadMaintenanceData(truckId);
    _setupTruckListener();
    _setupListeners();
    _updateWeekKey();
    _startTracking();

    // 3. Update online presence and Restore session in PARALLEL
    // These are the heaviest awaited tasks
    try {
      await Future.wait([
        _database.ref('truck_locations').child(truckId).update({
          'isOnline': true,
          'status': 'ACTIVE',
          'lastSeen': ServerValue.timestamp,
          'driver_id': _user?.userId,
          'driver_name': _user?.name,
        }),
        _restoreTripSession(truckId, driverIdStr),
      ]);
    } catch (e) {
      debugPrint("Initialization error: $e");
    }
    
    if (mounted) {
      setState(() {
        _isInitializing = false;
        _isRestoringSession = false;
      });
    }
    debugPrint("========== INITIALIZATION COMPLETE AT: ${DateTime.now()} ==========");
  }

  Future<void> _restoreTripSession(String truckId, String driverIdStr) async {
    debugPrint("[SESSION] UNFINISHED TRIP QUERY START: ${DateTime.now()}");
    
    String? existingSessionId;
    Map? activeRouteData;
    
    // 1. Resolve Location quickly without blocking restoration if possible
    try {
      // Check last known first (instant)
      Position? lastPos = await Geolocator.getLastKnownPosition();
      if (lastPos != null && mounted) setState(() => _currentPosition = lastPos);

      // Attempt fresh fix with very short timeout
      Position? freshPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 1), // Reduced from 3s to 1s
      );
      if (mounted) setState(() => _currentPosition = freshPos);
      debugPrint("[SESSION] Authoritative position obtained during restoration: ${freshPos.latitude}, ${freshPos.longitude}");
    } catch (e) {
      debugPrint("[SESSION] Fast position check skipped or timed out: $e");
    }

    // 1. Check Driver document first (Most reliable persistent reference)
    try {
      final userSnap = await _database.ref('users/$driverIdStr').get();
      if (userSnap.exists && userSnap.value != null) {
        final uData = userSnap.value as Map;
        if (uData['current_trip_id'] != null) {
          final String pointerId = uData['current_trip_id'].toString();
          debugPrint("[SESSION] Found current_trip_id in user doc: $pointerId");
          
          final routeSnap = await _database.ref('driver_routes/$pointerId').get();
          if (routeSnap.exists && routeSnap.value != null) {
            final rData = routeSnap.value as Map;
            
            // SECURITY: Ensure this session belongs to THIS driver
            final String sessionDriverId = (rData['driver_id'] ?? '').toString();
            bool isMySession = (sessionDriverId == driverIdStr || rData['driver_id'] == _user?.userId);

            // STRICT TERMINAL STATUS CHECK
            final String status = (rData['route_status'] ?? '').toString().toUpperCase();
            bool isFinished = rData['isFinished'] == true || 
                             rData['finishTime'] != null || 
                             rData['end_time'] != null ||
                             status == 'COMPLETED' || 
                             status == 'FINISHED';

            bool isActive = status == 'ACTIVE' && !isFinished;
            
            if (isMySession && isActive) {
              existingSessionId = pointerId;
              activeRouteData = rData;
              debugPrint("[SESSION] Driver doc recovery successful: $existingSessionId (FIREBASE START TIME: ${activeRouteData!['start_time']})");
            } else {
              debugPrint("[SESSION] Driver doc pointer found but trip is ALREADY FINISHED or INVALID. Ignoring.");
              // OPTIONAL: Clear stale pointer
              await _database.ref('users/$driverIdStr').update({'current_trip_id': null});
            }
          }
        }
      }
    } catch (e) {
      debugPrint("[SESSION] Driver doc recovery error: $e");
    }

    // 2. Check truck_locations second (Direct path, NO INDEX NEEDED)
    if (existingSessionId == null) {
      try {
        final locSnap = await _database.ref('truck_locations/$truckId').get();
        if (locSnap.exists && locSnap.value != null) {
          final lData = locSnap.value as Map;
          if (lData['current_session'] != null) {
            final String pointerId = lData['current_session'].toString();
            debugPrint("[SESSION] Found current_session pointer: $pointerId");
            
            final routeSnap = await _database.ref('driver_routes/$pointerId').get();
            if (routeSnap.exists && routeSnap.value != null) {
              final rData = routeSnap.value as Map;
              
              // SECURITY: Ensure this session belongs to THIS driver
              final String sessionDriverId = (rData['driver_id'] ?? '').toString();
              bool isMySession = (sessionDriverId == driverIdStr || rData['driver_id'] == _user?.userId);

              // STRICT TERMINAL STATUS CHECK
              final String status = (rData['route_status'] ?? '').toString().toUpperCase();
              bool isFinished = rData['isFinished'] == true || 
                               rData['finishTime'] != null || 
                               rData['end_time'] != null ||
                               status == 'COMPLETED' || 
                               status == 'FINISHED';

              bool isActive = status == 'ACTIVE' && !isFinished;
              
              if (isMySession && isActive) {
                existingSessionId = pointerId;
                activeRouteData = rData;
                debugPrint("[SESSION] Primary recovery successful: $existingSessionId (FIREBASE START TIME: ${activeRouteData!['start_time']})");
              } else {
                debugPrint("[SESSION] Truck pointer found but trip is ALREADY FINISHED. Ignoring.");
                await _database.ref('truck_locations').child(truckId).update({'current_session': null});
              }
            }
          }
        }
      } catch (e) {
        debugPrint("[SESSION] Primary recovery error: $e");
      }
    }

    // 3. Fallback: Query driver_routes for ANY ACTIVE trip for this driver
    if (existingSessionId == null) {
      try {
        debugPrint("[SESSION] Falling back to query driver_routes for any ACTIVE trip...");
        final routesRef = _database.ref('driver_routes');
        
        final List<DataSnapshot> snapshots = [];
        snapshots.add(await routesRef.orderByChild('driver_id').equalTo(_user?.userId).get());
        snapshots.add(await routesRef.orderByChild('driver_id').equalTo(driverIdStr).get());
        
        int latestTimestamp = 0;
        for (var snapshot in snapshots) {
          if (snapshot.exists && snapshot.value != null) {
            final Map routes = snapshot.value as Map;
            routes.forEach((key, value) {
              final String status = (value['route_status'] ?? '').toString().toUpperCase();
              bool isFinished = value['isFinished'] == true || 
                               value['finishTime'] != null || 
                               value['end_time'] != null ||
                               status == 'COMPLETED' || 
                               status == 'FINISHED';

              if (status == 'ACTIVE' && !isFinished) {
                int ts = (value['server_start_time'] ?? value['timestamp'] ?? 0) as int;
                if (ts > latestTimestamp) {
                  latestTimestamp = ts;
                  existingSessionId = key.toString();
                  activeRouteData = value as Map;
                }
              }
            });
          }
        }
      } catch (e) {
        debugPrint("[SESSION] Fallback query failed: $e");
      }
    }

    debugPrint("[SESSION] UNFINISHED TRIP QUERY END: ${DateTime.now()}");
    debugPrint("TRIP FOUND: ${existingSessionId != null}");

    if (existingSessionId != null) {
      _sessionId = existingSessionId;
      if (activeRouteData != null && mounted) {
        final String restoredStartTime = activeRouteData!['start_time'] ?? "--:--";
        debugPrint("LOCAL RESTORED START TIME: $restoredStartTime");
        
        setState(() {
          _startTime = restoredStartTime;
          _distance = (activeRouteData!['total_distance'] ?? 0.0).toDouble();
          
          if (activeRouteData!['server_start_time'] != null) {
            _startDateTime = DateTime.fromMillisecondsSinceEpoch(activeRouteData!['server_start_time'] as int);
          } else if (activeRouteData!['timestamp'] != null) {
            _startDateTime = DateTime.fromMillisecondsSinceEpoch(activeRouteData!['timestamp'] as int);
          }
        });
        debugPrint("FINAL UI START TIME: $_startTime");
      }
      
      // Force sync the CORRECT original Start Time to the live node and user doc
      await _database.ref('users/$driverIdStr').update({'current_trip_id': _sessionId});
      await _database.ref('truck_locations').child(truckId).update({
        'current_session': _sessionId,
        'start_time': _startTime,
        'distance': _distance,
      });

      _setupPurokListener();
      _setupRoutePointsListener();
      _setupOptimizedRouteListener();
      _startIdleDetection();

      // NEW: Try auto-optimization now that session is restored
      _tryAutoOptimizeRoute("RESTORE");
    } else {
      debugPrint("[LIFECYCLE] No unfinished trip found. Creating new trip to ensure ACTIVE status.");
      // Auto-start new trip if none found - Satisfies Test 5 requirement
      await _startTripSession();
    }
  }

  void _setupOptimizedRouteListener() {
    if (_sessionId == null) return;
    _optimizedSubscription?.cancel();
    _optimizedSubscription = _database.ref('driver_routes/$_sessionId/optimized_route').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        if (mounted) setState(() => _optimizedData = event.snapshot.value as Map);
      } else {
        if (mounted) setState(() => _optimizedData = null);
      }
    });
  }

  void _loadMaintenanceData(String truckId) async {
    final ref = _database.ref('trucks/$truckId/maintenance');
    // We listen to it live so we have the latest flags and values
    ref.onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        if (mounted) {
          setState(() {
            _maintenanceData = Map<String, dynamic>.from(event.snapshot.value as Map);
          });
        }
      }
    });
  }

  void _setupUserListener() {
    if (_user == null) return;
    _userSubscription?.cancel();
    
    // Using current user ID
    _userSubscription = _database.ref('users/${_user!.userId}').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map data = event.snapshot.value as Map;
        
        if (mounted) {
          setState(() {
            // Merge Firebase data with current user object to avoid losing fields
            final Map<String, dynamic> currentData = _user!.toJson();
            data.forEach((k, v) => currentData[k] = v);
            final updatedUser = UserData.fromJson(currentData);
            
            // Update local state and restart truck listener if truck ID changed
            if (_user?.preferredTruck != updatedUser.preferredTruck) {
              _user = updatedUser;
              _setupTruckListener();
              _setupListeners();
            } else {
              _user = updatedUser;
            }
          });
        }
      }
    });
  }

  void _setupTruckListener() {
    _truckSubscription?.cancel();
    final truckId = _user?.preferredTruck ?? "Unknown";

    _truckSubscription = _database.ref('trucks/$truckId').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final data = event.snapshot.value as Map;
        if (mounted) {
          setState(() {
            _truckPlateNumber = data['plateNumber']?.toString() ?? "N/A";
          });
        }
      }
    });
  }

  void _setupListeners() {
    final truckId = _user?.preferredTruck ?? "Unknown";
    _statusSubscription?.cancel();
    _statusSubscription = _database.ref('truck_locations').child(truckId).onValue.listen((event) {
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map;
        final String remoteStatus = data['status']?.toString().toUpperCase() ?? "OFFLINE";
        
        if (mounted) {
          debugPrint("STATUS UPDATE FROM FIREBASE: $remoteStatus (Current Local: $_status)");
          
          // During initialization, don't let a stale OFFLINE or IDLE from Firebase 
          // overwrite our local ACTIVE status.
          if (_isInitializing && (remoteStatus == "OFFLINE" || remoteStatus == "IDLE")) {
             debugPrint("   -> IGNORING STALE STATUS DURING INITIALIZATION");
             return;
          }

          setState(() {
            _status = remoteStatus;
            // AUTHORITATIVE: Distance and Start Time are managed by the Driver app locally
            // and synced TO Firebase history, avoiding overwriting with stale data on re-login.
          });
        }
      }
    });

    _notificationSubscription?.cancel();
    
    // Track dashboard load time to avoid showing historical alerts as real-time popups
    final int dashboardLoadTime = DateTime.now().millisecondsSinceEpoch;

    _notificationSubscription = _database.ref('notifications').onValue.listen((event) {
      if (event.snapshot.exists) {
        final Map data = event.snapshot.value as Map;
        int unread = 0;
        
        // Debug counters
        int matched = 0;
        int adminExcluded = 0;
        int residentExcluded = 0;
        int otherDriverExcluded = 0;

        data.forEach((k, v) {
          final val = v as Map;
          bool forMe = _isNotificationForMe(val);
          
          if (forMe) {
            matched++;
            if (val['isRead'] == false) {
              unread++;
              
              // NEW: Trigger real-time SnackBar if it's a NEW notification while dashboard is open
              final int ts = (val['timestamp'] ?? 0) as int;
              if (ts > dashboardLoadTime && val['realtimeTriggered'] != true) {
                // Mark locally as triggered to avoid duplicates in the same session
                val['realtimeTriggered'] = true; 
                _showSnackBar("${val['title']}: ${val['message']}");
              }
            }
          } else {
            // Determine exclusion reason for debug
            final String type = (val['type'] ?? '').toString();
            if (['REGISTRATION', 'NEW_REGISTRATION', 'RESIDENT_COMPLAINT'].contains(type)) {
              adminExcluded++;
            } else if (['auto_arrival', 'auto_approach', 'manual_alert', 'COLLECTION_ALERT', 'COMPLAINT_RESOLVED'].contains(type)) {
              residentExcluded++;
            } else {
              otherDriverExcluded++;
            }
          }
        });

        debugPrint("--- DRIVER NOTIFICATION DEBUG ---");
        debugPrint("CURRENT DRIVER ID: ${_user?.userId}");
        debugPrint("ASSIGNED TRUCK: ${_user?.preferredTruck}");
        debugPrint("RAW NOTIFICATIONS: ${data.length}");
        debugPrint("DRIVER MATCHED: $matched");
        debugPrint("EXCLUDED ADMIN: $adminExcluded");
        debugPrint("EXCLUDED RESIDENT: $residentExcluded");
        debugPrint("EXCLUDED OTHER DRIVER: $otherDriverExcluded");
        debugPrint("FINAL DRIVER ALERT COUNT: $matched (Unread: $unread)");
        debugPrint("---------------------------------");

        if (mounted) {
          setState(() => _unreadNotifications = unread);
        }
      }
    });

    // --- NEW: CONNECTION RECOVERY LOGIC ---
    _database.ref('.info/connected').onValue.listen((event) {
      final bool isConnected = event.snapshot.value == true;
      if (isConnected && _sessionId != null && _user != null) {
        debugPrint("[CONNECTION] Reconnected. Restoring active status...");
        // If we have an active session, ensure we are ACTIVE and Online
        _database.ref('truck_locations').child(_user?.preferredTruck ?? "Unknown").update({
           'isOnline': true,
           'status': (_status.contains("LOST") || _status == "OFFLINE") ? "ACTIVE" : _status,
           'updatedAt': DateTime.now().toIso8601String(),
        });
        if (mounted) {
          setState(() {
            if (_status.contains("LOST") || _status == "OFFLINE") {
              _status = "ACTIVE";
            }
          });
        }
      } else if (!isConnected && _status != "OFFLINE") {
        debugPrint("[CONNECTION] Lost. Setting local status to IDLE.");
        if (mounted) setState(() => _status = "IDLE (LOST)");
      }
    });
  }

  void _setupRoutePointsListener() {
    if (_sessionId == null) {
      return;
    }
    _routePointsSubscription?.cancel();
    _routePointsSubscription = _database.ref('driver_routes/$_sessionId/route').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map data = event.snapshot.value as Map;
        final List<Map> list = [];
        data.forEach((k, v) => list.add(v as Map));
        list.sort((a, b) => (a['timestamp'] ?? 0).compareTo(b['timestamp'] ?? 0));
        
        debugPrint("[LIFECYCLE] RESTORED ROUTE POINT COUNT: ${list.length}");
        
        if (mounted) setState(() => _tripRoutePoints = list);
      }
    });
  }

  void _setupPurokListener() {
    if (_user == null || _currentWeekKey == null) {
      return;
    }
    
    _purokStatusSubscription?.cancel();
    
    // WEEKLY SOURCE OF TRUTH: Shared across all sessions in the same week
    final String driverId = _user!.userId.toString();

    if (mounted) setState(() => _isWeeklyProgressLoading = true);

    _purokStatusSubscription = _database
        .ref('weekly_collection_progress/$_currentWeekKey/$driverId/areas')
        .onValue.listen((event) {
      
      if (mounted) setState(() => _isWeeklyProgressLoading = false);

      if (event.snapshot.exists && event.snapshot.value != null) {
        final data = event.snapshot.value as Map;
        int completed = 0;
        data.forEach((key, value) {
          if (value['completed'] == true) completed++;
        });
        
        debugPrint("[WEEKLY] PROGRESS UPDATE: $completed / $_totalPuroks");

        if (mounted) {
          setState(() {
            _purokStatus = Map<String, dynamic>.from(data);
            _completedCount = completed;
          });
          
          // Trigger re-optimization when progress changes
          _tryAutoOptimizeRoute("PROGRESS_CHANGED");

          final truckId = _user?.preferredTruck ?? "Unknown";
          _database.ref('truck_locations').child(truckId).update({
            'visited_puroks': completed,
            'efficiency': (_totalPuroks > 0) ? (completed / _totalPuroks) * 100 : 0.0,
          });
        }
      } else {
        debugPrint("[WEEKLY] No data found for current week. Initializing...");
        _initializeWeeklyProgress();
      }
    });
  }

  Future<void> _initializeWeeklyProgress() async {
    if (_user == null || _currentWeekKey == null) return;
    
    // Safety: Wait for purok configs if they are still loading
    if (_purokConfigs.isEmpty) {
       debugPrint("[WEEKLY] Purok configs empty. Deferring initialization...");
       await _loadPuroks();
       if (_purokConfigs.isEmpty) {
         debugPrint("[WEEKLY] CRITICAL: No puroks found in Firebase. Cannot initialize progress.");
         return;
       }
    }
    
    final String driverId = _user!.userId.toString();
    final ref = _database.ref('weekly_collection_progress/$_currentWeekKey/$driverId');
    
    // Check again to avoid race conditions
    final snap = await ref.get();
    if (snap.exists) {
      final Map data = snap.value as Map;
      if (data['areas'] != null && (data['areas'] as Map).isNotEmpty) {
        debugPrint("[WEEKLY] Progress already initialized with areas. Skipping.");
        return;
      }
      debugPrint("[WEEKLY] Progress node exists but areas missing. Re-initializing...");
    }

    Map<String, dynamic> initial = {};
    for (var p in _purokConfigs) {
      String key = p['id'].toString(); // USE CANONICAL ID
      initial[key] = {
        'name': p['name'],
        'lat': p['lat'],
        'lng': p['lng'],
        'completed': false,
      };
    }

    await ref.update({
      'week_start': _currentWeekKey!.substring(1),
      'driver_id': driverId,
      'truck_id': _user?.preferredTruck ?? "Unknown",
      'areas': initial,
    });
    
    debugPrint("[WEEKLY] Initialized for week $_currentWeekKey with ${initial.length} areas.");
  }

  // --- TRIP LOGIC ---

  Future<void> _startTripSession() async {
    debugPrint("[SESSION] _startTripSession called. current session Id: $_sessionId");
    
    // PREVENT DUPLICATE TRIPS: If a session already exists, do not create another.
    if (_sessionId != null) {
      debugPrint("[SESSION] WARNING: _startTripSession called but session Id already exists ($_sessionId). Ignoring.");
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return;
      }
    }

    final truckId = _user?.preferredTruck ?? "Unknown";
    final driverId = _user?.userId ?? "Unknown";

    try {
      debugPrint("[SESSION] Requesting current position for new trip...");
      Position startPos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.bestForNavigation);
      debugPrint("[SESSION] Start position obtained: ${startPos.latitude}, ${startPos.longitude}");
      
      // Authoritative update of local state immediately to allow UI like Optimizer to use it
      if (mounted) {
        setState(() {
          _currentPosition = startPos;
        });
      }

      _sessionId = _database.ref('driver_routes').push().key;
      debugPrint("START TIME WRITE: NEW TRIP CREATED. ID: $_sessionId");
      
      // Authoritative persistent reference in the Driver's own document
      await _database.ref('users/$driverId').update({
        'current_trip_id': _sessionId,
      });

      _startDateTime = DateTime.now();
      String timeStr = DateFormat('h:mm a').format(_startDateTime!);
      debugPrint("[SESSION] New Start Time generated: $timeStr");

      debugPrint("[SESSION] Writing new session data to Firebase...");
      await _database.ref('truck_locations').child(truckId).update({
        'status': 'ACTIVE',
        'isOnline': true,
        'driver_id': driverId,
        'driver_name': _user?.name ?? 'Driver',
        'plate_number': _truckPlateNumber,
        'start_time': timeStr,
        'server_start_time': ServerValue.timestamp,
        'latitude': startPos.latitude,
        'longitude': startPos.longitude,
        'distance': 0.0,
        'speed': 0.0,
        'avg_speed': 0.0,
        'efficiency': 0.0,
        'accuracy': startPos.accuracy,
        'lastSeen': ServerValue.timestamp,
        'updatedAt': DateTime.now().toIso8601String(),
        'current_session': _sessionId,
      });

      _database.ref('truck_locations').child(truckId).onDisconnect().update({
        'status': 'IDLE', // Mark as IDLE if app is killed or signal lost
        'isOnline': false,
        'lastSeen': ServerValue.timestamp,
      });

      await _database.ref('driver_routes').child(_sessionId!).set({
        'truck_id': truckId,
        'driver_id': driverId,
        'driver_name': _user?.name ?? 'Driver',
        'start_time': timeStr,
        'server_start_time': ServerValue.timestamp, // PERSISTENCE: Actual timestamp
        'total_distance': 0.0, // PERSISTENCE: Track distance here too
        'route_status': 'ACTIVE',
        'isOnline': true,
        'timestamp': ServerValue.timestamp,
        'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'maintenanceProcessed': false,
        'start_lat': startPos.latitude,
        'start_lng': startPos.longitude,
        'start_accuracy': startPos.accuracy,
      });
      debugPrint("[SESSION] Firebase write complete for new trip.");

      // Trigger initial optimization
      _tryAutoOptimizeRoute("NEW_TRIP");

      // CRITICAL: First route point must be EXACTLY the start point
      _appendRoutePoint(startPos, "ACTIVE", "GREEN");

      if (mounted) {
        setState(() {
          _status = "ACTIVE";
          _startTime = timeStr;
          _distance = 0.0;
          _currentPosition = startPos;
          _lastGpsUpdateTime = DateTime.now();
          // _completedCount and _purokStatus are NOT reset here because they are weekly.
          _autoNotifiedPuroks.clear(); 
          _approachNotifiedPuroks.clear();
        });
      }
      _setupPurokListener();
      _setupRoutePointsListener();
      _setupOptimizedRouteListener();
      _startTracking();
      _startIdleDetection();
    } catch (e) {
      // Error handling
    }
  }

  void _startTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation, 
        distanceFilter: 0, // 0 for max sensitivity during tests
      ),
    ).listen((pos) => _processNewPosition(pos));
  }

  void _processNewPosition(Position pos) {
    if (_sessionId == null || _status == "OFFLINE" || _status == "FINISHED") return;
    
    // GPS FIX LOG
    if (_currentPosition == null) {
      debugPrint("GPS FIRST FIX: ${pos.latitude}, ${pos.longitude} AT: ${DateTime.now()}");
      
      // TRIGGER AUTO-OPTIMIZATION ON FIRST FIX
      _tryAutoOptimizeRoute("GPS_FIRST_FIX");
    }
    // Reject extremely poor accuracy readings (e.g., 20000m)
    if (pos.accuracy > 50 && !_isSimulationMode) {
      debugPrint("[GPS FILTER] Rejected point due to poor accuracy: ${pos.accuracy}m");
      return;
    }

    final truckId = _user?.preferredTruck ?? "Unknown";
    
    double traveled = 0;

    if (_currentPosition != null) {
      // Calculate real distance walked/traveled between consecutive points
      traveled = Geolocator.distanceBetween(
        _currentPosition!.latitude, 
        _currentPosition!.longitude, 
        pos.latitude, 
        pos.longitude
      ) / 1000.0; // convert to km
      
      // Filter out micro-jitter (less than 2 meters)
      if (traveled < 0.002) {
        traveled = 0;
      }
    }

    _lastGpsUpdateTime = DateTime.now();
    double speedKmH = (pos.speed * 3.6);

    // 1. GPS NOISE FILTERING
    bool isAccurate = pos.accuracy < 35.0; // Reject points with > 35m error
    bool movedFarEnough = traveled > 0.003; // Must move at least 3 meters (Walking speed friendly)

    // Debug raw vs accepted
    debugPrint("[GPS MASTER] RAW: ${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)} | ACC: ${pos.accuracy.toStringAsFixed(1)}m | SPEED: ${speedKmH.toStringAsFixed(1)}km/h");

    if (!isAccurate && !_isSimulationMode) {
      debugPrint("[GPS REJECTED] Poor Accuracy: ${pos.accuracy.toStringAsFixed(1)}m");
      return;
    }

    if (mounted) {
      setState(() {
        _speed = speedKmH;
        if (movedFarEnough || _currentPosition == null || _isSimulationMode) {

          _distance += traveled;
          _currentPosition = pos;
          debugPrint("[GPS MASTER] ACCEPTED: ${pos.latitude}, ${pos.longitude}");
          _checkMaintenanceThresholds();
        } else {
          debugPrint("[GPS MASTER] FILTERED (Stationary): moved ${traveled * 1000}m");
        }
        
        // Auto-status logic (Only if not overridden)
        if (_testStatusOverride == "AUTO") {
          if (speedKmH > 1.2 && _status == "IDLE") {
            _updateTripStatus("ACTIVE");
          }
        }
      });
    }

    _checkPurokProximity(pos);

    double avgSpeed = 0.0;
    if (_startDateTime != null) {
      final durationHrs = DateTime.now().difference(_startDateTime!).inSeconds / 3600.0;
      if (durationHrs > 0) {
        avgSpeed = _distance / durationHrs;
      }
    }

    // Determine Status for this specific point (respecting override)
    String effectiveStatus = _getEffectiveRouteStatus();
    String trailColor = _getTrailColorForStatus(effectiveStatus);

    _database.ref('truck_locations').child(truckId).update({
      'truck_id': truckId, // NEW: Include ID in the node data
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      'distance': _distance,
      'speed': speedKmH,
      'avg_speed': avgSpeed,
      'heading': pos.heading,
      'accuracy': pos.accuracy,
      'status': effectiveStatus, 
      'isOnline': true,
      'plate_number': _truckPlateNumber,
      'lastSeen': ServerValue.timestamp,
      'updatedAt': DateTime.now().toIso8601String(),
    });

    // Persistent trip distance update
    if (_sessionId != null) {
      _database.ref('driver_routes').child(_sessionId!).update({
        'total_distance': _distance,
        'last_lat': pos.latitude,
        'last_lng': pos.longitude,
        'last_seen': ServerValue.timestamp,
      });
    }

    if (movedFarEnough || _tripRoutePoints.isEmpty || _isSimulationMode) {
      _appendRoutePoint(pos, effectiveStatus, trailColor);
    }
  }

  String _getEffectiveRouteStatus() {
    if (_testStatusOverride != "AUTO") {
      return _testStatusOverride.replaceFirst("FORCE ", "");
    }
    // Normalize status for route points
    if (_status.contains("IDLE")) return "IDLE";
    if (_status.contains("FULL")) return "FULL";
    if (_status.contains("FINISHED")) return "FINISHED";
    return "ACTIVE";
  }

  String _getTrailColorForStatus(String status) {
    switch (status.toUpperCase()) {
      case "IDLE": return "YELLOW";
      case "FULL": return "PINK";
      case "FINISHED": return "BLACK";
      default: return "GREEN";
    }
  }

  void _checkPurokProximity(Position pos) {
    if (_sessionId == null || _currentWeekKey == null || _user == null) {
      return;
    }
    
    // 1. GPS QUALITY CHECK: Ignore bad accuracy or stale events
    if (pos.accuracy > 40 && !_isSimulationMode) {
      debugPrint("[PROXIMITY] Skipping due to poor accuracy: ${pos.accuracy}");
      return;
    }

    final String driverId = _user!.userId.toString();

    for (var p in _purokConfigs) {
      String key = p['name'].replaceAll('/', '_');
      
      double dist = Geolocator.distanceBetween(pos.latitude, pos.longitude, p['lat'], p['lng']);
      double geofenceRadius = (p['radius'] ?? 60.0).toDouble();

      // --- APPROACH DETECTION (5x Radius) ---
      if (dist <= (geofenceRadius * 5) && dist > geofenceRadius) {
        _handleApproachNotification(p['name'], dist);
      }
      
      // Skip if already completed this week
      if (_purokStatus[key]?['completed'] == true) {
        continue;
      }
      
      // 2. STABLE CONDITION: Must be within geofence at low speed
      // Speed check: < 25 km/h ensures they are actually collecting, not just flying by.
      bool speedValid = _isSimulationMode || (pos.speed * 3.6) < 25.0; 

      if (dist <= geofenceRadius && speedValid) {
        // Increment consecutive valid points inside this Purok
        _purokConsecutivePoints[key] = (_purokConsecutivePoints[key] ?? 0) + 1;
        
        // 3. PREVENT FALSE POSITIVES: Require 3 consecutive valid points (approx 6-15 seconds)
        if (_purokConsecutivePoints[key]! >= 3 || _isSimulationMode) {
          debugPrint("[WEEKLY] Robust detection confirmed for ${p['name']}. Marking COMPLETED.");
          
          _database.ref('weekly_collection_progress/$_currentWeekKey/$driverId/areas/$key').update({
            'completed': true,
            'completedAt': DateFormat('yyyy-MM-dd hh:mm a').format(DateTime.now()),
            'timestamp': ServerValue.timestamp,
            'completionSource': _isSimulationMode ? 'SIMULATION' : 'GPS_PROXIMITY',
            'sessionId': _sessionId,
            'truckId': _user?.preferredTruck ?? "Unknown",
          });
          
          _database.ref('truck_locations').child(_user?.preferredTruck ?? "Unknown").update({'current_purok': p['name']});
          
          // --- Automatic Arrival Notifications ---
          _handleAutoNotifications(p['name'], dist);
          
          // Reset counter after completion
          _purokConsecutivePoints[key] = 0;
        } else {
          debugPrint("[PROXIMITY] Inside ${p['name']}. Points: ${_purokConsecutivePoints[key]}/3");
        }
      } else {
        // Reset counter if they leave or speed up
        _purokConsecutivePoints[key] = 0;
      }
    }
  }

  final Set<String> _autoNotifiedPuroks = {};

  void _handleAutoNotifications(String areaName, double distance) async {
    if (_autoNotifiedPuroks.contains(areaName)) {
      return;
    }
    
    final truckId = _user?.preferredTruck ?? "Unknown";
    
    // 1. Send "Arrived" notification to Firebase
    await _database.ref('notifications').push().set({
      'type': 'auto_arrival',
      'title': 'Garbage Truck Arrived',
      'message': 'The garbage truck ($truckId) has arrived in $areaName.',
      'purok': areaName,
      'truck_id': truckId,
      'timestamp': ServerValue.timestamp,
      'isRead': false
    });
    
    _autoNotifiedPuroks.add(areaName);
    debugPrint("[AUTO-NOTIFY] Sent arrival alert for $areaName");
  }

  final Set<String> _approachNotifiedPuroks = {};

  void _handleApproachNotification(String areaName, double distance) async {
    if (_approachNotifiedPuroks.contains(areaName)) {
      return;
    }
    
    final truckId = _user?.preferredTruck ?? "Unknown";
    
    // Calculate simple ETA (Assume 15 km/h for arrival)
    double speedMps = 15 / 3.6; 
    int etaMinutes = (distance / speedMps / 60).ceil();
    if (etaMinutes < 1) {
      etaMinutes = 1;
    }

    await _database.ref('notifications').push().set({
      'type': 'auto_approach',
      'title': 'Garbage Truck Approaching',
      'message': 'Truck $truckId is on the way to $areaName. Estimated arrival: $etaMinutes min.',
      'purok': areaName,
      'truck_id': truckId,
      'timestamp': ServerValue.timestamp,
      'isRead': false
    });
    
    _approachNotifiedPuroks.add(areaName);
    debugPrint("[AUTO-NOTIFY] Sent approach alert for $areaName (ETA: $etaMinutes)");
  }

  void _appendRoutePoint(Position pos, String status, String color) {
    if (_sessionId == null) {
      return;
    }
    // Use local timestamp for immediate consistent sorting in map views
    final int ts = DateTime.now().millisecondsSinceEpoch;
    _database.ref('driver_routes').child(_sessionId!).child('route').push().set({
      'lat': pos.latitude, 'lng': pos.longitude, 'status': status, 'color': color,
      'speed': pos.speed * 3.6, 'heading': pos.heading, 'accuracy': pos.accuracy, 
      'timestamp': ts,
    });
  }

  void _startIdleDetection() {
    _idleDetectionTimer?.cancel();
    _idleDetectionTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_currentPosition == null || _status == "OFFLINE" || _status == "FINISHED" || _status == "IDLE") {
        return;
      }
      if (_lastGpsUpdateTime != null && DateTime.now().difference(_lastGpsUpdateTime!).inMinutes >= 2) {
        _updateTripStatus("IDLE");
      }
    });
  }

  Future<void> _updateTripStatus(String newStatus) async {
    final truckId = _user?.preferredTruck ?? "Unknown";
    
    // VALIDATION: Changing status must NOT change weekly progress
    debugPrint("[STATUS] Changing truck status to $newStatus. Weekly progress preserved.");

    await _database.ref('truck_locations').child(truckId).update({
      'status': newStatus.toUpperCase(),
      'updatedAt': DateTime.now().toIso8601String(),
    });
    if (mounted) {
      setState(() => _status = newStatus);
    }
  }

  bool _isFinishing = false; // Added to prevent multiple finish calls

  Future<void> _finishTrip() async {
    debugPrint("[FINISH] Finish Trip sequence started...");
    
    if (_isFinishing) {
      debugPrint("[FINISH] WARNING: Already in the process of finishing.");
      return;
    }

    setState(() => _isFinishing = true);
    final truckId = _user?.preferredTruck ?? "Unknown";
    final driverId = _user?.userId.toString() ?? "Unknown";

    debugPrint("[FINISH] LOG: Initial State - session Id: $_sessionId, driverId: $driverId, status: $_status");

    try {
      // 1. RECOVERY LOGIC: If session Id is null, try to find an active trip in Firebase
      if (_sessionId == null) {
        debugPrint("[FINISH] RECOVERY: Local session Id is null. Searching Firebase...");
        
        // 1. Check truck_locations first (Direct path, NO INDEX NEEDED)
        final locSnap = await _database.ref('truck_locations/$truckId').get();
        if (locSnap.exists && locSnap.value != null) {
          final lData = locSnap.value as Map;
          if (lData['current_session'] != null) {
            _sessionId = lData['current_session'].toString();
            debugPrint("[FINISH] Recovered session Id from truck_locations: $_sessionId");
            
            final sessionSnap = await _database.ref('driver_routes/$_sessionId').get();
            if (sessionSnap.exists) {
              final sData = sessionSnap.value as Map;
              _startTime = sData['start_time'] ?? _startTime;
              _distance = (sData['total_distance'] ?? _distance).toDouble();
            }
          }
        }

        // 2. Fallback: Check driver_routes (Query, NEEDS INDEX)
        if (_sessionId == null) {
          try {
            final routesRef = _database.ref('driver_routes');
            final activeRouteSnapshot = await routesRef
                .orderByChild('driver_id')
                .equalTo(int.tryParse(driverId) ?? driverId)
                .get();
            
            if (activeRouteSnapshot.exists && activeRouteSnapshot.value != null) {
              final Map routes = activeRouteSnapshot.value as Map;
              routes.forEach((key, value) {
                if (value['route_status'] == 'ACTIVE') {
                  _sessionId = key.toString();
                  _startTime = value['start_time'] ?? _startTime;
                  _distance = (value['total_distance'] ?? _distance).toDouble();
                  if (value['server_start_time'] != null) {
                    _startDateTime = DateTime.fromMillisecondsSinceEpoch(value['server_start_time'] as int);
                  }
                }
              });
            }
          } catch (e) {
            debugPrint("[FINISH] Fallback query failed: $e");
          }
        }
      }

      final String? finalSessionId = _sessionId;
      debugPrint("[FINISH] RECOVERY RESULT: session Id resolved to: $finalSessionId");

      // 2. FINALIZE TRIP DOCUMENT (if it exists)
      if (finalSessionId != null) {
        debugPrint("[FINISH] Step 1: Updating driver_routes document...");
        await _database.ref('driver_routes').child(finalSessionId).update({
          'route_status': 'COMPLETED',
          'isFinished': true,
          'finishTime': ServerValue.timestamp,
          'end_time': DateFormat('h:mm a').format(DateTime.now()),
          'finish_lat': _currentPosition?.latitude,
          'finish_lng': _currentPosition?.longitude,
          'final_distance': _distance,
          'total_distance': _distance,
        });

        if (_currentPosition != null) {
          _appendRoutePoint(_currentPosition!, "FINISHED", "BLACK");
        }

        // Apply Maintenance Deduction
        final sessionRef = _database.ref('driver_routes').child(finalSessionId);
        final sessionSnap = await sessionRef.get();
        bool alreadyDeducted = false;
        if (sessionSnap.exists) {
          final sData = sessionSnap.value as Map;
          alreadyDeducted = sData['maintenance_applied'] == true;
        }

        if (!alreadyDeducted) {
          debugPrint("[FINISH] Step 2: Applying maintenance deduction...");
          await _applyMaintenanceDeduction(truckId, _distance);
          await sessionRef.update({'maintenance_applied': true});
        }
      } else {
        debugPrint("[FINISH] INFO: No persistent trip document found to finalize.");
      }

      // 3. CLEANUP TRUCK LOCATIONS & RESET LOCAL STATE
      debugPrint("[FINISH] Step 3: Resetting truck_locations node and local session pointers...");
      await _database.ref('truck_locations').child(truckId).update({
        'status': 'completed', 
        'current_session': null,
        'start_time': null,
        'distance': 0.0,
        'current_purok': null,
        'visited_puroks': _completedCount, // Preserve the weekly count in live view if relevant
      });

      _positionSubscription?.cancel();
      debugPrint("[FINISH] WRITE SUCCESS: Driver trip closed. Weekly progress remains at $_completedCount / $_totalPuroks.");

      // Clear persistent user doc reference
      await _database.ref('users/$driverId').update({
        'current_trip_id': null,
      });

      if (mounted) {
        setState(() { 
          _status = "COMPLETED"; 
          _sessionId = null; 
          _startTime = "--:--"; 
          _startDateTime = null; // Reset timestamp
          _distance = 0.0;
          _speed = 0.0; // Reset speed
          _lastGpsUpdateTime = null; // Reset GPS update indicator
          _isFinishing = false;

          // _completedCount and _purokStatus are NOT reset here because they are weekly.
          _autoNotifiedPuroks.clear();
          _approachNotifiedPuroks.clear();
        });

        String msg = finalSessionId != null 
            ? "Trip completed successfully." 
            : "No active route record was found. Driver session has been closed.";
            
        debugPrint("[FINISH] TRIP FINISHED: true");
        debugPrint("[FINISH] PREVIOUS TRIP FINISHED: true");

        if (context.mounted) {
          CustomSnackBar.show(context, message: msg, isError: finalSessionId == null);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isFinishing = false);
        debugPrint("[FINISH] ERROR: $e");
        if (context.mounted) {
          CustomSnackBar.show(context, message: "Failed to finish Trip: $e", isError: true);
        }
      }
    }
  }

  void _checkMaintenanceThresholds() async {
    if (_maintenanceData.isEmpty || _user == null) return;
    final truckId = _user?.preferredTruck ?? "Unknown";

    final categories = ['oilChange', 'tireRotation', 'fullInspection'];
    final labels = {
      'oilChange': 'Oil Change',
      'tireRotation': 'Tire Rotation',
      'fullInspection': 'Full Inspection'
    };

    for (var cat in categories) {
      if (!_maintenanceData.containsKey(cat)) continue;
      final data = _maintenanceData[cat] as Map;
      double savedRemaining = (data['remainingKm'] ?? 0.0).toDouble();
      double currentRemaining = savedRemaining - _distance;

      // Thresholds
      if (currentRemaining <= 0 && data['notifiedDue'] != true) {
        await _sendMaintenanceNotification(truckId, cat, "${labels[cat]} Required", "$truckId has reached its ${(labels[cat] ?? '').toLowerCase()} limit. Maintenance is required.", "notifiedDue");
      } else if (currentRemaining <= 100 && data['notified100'] != true) {
        await _sendMaintenanceNotification(truckId, cat, "${labels[cat]} Urgent", "$truckId only has ${currentRemaining.toStringAsFixed(0)} km remaining before its ${(labels[cat] ?? '').toLowerCase()} is due.", "notified100");
      } else if (currentRemaining <= 500 && data['notified500'] != true) {
        await _sendMaintenanceNotification(truckId, cat, "${labels[cat]} Due Soon", "$truckId has ${currentRemaining.toStringAsFixed(0)} km remaining before the next ${(labels[cat] ?? '').toLowerCase()}.", "notified500");
      }
    }
  }

  Future<void> _sendMaintenanceNotification(String truckId, String category, String title, String message, String flagField) async {
    // 1. Mark as notified in Firebase immediately to prevent duplicate triggers
    await _database.ref('trucks/$truckId/maintenance/$category').update({flagField: true});
    
    // 2. Push notification to the global notifications node
    await _database.ref('notifications').push().set({
      'type': 'MAINTENANCE_ALERT',
      'title': title,
      'message': message,
      'truck_id': truckId,
      'driver_id': _user?.userId.toString(),
      'targetRole': 'driver',
      'timestamp': ServerValue.timestamp,
      'isRead': false,
    });
    
    debugPrint("[MAINTENANCE ALERT] $title: $message");
  }

  Future<void> _applyMaintenanceDeduction(String truckId, double tripDistance) async {
    try {
      final truckRef = _database.ref('trucks/$truckId/maintenance');
      final snapshot = await truckRef.get();
      
      if (!snapshot.exists || snapshot.value == null) {
        return;
      }
      final data = snapshot.value as Map;

      // Deduct from each maintenance category
      Future<void> deductItem(String key, double interval) async {
        final item = data[key] as Map?;
        double currentRemaining = (item?['remainingKm'] ?? interval).toDouble();
        double newRemaining = currentRemaining - tripDistance;
        
        // Dynamic status based on new value
        String status = "NORMAL";
        if (newRemaining <= 0) {
          status = "SERVICE DUE";
        } else if (newRemaining <= 100) {
          status = "URGENT";
        } else if (newRemaining <= 500) {
          status = "DUE SOON";
        }

        await truckRef.child(key).update({
          'remainingKm': newRemaining,
          'status': status,
          'lastMaintenanceUpdate': ServerValue.timestamp,
        });
      }

      await deductItem('oilChange', 5000.0);
      await deductItem('tireRotation', 10000.0);
      await deductItem('fullInspection', 20000.0);

      debugPrint("[MAINTENANCE] Final Deduction: $tripDistance km from truck $truckId");
    } catch (e) {
      debugPrint("[MAINTENANCE] Error applying deduction: $e");
    }
  }

  void _handleSimulationToggle() {
    if (_isSimulationMode) {
      setState(() {
        _isSimulationMode = false;
        _simulationTimer?.cancel();
        _startTracking();
      });
      CustomSnackBar.show(context, message: "Simulation stopped. Returning to Real GPS.");
    } else {
      _showAreaSelection("Select Simulation Location", (area) {
        setState(() => _isSimulationMode = true);
        _startSimulationAt(area);
      }, description: "Select a location to simulate the truck's presence for testing purposes.");
    }
  }

  void _startSimulationAt(String areaName) {
    _positionSubscription?.cancel();
    _simulationTimer?.cancel();
    
    // 1. Find the area in our config
    final config = _purokConfigs.firstWhere(
      (p) => p['name'] == areaName,
      orElse: () => _purokConfigs.first,
    );

    debugPrint("[SIMULATION] Starting at ${config['name']} (${config['lat']}, ${config['lng']})");

    void sendSimulatedUpdate(Map<String, dynamic> targetPurok) {
      final pos = Position(
        latitude: targetPurok['lat'], 
        longitude: targetPurok['lng'], 
        timestamp: DateTime.now(), 
        accuracy: 5.0, // High accuracy for simulation
        altitude: 0, heading: 0, speed: 15.0,
        speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0
      );
      
      // Update local state for Map to pick up
      if (mounted) {
        setState(() {
          _currentPosition = pos;
        });
      }

      // This will update truck_locations and trigger proximity checks
      _processNewPosition(pos);
    }

    // Move to the selected Purok instantly
    sendSimulatedUpdate(config);
  }

  void _sendManualAlert(String area) async {
    if (_sessionId == null || _currentWeekKey == null || _user == null) {
      return;
    }
    final truckId = _user?.preferredTruck ?? "Unknown";
    final String driverId = _user!.userId.toString();
    
    try {
      // 1. Send Notification (Target specific Purok residents)
      await _database.ref('notifications').push().set({
        'type': 'manual_alert', 
        'title': 'Garbage Truck Update',
        'message': 'The garbage truck is now approaching $area.',
        'purok': area, // FILTERED BY AREA
        'truck_id': truckId, 
        'timestamp': ServerValue.timestamp, 
        'isRead': false
      });

      // 2. Mark ONLY selected Purok as Completed for the CURRENT WEEK
      // Find area ID from name
      final config = _purokConfigs.firstWhere((p) => p['name'] == area, orElse: () => {});
      if (config.isNotEmpty) {
        String areaId = config['id'].toString();
        await _database.ref('weekly_collection_progress/$_currentWeekKey/$driverId/areas/$areaId').update({
          'completed': true,
          'completedAt': DateFormat('yyyy-MM-dd hh:mm a').format(DateTime.now()),
          'timestamp': ServerValue.timestamp,
          'completionSource': 'MANUAL_ALERT',
          'sessionId': _sessionId,
        });
      }

      if (mounted) {
        CustomSnackBar.show(context, message: "Alert sent and $area marked as visited.");
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(context, message: "Failed to send alert: $e", isError: true);
      }
    }
  }

  void _markAllNotificationsAsRead(List<Map> notifications) async {
    if (notifications.isEmpty) return;
    
    final List<Future> updates = [];
    for (var n in notifications) {
      if (n['isRead'] == false) {
        updates.add(_database.ref('notifications/${n['key']}').update({'isRead': true}));
      }
    }
    
    if (updates.isNotEmpty) {
      await Future.wait(updates);
      debugPrint("[NOTIF] Marked ${updates.length} as read.");
    }
  }

  Future<void> _handleLogout() async {
    debugPrint("[LIFECYCLE] LOGOUT SEQUENCE STARTED");
    
    // 1. Show immediate loading feedback
    if (mounted) {
      setState(() => _isNavigating = true);
    }

    // Capture context early
    final BuildContext currentContext = context;
    final String truckId = _user?.preferredTruck ?? "Unknown";

    try {
      // 2. Clear state immediately for UI responsiveness
      _optimizedData = null;
      _positionSubscription?.cancel();
      
      // 3. Run Firebase update and local logout in PARALLEL to eliminate sequential lag
      await Future.wait([
        _database.ref('truck_locations').child(truckId).update({
          'status': 'OFFLINE', 
          'isOnline': false, 
          'lastSeen': ServerValue.timestamp
        }).timeout(const Duration(seconds: 2), onTimeout: () {
           debugPrint("Firebase logout update timed out");
           return;
        }),
        SessionManager.logout(),
      ]);

      debugPrint("[LIFECYCLE] LOGOUT DATA CLEARED");

      if (mounted) {
        CustomSnackBar.show(currentContext, message: "Logout successful.", isError: false);
        Navigator.pushReplacementNamed(currentContext, '/');
      }
    } catch (e) {
      debugPrint("Logout error: $e");
      // Fallback: force logout anyway to prevent user being stuck
      await SessionManager.logout();
      if (mounted) Navigator.pushReplacementNamed(currentContext, '/');
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = Responsive.isDesktop(context);
    
    // DIAGNOSTIC LOGGING
    if (_currentPosition != null) {
       debugPrint("[DASHBOARD BUILD] currentPos: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}");
    }

    Widget content;
    if (isDesktop) {
      content = Row(
        children: [
          _buildSidebar(),
          Expanded(child: _buildMainContent()),
        ],
      );
    } else {
      content = Stack(
        children: [
          _buildMainContent(),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomNav(),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: isDesktop ? AppColors.dashboardBg : Colors.white,
      extendBody: !isDesktop, // Allow body to scroll behind the floating nav
      body: Stack(
        children: [
          content,
          _buildRefreshSpinner(),
          // DIAGNOSTICS OVERLAY
          Positioned(
            top: 50, right: 10,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildDiagnosticRow("GPS", _currentPosition != null 
                        ? "${_currentPosition!.latitude.toStringAsFixed(5)}, ${_currentPosition!.longitude.toStringAsFixed(5)}" 
                        : "WAITING FOR GPS"),
                    _buildDiagnosticRow("LAST", _tripRoutePoints.isNotEmpty 
                        ? "${_tripRoutePoints.last['lat']?.toStringAsFixed(5) ?? '...'}, ${_tripRoutePoints.last['lng']?.toStringAsFixed(5) ?? '...'}" 
                        : "NO POINTS"),
                  ],
                ),
              ),
            ),
          ),
          // COLLAPSIBLE DEBUG OVERLAY & WALK TEST PANEL
          Positioned(
            top: 100, left: 10,
            child: Container(
              width: 180,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () => setState(() => _isDebugPanelExpanded = !_isDebugPanelExpanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("DEBUG PANEL", style: TextStyle(color: Colors.yellow, fontSize: 10, fontWeight: FontWeight.bold)),
                          Icon(_isDebugPanelExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.white70, size: 14),
                        ],
                      ),
                    ),
                  ),
                  if (_isDebugPanelExpanded) ...[
                    const Divider(color: Colors.white24, height: 1),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("TRIP: ${_sessionId ?? 'none'}", style: const TextStyle(color: Colors.white70, fontSize: 8)),
                          Text("COMPLETED PUROKS: $_completedCount / $_totalPuroks", style: const TextStyle(color: Colors.greenAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                          Text("WEEKLY LOADING: $_isWeeklyProgressLoading", style: const TextStyle(color: Colors.white70, fontSize: 8)),
                          Text("CURRENT STATUS: $_status", style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                          Text("EFFECTIVE ROUTE STATUS: ${_getEffectiveRouteStatus()}", style: const TextStyle(color: Colors.cyanAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                          if (_startDateTime != null)
                            Text("START: ${_tripRoutePoints.isNotEmpty ? _tripRoutePoints.first['lat'] : '...' }, ${_tripRoutePoints.isNotEmpty ? _tripRoutePoints.first['lng'] : '...'}", style: const TextStyle(color: Colors.white70, fontSize: 8)),
                          Text("GPS: ${_currentPosition != null ? 'LOCKED' : 'SEARCHING'}", style: TextStyle(color: _currentPosition != null ? Colors.greenAccent : Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                          if (_currentPosition != null) ...[
                            Text("LAT: ${_currentPosition!.latitude.toStringAsFixed(6)}", style: const TextStyle(color: Colors.white70, fontSize: 8)),
                            Text("LNG: ${_currentPosition!.longitude.toStringAsFixed(6)}", style: const TextStyle(color: Colors.white70, fontSize: 8)),
                            Text("ACCURACY: ${_currentPosition!.accuracy.toStringAsFixed(1)}m", style: TextStyle(color: _currentPosition!.accuracy < 20 ? Colors.greenAccent : Colors.orangeAccent, fontSize: 8)),
                          ],
                          const SizedBox(height: 4),
                          Text("ROUTE POINTS: ${_tripRoutePoints.length}", style: const TextStyle(color: Colors.white, fontSize: 8)),
                          _buildDebugCounter("ACTIVE POINTS", "ACTIVE"),
                          _buildDebugCounter("IDLE POINTS", "IDLE"),
                          _buildDebugCounter("FULL POINTS", "FULL"),
                          const SizedBox(height: 4),
                          Text("DISTANCE: ${_distance.toStringAsFixed(3)} km", style: const TextStyle(color: Colors.white, fontSize: 9)),
                          Text("MAP ROUTE: ${_sessionId != null ? 'VISIBLE' : 'HIDDEN'}", style: const TextStyle(color: Colors.white, fontSize: 8)),
                          const SizedBox(height: 8),
                          const Text("FORCE STATUS COLOR:", style: TextStyle(color: Colors.cyanAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          _buildOverrideButtons(),
                          const SizedBox(height: 8),
                          if (_debugTestRoute != null) ...[
                            const Divider(color: Colors.white24),
                            const Text("TEST ROUTE METRICS:", style: TextStyle(color: Colors.orangeAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                            _buildTestRouteMetrics(),
                            const SizedBox(height: 8),
                          ],
                          const Divider(color: Colors.white24),
                          const Text("RENDERER TEST:", style: TextStyle(color: Colors.orangeAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          _buildRendererTestButtons(),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticRow(String label, String value, {Color color = Colors.white70}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("$label: ", style: const TextStyle(color: Colors.white38, fontSize: 8)),
          Text(value, style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildDebugCounter(String label, String status) {
    int count = _tripRoutePoints.where((p) => (p['status'] ?? '').toString().toUpperCase() == status).length;
    Color color = Colors.white70;
    if (status == "ACTIVE") color = Colors.greenAccent;
    if (status == "IDLE") color = Colors.yellowAccent;
    if (status == "FULL") color = Colors.pinkAccent;
    return Text("$label: $count", style: TextStyle(color: color, fontSize: 7));
  }

  Widget _buildMainContent() {
    return LayoutBuilder(builder: (context, constraints) {
      final bool isDesktop = Responsive.isDesktop(context);
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerMove: (event) {
          // Disable pull-to-refresh on Map and Settings pages
          // They handle their own refresh or don't use this gesture
          if (_selectedIndex != 0) return;
          
          bool atTop = _scrollController.hasClients && _scrollController.offset <= 0;



          if (!_isRefreshing && (atTop || _manualPullDepth > 0)) {
            if (event.delta.dy > 0 || _manualPullDepth > 0) {
              setState(() {
                _manualPullDepth += event.delta.dy * 0.5;
                if (_manualPullDepth < 0) _manualPullDepth = 0;
                if (_manualPullDepth > 120) _manualPullDepth = 120;
                _showRefreshSpinner = _manualPullDepth > 0;
              });
            }
          }
        },
        onPointerUp: (event) {
          if (_manualPullDepth > 70 && !_isRefreshing) {
            _refreshDashboard(manual: true);
          } else if (!_isRefreshing) {
            setState(() {
              _manualPullDepth = 0;
              _showRefreshSpinner = false;
            });
          }
        },
        child: IndexedStack(index: _selectedIndex, children: [
          FadeSlideEntrance(key: const ValueKey("home"), child: _buildResponsiveDashboard(constraints)),
          FadeSlideEntrance(
            key: const ValueKey("track"),
            child: DriverTrackTruckScreen(
              isEmbedded: true, 
              currentSessionId: _sessionId, 
              focusTruckId: _user?.preferredTruck ?? "Unknown", 
              onBack: () => setState(() => _selectedIndex = 0),
              isSimulation: _isSimulationMode,
              manualPosition: _currentPosition, 
              testRoute: _debugTestRoute, 
              currentDistance: _distance,
              currentSpeed: _speed,
              startTime: _startTime,
              lastGpsUpdateTime: _lastGpsUpdateTime,
              onOptimize: _optimizeRoute,
              isOptimizing: _isOptimizing,
            ),



          ),
          FadeSlideEntrance(
            key: const ValueKey("settings"),
            child: DriverSettingsScreen(
              isEmbedded: true, 
              onBack: () => setState(() => _selectedIndex = 0), 
              currentSessionId: _sessionId,
            ),
          ),
        ]),
      );
    });
  }

  Widget _buildResponsiveDashboard(BoxConstraints constraints) {
    if (Responsive.isDesktop(context)) {
      return _buildDesktopDashboard();
    } else {
      return _buildMobileDashboard(constraints.maxWidth);
    }
  }

  Widget _buildMobileDashboard(double width) {
    final double screenWidth = MediaQuery.of(context).size.width;
    
    // Adaptive sizes for Quick Actions
    final double titleFontSize = (screenWidth * 0.045).clamp(15.0, 18.0);
    final double subtitleFontSize = (screenWidth * 0.035).clamp(12.0, 14.0);
    final double iconContainerSize = (screenWidth * 0.13).clamp(48.0, 56.0);
    final double iconSize = (screenWidth * 0.065).clamp(24.0, 28.0);

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
      child: SingleChildScrollView(
        controller: _scrollController,
        physics: (_manualPullDepth > 0 || _isRefreshing) 
            ? const NeverScrollableScrollPhysics() 
            : const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        child: AnimatedBuilder(
          animation: _scrollController,
          builder: (context, child) {
            final double offset = _scrollController.hasClients ? _scrollController.offset : 0;
            return Transform.translate(
              offset: Offset(0, offset < 0 ? offset : 0),
              child: Column(children: [
                _buildHeader(width),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: (screenWidth * 0.05).clamp(16.0, 24.0),
                    vertical: 20
                  ),
                  child: Column(children: [
                    Row(children: [
                      Expanded(
                        child: _buildStatCard(
                          "Start Time",
                          _startTime,
                          Icons.access_time_filled,
                          const Color(0xFFE3F2FD),
                          iconColor: Colors.blue,
                        ),
                      ),
                      SizedBox(width: (screenWidth * 0.03).clamp(8.0, 12.0)),
                      Expanded(
                        child: _buildStatCard(
                          "Distance",
                          "${_distance.toStringAsFixed(2)} km",
                          Icons.route,
                          const Color(0xFFF3E5F5),
                          iconColor: Colors.purple,
                        ),
                      ),
                      SizedBox(width: (screenWidth * 0.03).clamp(8.0, 12.0)),
                      Expanded(
                        child: _buildStatCard(
                          "Speed",
                          "${_speed.toStringAsFixed(1)} km/h",
                          Icons.speed_rounded,
                          const Color(0xFFE8F5E9),
                          iconColor: Colors.green,
                        ),
                      ),
                    ]),

                    const SizedBox(height: 24),
                    _buildVehicleControls(width),
                    const SizedBox(height: 24),
                    _buildActionsGrid(width),
                    const SizedBox(height: 24),
                    _buildOptimizedRouteCard(width),
                    const SizedBox(height: 24),
                    _buildMapCard(width),
                    
                    // QUICK ACTIONS SECTION
                    FadeSlideEntrance(
                      delay: const Duration(milliseconds: 500),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
                            child: Text("Quick Actions", style: TextStyle(fontSize: (screenWidth * 0.05).clamp(16.0, 18.0), fontWeight: FontWeight.w900, color: const Color(0xFF1A1A1A))),
                          ),
                          _buildActionCard(
                            "Daily Routes", 
                            "View assigned collection paths", 
                            Icons.route_rounded, 
                            const Color(0xFFE3F2FD), 
                            const Color(0xFF2196F3),
                            titleFontSize: titleFontSize,
                            subtitleFontSize: subtitleFontSize,
                            iconContainerSize: iconContainerSize,
                            iconSize: iconSize,
                            onTap: _showDailyRoutes,
                          ),
                          const SizedBox(height: 12),
                          _buildActionCard(
                            "Report Issue", 
                            "Log vehicle or collection problems", 
                            Icons.report_problem_rounded, 
                            const Color(0xFFFFF0F2), 
                            const Color(0xFFFF1744),
                            titleFontSize: titleFontSize,
                            subtitleFontSize: subtitleFontSize,
                            iconContainerSize: iconContainerSize,
                            iconSize: iconSize,
                            onTap: _showReportIssue,
                          ),
                          const SizedBox(height: 12),
                          _buildActionCard(
                            "Maintenance", 
                            "Check truck service schedule", 
                            Icons.engineering_rounded, 
                            const Color(0xFFFFF8E1), 
                            const Color(0xFFFFAB00),
                            titleFontSize: titleFontSize,
                            subtitleFontSize: subtitleFontSize,
                            iconContainerSize: iconContainerSize,
                            iconSize: iconSize,
                            onTap: _showMaintenanceSchedule,
                          ),
                        ],
                      ),
                    ),
        
                    const SizedBox(height: 24),
                    _buildTripInformation(),
                    const SizedBox(height: 24),
                    _buildGpsStatus(),
                    const SizedBox(height: 120),
                  ]),
                ),
              ]),
            );
          }
        ),
      ),
    );
  }

  Widget _buildDesktopDashboard() {
    final double screenWidth = MediaQuery.of(context).size.width;
    
    // Adaptive sizes for Quick Actions
    final double titleFontSize = 17.0;
    final double subtitleFontSize = 13.0;
    final double iconContainerSize = 52.0;
    final double iconSize = 26.0;

    return Column(
      children: [
        _buildWebHeader(),
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: (_manualPullDepth > 0 || _isRefreshing) 
                  ? const NeverScrollableScrollPhysics() 
                  : const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              child: AnimatedBuilder(
                animation: _scrollController,
                builder: (context, child) {
                  final double offset = _scrollController.hasClients ? _scrollController.offset : 0;
                  return Transform.translate(
                    offset: Offset(0, offset < 0 ? offset : 0),
                    child: Column(
                      children: [
                        const SizedBox(height: 32),
                        _buildWebBanner(),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // LEFT COLUMN (Flex 3)
                              Expanded(
                                flex: 3,
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _buildStatCard(
                                            "Start Time",
                                            _startTime,
                                            Icons.access_time_filled,
                                            const Color(0xFFE3F2FD),
                                            iconColor: Colors.blue,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: _buildStatCard(
                                            "Distance",
                                            "${_distance.toStringAsFixed(2)} km",
                                            Icons.route,
                                            const Color(0xFFF3E5F5),
                                            iconColor: Colors.purple,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: _buildStatCard(
                                            "Current Speed",
                                            "${_speed.toStringAsFixed(1)} km/h",
                                            Icons.speed_rounded,
                                            const Color(0xFFE8F5E9),
                                            iconColor: Colors.green,
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 24),
                                    _buildMapCard(MediaQuery.of(context).size.width),
                                    const SizedBox(height: 24),

                                    _buildTripInformation(),
                                    const SizedBox(height: 24),
                                    _buildGpsStatus(),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 24),
                              
                              // RIGHT COLUMN (Flex 2)
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildVehicleControls(MediaQuery.of(context).size.width),
                                    const SizedBox(height: 24),
                                    _buildActionsGrid(MediaQuery.of(context).size.width),
                                    const SizedBox(height: 24),
                                    _buildOptimizedRouteCard(MediaQuery.of(context).size.width),
                                    const SizedBox(height: 32),
                                    
                                    // QUICK ACTIONS FOR WEB
                                    const Padding(
                                      padding: EdgeInsets.fromLTRB(28, 0, 16, 16), // Aligned with card content
                                      child: Text("Quick Actions", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
                                    ),
                                    const SizedBox(height: 16),
                                    _buildActionCard(
                                      "Daily Routes", 
                                      "View assigned collection paths", 
                                      Icons.route_rounded, 
                                      const Color(0xFFE3F2FD), 
                                      const Color(0xFF2196F3),
                                      titleFontSize: titleFontSize,
                                      subtitleFontSize: subtitleFontSize,
                                      iconContainerSize: iconContainerSize,
                                      iconSize: iconSize,
                                      onTap: _showDailyRoutes,
                                    ),
                                    const SizedBox(height: 12),
                                    _buildActionCard(
                                      "Report Issue", 
                                      "Log vehicle or collection problems", 
                                      Icons.report_problem_rounded, 
                                      const Color(0xFFFFF0F2), 
                                      const Color(0xFFFF1744),
                                      titleFontSize: titleFontSize,
                                      subtitleFontSize: subtitleFontSize,
                                      iconContainerSize: iconContainerSize,
                                      iconSize: iconSize,
                                      onTap: _showReportIssue,
                                    ),
                                    const SizedBox(height: 12),
                                    _buildActionCard(
                                      "Maintenance", 
                                      "Check truck service schedule", 
                                      Icons.engineering_rounded, 
                                      const Color(0xFFFFF8E1), 
                                      const Color(0xFFFFAB00),
                                      titleFontSize: titleFontSize,
                                      subtitleFontSize: subtitleFontSize,
                                      iconContainerSize: iconContainerSize,
                                      iconSize: iconSize,
                                      onTap: _showMaintenanceSchedule,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _viewProfilePicture() {
    if (_user == null) return;

    final String profileUrl = (_user!.profilePicture != null && _user!.profilePicture!.isNotEmpty)
        ? _user!.profilePicture!
        : "";

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "ProfilePicture",
      barrierColor: Colors.black.withOpacity(0.5),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(color: Colors.transparent),
                ),
                Center(
                  child: Hero(
                    tag: 'profile_pic_${_user?.userId ?? 'default'}',
                    child: Container(
                      width: 300,
                      height: 300,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 30, spreadRadius: 10)
                        ],
                        image: profileUrl.isNotEmpty
                            ? DecorationImage(
                                image: NetworkImage(profileUrl),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: profileUrl.isEmpty
                          ? Center(
                              child: Text(
                                (_user?.name != null && _user!.name.isNotEmpty) ? _user!.name[0].toUpperCase() : "U",
                                style: const TextStyle(fontSize: 80, fontWeight: FontWeight.bold, color: Color(0xFF00695C)),
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(double width) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double screenWidth = MediaQuery.of(context).size.width;
    bool isMobile = width < 600;
    double bgHeight = isMobile ? (screenHeight * 0.22).clamp(180, 220) : 220;
    
    // Adaptive font sizes
    final double welcomeFontSize = (screenWidth * 0.035).clamp(11.0, 14.0);
    final double nameFontSize = (screenWidth * 0.05).clamp(16.0, 20.0);
    final double locationFontSize = (screenWidth * 0.03).clamp(10.0, 12.0);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 1. Green "Satin" Background
        Container(
          width: double.infinity,
          height: bgHeight,
          decoration: const BoxDecoration(
            color: Color(0xFF00695C),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
          ),
          child: Stack(
            children: [
              AnimatedBuilder(
                animation: _circleController,
                builder: (context, child) {
                  return CustomPaint(
                    size: Size(double.infinity, bgHeight),
                    painter: HeaderCirclePainter(_circleController.value),
                  );
                },
              ),
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Minimalist Clock
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _currentTime,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: (screenWidth * 0.035).clamp(11.0, 13.0),
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      // Action Icons
                      Row(
                        children: [
                          _buildHeaderActionIcon(
                            Icons.notifications_outlined,
                            badgeCount: _unreadNotifications > 0 ? _unreadNotifications : null,
                            onTap: () => _showNotificationsModal(context),
                          ),
                          const SizedBox(width: 10),
                          _buildHeaderActionIcon(
                            Icons.logout_rounded,
                            onTap: () => _showLogoutDialog(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // 2. Overlapping White Card
        Padding(
          padding: EdgeInsets.only(top: bgHeight - 60, left: 20, right: 20),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: AppTheme.balancedPulidongShadow,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: _viewProfilePicture,
                      child: Hero(
                        tag: 'profile_pic_${_user?.userId ?? 'default'}',
                        child: Container(
                          width: (screenWidth * 0.16).clamp(56.0, 64.0),
                          height: (screenWidth * 0.16).clamp(56.0, 64.0),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF00695C), width: 2),
                            image: (_user?.profilePicture != null && _user!.profilePicture!.isNotEmpty)
                                ? DecorationImage(
                                    image: NetworkImage(_user!.profilePicture!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: (_user?.profilePicture == null || _user!.profilePicture!.isEmpty)
                              ? Center(
                                  child: Text(
                                    (_user?.name != null && _user!.name.isNotEmpty) ? _user!.name[0].toUpperCase() : "D",
                                    style: TextStyle(fontSize: (screenWidth * 0.06).clamp(20.0, 24.0), fontWeight: FontWeight.bold, color: const Color(0xFF00695C)),
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Duty Tracker,",
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: welcomeFontSize,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _user?.name != null && _user!.name.isNotEmpty ? _user!.name : "Loading...",
                            style: TextStyle(
                              color: const Color(0xFF1A1A1A),
                              fontSize: nameFontSize,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.local_shipping_rounded, color: Color(0xFF00796B), size: 14),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  "Truck: ${_user?.preferredTruck ?? 'None'} | ${_truckPlateNumber ?? 'N/A'}",
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontSize: locationFontSize,
                                    fontWeight: FontWeight.w700
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _HoverZoomLink(
                      onTap: () {
                        if (_user == null) return;
                        _showStyledBottomSheet(
                          title: "Edit Account",
                          description: "Update your profile details and account settings here.",
                          showLoading: false,
                          maxHeightMultiplier: 0.9,
                          bottomPadding: 32,
                          children: [
                            DataManagementModal(
                              user: _user!,
                              onSuccess: _loadUser,
                            ),
                          ],
                        );
                      },
                      child: Text(
                        "Edit",
                        style: TextStyle(
                          color: const Color(0xFF00796B),
                          fontWeight: FontWeight.w800,
                          fontSize: (screenWidth * 0.035).clamp(12.0, 14.0),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                HoverActionButton(
                  text: "Track Work Map",
                  onTap: () => setState(() => _selectedIndex = 1),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderActionIcon(IconData icon, {int? badgeCount, VoidCallback? onTap, bool isDark = false}) {
    Color baseColor = isDark ? AppColors.tealText : Colors.white;
    Color bgColor = isDark ? AppColors.tealText.withOpacity(0.1) : Colors.white.withValues(alpha: 30 / 255);

    return _HoverZoomCard(
      onTap: onTap,
      scale: 1.1,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(14),
            border: isDark ? Border.all(color: AppColors.tealText.withOpacity(0.1)) : null,
          ),
          child: Icon(icon, color: baseColor, size: 24),
        ),
        if (badgeCount != null)
          Positioned(
            right: -2, top: -2,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: const BoxDecoration(color: Color(0xFFFF4081), shape: BoxShape.circle),
              child: Text("$badgeCount", style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
            ),
          ),
      ]),
    );
  }

  Color _buildStatusIndicatorColor() {
    switch(_status.toUpperCase()) {
      case "ACTIVE": return const Color(0xFF2E7D32); // Darker Green
      case "IDLE": return const Color(0xFFEF6C00); // Darker Orange
      case "FULL": return const Color(0xFFC2185B); // Darker Pink/Magenta
      case "FINISHED": 
      case "COMPLETED": return const Color(0xFF1976D2); // Darker Blue
      default: return Colors.grey.shade700;
    }
  }

  Widget _buildStatusIndicator() {
    Color color = _buildStatusIndicatorColor();
    String label = _status.toUpperCase();
    
    // Updated Status Mapping
    if (label == "FINISHED" || label == "DONE" || label == "COMPLETED") {
      label = "COMPLETED";
    } else if (label == "IDLE") {
      label = "IDLE";
    } else if (label == "ACTIVE" || label == "START") {
      label = "ACTIVE";
    } else if (label == "FULL") {
      label = "FULL";
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10), border: Border.all(color: color)),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900)),
    );
  }

  Widget _buildActionCard(String title, String subtitle, IconData icon, Color bgColor, Color iconColor, {
    required VoidCallback onTap, 
    double? titleFontSize, 
    double? subtitleFontSize, 
    double? iconContainerSize, 
    double? iconSize,
    bool isLoading = false,
  }) {
    return _HoverZoomCard(
      onTap: isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppTheme.balancedPulidongShadow,
        ),
        child: Row(children: [
          Container(
            width: iconContainerSize ?? 52, 
            height: iconContainerSize ?? 52, 
            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(16)), 
            child: isLoading 
              ? Center(child: Padding(padding: const EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 3, color: iconColor)))
              : Icon(icon, color: iconColor, size: iconSize ?? 26)
          ),
          const SizedBox(width: 20),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: titleFontSize ?? 17, color: const Color(0xFF1A1A1A))),
            Text(isLoading ? "Calculating optimized path..." : subtitle, style: TextStyle(fontSize: subtitleFontSize ?? 13, color: Colors.grey, fontWeight: FontWeight.w500)),
          ])),
          const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFE0E0E0), size: 16),
        ]),
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double titleFontSize = (screenWidth * 0.03).clamp(11.0, 13.0);
    final double valueFontSize = (screenWidth * 0.05).clamp(16.0, 20.0);
    final double iconSize = (screenWidth * 0.055).clamp(20.0, 24.0);

    return Container(
      padding: EdgeInsets.all((screenWidth * 0.04).clamp(12.0, 20.0)), 
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05), // Light background color
        borderRadius: BorderRadius.circular(24), 
        border: Border.all(color: color.withValues(alpha: 0.1), width: 2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(8), 
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle), 
          child: Icon(icon, color: color, size: iconSize)
        ),
        const SizedBox(height: 12),
        Text(title, style: TextStyle(fontSize: titleFontSize, color: color.darken(0.3), fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: valueFontSize, fontWeight: FontWeight.w900, color: color.darken(0.2))),
      ]),
    );
  }

  Widget _buildVehicleControls(double width) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double titleFontSize = (screenWidth * 0.045).clamp(16.0, 18.0);
    final double iconSize = (screenWidth * 0.045).clamp(16.0, 18.0);

    return Container(
      padding: EdgeInsets.all((screenWidth * 0.05).clamp(16.0, 28.0)), 
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(32),
        boxShadow: AppTheme.balancedPulidongShadow,
        border: Border.all(color: Colors.grey.shade100, width: 2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: AppColors.tealText.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.settings_input_component_rounded, color: AppColors.tealText, size: iconSize),
                ),
                const SizedBox(width: 12),
                Text("Vehicle Console", style: TextStyle(fontWeight: FontWeight.w900, fontSize: titleFontSize, color: const Color(0xFF1A1A1A))),
              ],
            ),
            // Minimal Duty Pulse
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _buildStatusIndicatorColor().withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: _buildStatusIndicatorColor(), shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(_status.toUpperCase(), style: TextStyle(color: _buildStatusIndicatorColor(), fontSize: 9, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          "Manage your trip status and collection progress.",
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 16),
        // Unified Control Pill - Responsive Row/Wrap
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F7F9),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Expanded(child: _buildConsoleButton("START", Icons.play_arrow_rounded, const Color(0xFF2E7D32), () {
                if (_sessionId == null) {
                  _startTripSession();
                } else {
                  _updateTripStatus("ACTIVE");
                }
              })),
              Expanded(child: _buildConsoleButton("PAUSE", Icons.pause_rounded, Colors.orange, () => _updateTripStatus("IDLE"))),
              Expanded(child: _buildConsoleButton("FULL", Icons.local_shipping_rounded, Colors.pink, _showFullConfirmation)),
              Expanded(child: _buildConsoleButton("DONE", Icons.check_rounded, Colors.blue, _showFinishConfirmation)),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildConsoleButton(String label, IconData icon, Color color, VoidCallback onTap) {
    String currentStatus = _status.toUpperCase();
    bool isSelected = false;
    
    if (label == "START") isSelected = currentStatus == "ACTIVE";
    else if (label == "PAUSE") isSelected = currentStatus == "IDLE";
    else if (label == "FULL") isSelected = currentStatus == "FULL";
    else if (label == "DONE") isSelected = currentStatus == "FINISHED" || currentStatus == "COMPLETED";

    return _HoverZoomCard(
      onTap: onTap,
      scale: 1.05,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected ? [
            BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))
          ] : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? Colors.white : color.withValues(alpha: 0.6), size: 24),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: isSelected ? Colors.white : color.withValues(alpha: 0.6), letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsGrid(double width) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF00897B).withValues(alpha: 0.85), // Lighter Professional Teal Toolbelt
        borderRadius: BorderRadius.circular(28),
        boxShadow: AppTheme.balancedPulidongShadow,
        border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              "Quick access to manual alerts and simulation.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.8), fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildToolPill("Manual Alert", Icons.notifications_active_rounded, Colors.white, () => _showAreaSelection("Manual Alert", _sendManualAlert, description: "Notify residents of your arrival in a specific area manually."))),
              Container(width: 1, height: 24, color: Colors.white.withValues(alpha: 0.2)),
              Expanded(child: _buildToolPill(_isSimulationMode ? "Real GPS" : "Simulation", _isSimulationMode ? Icons.location_on_rounded : Icons.directions_run_rounded, Colors.white, _handleSimulationToggle)),
              Container(width: 1, height: 24, color: Colors.white.withValues(alpha: 0.2)),
              Expanded(child: _buildToolPill("Progress", Icons.checklist_rtl_rounded, Colors.white, _showProgressModal)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToolPill(String label, IconData icon, Color color, VoidCallback onTap) {
    return _HoverZoomCard(
      onTap: onTap,
      scale: 1.05,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color.withOpacity(0.9), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
          ],
        ),
      ),
    );
  }

  void _showAreaSelection(String title, Function(String) onSelect, {String? description}) {
    _showStyledBottomSheet(
      title: title,
      description: description,
      loadingText: "Loading locations...",
      bottomPadding: 32,
      builder: (context, setModalState) {
        if (_purokConfigs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Column(
                children: [
                  CircularProgressIndicator(color: AppColors.tealText),
                  SizedBox(height: 16),
                  Text("Fetching collection areas...", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _purokConfigs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final area = _purokConfigs[i];
            return _HoverZoomCard(
              onTap: () {
                Navigator.pop(context);
                onSelect(area['name']);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade100, width: 1.5),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.tealText.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.location_on_rounded, color: AppColors.tealText, size: 20),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        area['name'],
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, color: Colors.black12, size: 14),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMapCard(double width) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: AppTheme.balancedPulidongShadow,
      ),
      child: Column(children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFFE3F2FD), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.location_on_rounded, color: Color(0xFF2196F3))
          ),
          title: const Text("Live Tracking", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          subtitle: const Text("Real-time truck locations", style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
          trailing: _HoverZoomLink(
            onTap: () => setState(() => _selectedIndex = 1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFFE0F2F1), borderRadius: BorderRadius.circular(12)),
              child: const Text("Full Map", style: TextStyle(color: Color(0xFF00796B), fontWeight: FontWeight.w900, fontSize: 13))
            ),
          ),
        ),
        Container(
          height: 300,
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 10 / 255), blurRadius: 10, offset: const Offset(0, 5))]
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: DriverTrackTruckScreen(
              isMiniMap: true,
              currentSessionId: _sessionId,
              focusTruckId: _user?.preferredTruck ?? "Unknown",
              isSimulation: _isSimulationMode,
              manualPosition: _currentPosition, // Pass current position for real-time dashboard tracking
              currentDistance: _distance,
              currentSpeed: _speed,
              startTime: _startTime,
              lastGpsUpdateTime: _lastGpsUpdateTime,
              onOptimize: _optimizeRoute,
              isOptimizing: _isOptimizing,
            )



          ),
        ),
        if (_optimizedData != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: HoverActionButton(
                    text: "SHOW RECOMMENDED ROUTE",
                    onTap: () => setState(() => _selectedIndex = 1),
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
          ),
      ]),
    );
  }

  Widget _buildOptimizedRouteCard(double width) {
    debugPrint("ROUTE CARD BUILD (isOptimizing: $_isOptimizing, hasData: ${_optimizedData != null})");
    
    // --- STATE 1: NO DATA OR CALCULATING (Action Card with In-Button Loading) ---
    if (_optimizedData == null) {
      return _buildActionCard(
        "Route Optimization", 
        "Calculate the fastest collection path", 
        Icons.alt_route_rounded, 
        const Color(0xFFE3F2FD), 
        const Color(0xFF2196F3), 
        isLoading: _isOptimizing,
        onTap: () {
          debugPrint("ROUTE OPTIMIZATION CARD CLICKED");
          _optimizeRoute();
        }
      );
    }

    // --- STATE 2: OPTIMIZATION READY (Enhanced Professional Layout) ---
    final stops = _optimizedData!['stops'] as List;
    final nextStop = stops.firstWhere((s) => _purokStatus[s['area_name'].replaceAll('/', '_')]?['completed'] != true, orElse: () => stops.first);
    final int remainingCount = stops.where((s) => _purokStatus[s['area_name'].replaceAll('/', '_')]?['completed'] != true).length;

    return _HoverZoomCard(
      onTap: _showOptimizationDetails,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: AppTheme.balancedPulidongShadow,
          border: Border.all(color: AppColors.tealText.withValues(alpha: 0.1), width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: AppColors.tealText.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.alt_route_rounded, color: AppColors.tealText, size: 16),
                    ),

                    const SizedBox(width: 10),
                    const Text("OPTIMIZED ROUTE", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.tealText, letterSpacing: 0.5)),
                  ],
                ),
                _HoverZoomLink(
                  onTap: _optimizeRoute,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: AppColors.tealText.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      children: [
                        if (_isOptimizing) 
                          const Padding(padding: EdgeInsets.only(right: 6), child: SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.tealText)))
                        else
                          const Icon(Icons.refresh_rounded, color: AppColors.tealText, size: 12),
                        const SizedBox(width: 4),
                        const Text("RE-OPTIMIZE", style: TextStyle(color: AppColors.tealText, fontWeight: FontWeight.w900, fontSize: 10)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade100),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.location_on_rounded, color: Color(0xFF2E7D32), size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Next Priority Stop", style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w700)),
                        Text(nextStop['area_name'], style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF1A1A1A)), overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      children: [
                        const Text("ETA", style: TextStyle(color: Colors.blue, fontSize: 9, fontWeight: FontWeight.w800)),
                        Text(nextStop['estimated_arrival'], style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.blue)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildOptimizedMetric("Pending", "$remainingCount Areas"),
                _buildOptimizedMetric("Distance", "${(_optimizedData!['total_distance_km'] as num).toStringAsFixed(1)} km"),
                _buildOptimizedMetric("Est. Finish", _optimizedData!['estimated_completion']),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptimizedMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.w600)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF2C3E50))),
      ],
    );
  }

  Widget _buildTripInformation() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: AppTheme.balancedPulidongShadow,
        border: Border.all(color: Colors.grey.shade100, width: 2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: AppColors.tealText.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.info_outline_rounded, color: AppColors.tealText, size: 18),
            ),
            const SizedBox(width: 12),
            const Text("Trip Information", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF1A1A1A))),
          ],
        ),
        const SizedBox(height: 4),
        const Text("General metadata and session information for the current trip.", style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
        const SizedBox(height: 20),
        _buildInfoRow("Truck Number", _user?.preferredTruck ?? "Unknown", color: AppColors.tealText),
        const Divider(height: 24),
        _buildInfoRow("Plate Number", _truckPlateNumber ?? "N/A", isBold: true),
        const Divider(height: 24),
        _buildInfoRow("Start Time", _startTime),
        const Divider(height: 24),
        _buildInfoRow("Estimated End", _calculateEstimatedEnd()),
        const Divider(height: 24),
        _buildInfoRow("Total Distance", "${_distance.toStringAsFixed(1)} km", color: Colors.orangeAccent.shade200),
      ]),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? color, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600, fontSize: 14)),
        Text(
          value,
          style: TextStyle(
            color: color ?? const Color(0xFF2C3E50),
            fontWeight: isBold ? FontWeight.w900 : FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ],
    );
  }

  String _calculateEstimatedEnd() {
    if (_startTime == "--:--" || _startDateTime == null || _sessionId == null) {
      return "--:--";
    }
    // Assuming a 4-hour shift for estimation
    final end = _startDateTime!.add(const Duration(hours: 4));
    return DateFormat('h:mm a').format(end);
  }

  Widget _buildGpsStatus() {
    bool isSearching = _currentPosition == null;
    Color statusColor = isSearching ? Colors.orange : Colors.green;
    String statusText = isSearching ? "Searching..." : "Strong";

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: AppTheme.balancedPulidongShadow,
        border: Border.all(color: Colors.grey.shade100, width: 2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
            const SizedBox(width: 12),
            const Text("GPS Status", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF1A1A1A))),
          ],
        ),
        const SizedBox(height: 4),
        const Text("Real-time satellite connection and location accuracy.", style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Signal Strength", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600, fontSize: 14)),
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
                  Text(statusText, style: TextStyle(fontWeight: FontWeight.w900, color: statusColor, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
        const Divider(height: 24),
        _buildInfoRow("Accuracy", isSearching ? "Waiting for fix..." : "±${_currentPosition!.accuracy.toInt()} meters"),
        const Divider(height: 24),
        _buildInfoRow("Last Update", _lastGpsUpdateTime != null ? DateFormat('hh:mm:ss a').format(_lastGpsUpdateTime!) : "Waiting..."),
      ]),
    );
  }

  void _showDailyRoutes() async {
    if (_user == null) return;
    if (_isNavigating) return;
    setState(() => _isNavigating = true);

    try {
      _showStyledBottomSheet(
        title: "Daily Routes",
        description: "View and track your assigned collection paths for the day.",
        loadingText: "Loading collection routes...",
        bottomPadding: 20,
        children: [
          StreamBuilder(
            stream: _database.ref('driver_routes').orderByChild('driver_id').equalTo(_user?.userId).onValue,
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text("Error: ${snapshot.error}");
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: AppColors.tealText)));
              }
              if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
                return const Center(child: Padding(padding: EdgeInsets.all(40), child: Text("No assigned routes found.", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))));
              }
              
              final Map data = snapshot.data!.snapshot.value as Map;
              final List routes = [];
              data.forEach((k, v) => routes.add({...v as Map, 'id': k}));
              routes.sort((a, b) => (b['created_at'] ?? 0).compareTo(a['created_at'] ?? 0));

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: routes.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final r = routes[i];
                  String status = (r['route_status'] ?? "PENDING").toString().toUpperCase();
                  Color statusColor = status == "COMPLETED" ? Colors.green : Colors.blue;

                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white, 
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 10, offset: const Offset(0, 4))],
                      border: Border.all(color: Colors.grey.shade300, width: 1.5)
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              r['route_date'] ?? "Current Route", 
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.grey)
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                              child: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.w900, fontSize: 10)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          r['route_name'] ?? "Morning Collection", 
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF2C3E50))
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.route_rounded, size: 14, color: Colors.grey),
                            const SizedBox(width: 6),
                            Text("${r['total_distance_km'] ?? '0.0'} km covered", style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          )
        ],
      );
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  void _showReportIssue() async {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);

    try {
      await Geolocator.checkPermission();
      final descCtrl = TextEditingController();
      final typeCtrl = TextEditingController(text: "Engine");
      final urgencyCtrl = TextEditingController(text: "Medium");

      final typeFocus = FocusNode();
      final urgencyFocus = FocusNode();
      final descFocus = FocusNode();
      
      String? descError;

      if (!mounted) return;

      _showModal("Report Truck Issue", [
        const SizedBox(height: 8),
        // Custom Picker for Issue Type
        StatefulBuilder(
          builder: (context, setModalState) {
            typeFocus.addListener(() { if (mounted) setModalState(() {}); });
            return _buildTextField(
              "Issue Type", 
              typeCtrl, 
              focusNode: typeFocus,
              readOnly: true,
              hintText: "Select issue category",
              prefixIcon: Icons.category_outlined,
              suffixIcon: Icons.keyboard_arrow_down_rounded,
              onTap: () {
                typeFocus.requestFocus();
                _showSelectionPicker(
                  title: "Select Issue Category",
                  options: ["Engine", "Tires", "Brakes", "GPS", "Electrical", "Fuel", "Transmission", "Hydraulic System", "Body Damage", "Other"],
                  selectedValue: typeCtrl.text,
                  focusNode: typeFocus,
                  onSelect: (v) {
                    typeCtrl.text = v;
                    setModalState(() {});
                  },
                );
              },
            );
          }
        ),
        
        // Custom Picker for Urgency
        StatefulBuilder(
          builder: (context, setModalState) {
            urgencyFocus.addListener(() { if (mounted) setModalState(() {}); });
            return _buildTextField(
              "Urgency Level", 
              urgencyCtrl, 
              focusNode: urgencyFocus,
              readOnly: true,
              hintText: "Select urgency level",
              prefixIcon: Icons.priority_high_rounded,
              suffixIcon: Icons.keyboard_arrow_down_rounded,
              onTap: () {
                urgencyFocus.requestFocus();
                _showSelectionPicker(
                  title: "Select Urgency Level",
                  options: ["Low", "Medium", "High", "Critical"],
                  selectedValue: urgencyCtrl.text,
                  focusNode: urgencyFocus,
                  onSelect: (v) {
                    urgencyCtrl.text = v;
                    setModalState(() {});
                  },
                );
              },
            );
          }
        ),

        StatefulBuilder(
          builder: (context, setModalState) {
            descFocus.addListener(() { if (mounted) setModalState(() {}); });
            void validateDesc(String val) {
              if (val.trim().isEmpty) {
                setModalState(() => descError = "Description is required");
              } else {
                setModalState(() => descError = null);
              }
            }

            return _buildTextField(
              "Brief Description", 
              descCtrl, 
              focusNode: descFocus,
              maxLines: 4, 
              hintText: "Enter your brief description",
              prefixIcon: Icons.description_outlined,
              errorText: descError,
              onChanged: validateDesc,
            );
          }
        ),
      ], "Submit Report", () async {
        final description = descCtrl.text.trim();
        if (description.isEmpty) return false;
        try {
          Position? pos;
          try {
            pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low, timeLimit: const Duration(seconds: 3));
          } catch (_) {}
          final truckId = _user?.preferredTruck ?? "Unknown";
          final newIssueRef = _database.ref('truck_issues').push();
          final String issueId = newIssueRef.key ?? '';
          await newIssueRef.set({
            'driverId': _user?.userId,
            'driverName': _user?.name,
            'truckId': truckId,
            'issueType': typeCtrl.text,
            'description': description,
            'urgency': urgencyCtrl.text,
            'latitude': pos?.latitude ?? 0.0,
            'longitude': pos?.longitude ?? 0.0,
            'createdAt': ServerValue.timestamp,
            'updatedAt': ServerValue.timestamp,
            'status': 'PENDING',
            'isReadByDriver': false,
            'isReadByAdmin': false,
          });
          await _database.ref('notifications').push().set({
            'type': 'DRIVER_ISSUE',
            'title': 'New Truck Issue Reported',
            'message': '${_user?.name} reported a ${typeCtrl.text} issue for $truckId',
            'truck_id': truckId,
            'driver_id': _user?.userId.toString(),
            'relatedId': issueId,
            'targetRole': 'admin',
            'timestamp': ServerValue.timestamp,
            'isRead': false,
          });
          return true;
        } catch (_) { return false; }
      }, successMessage: "Successful submit complaint", maxHeightMultiplier: 0.85);
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  void _showMaintenanceSchedule() async {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);
    try {
      final truckId = _user?.preferredTruck ?? "Unknown";
      await _initializeMaintenanceIfNeeded(truckId);
      if (!context.mounted) return;
      _showStyledBottomSheet(
        title: "Maintenance Schedule",
        description: "Monitor upcoming service requirements and truck health status.",
        loadingText: "Fetching maintenance schedule...",
        bottomPadding: 20,
        children: [
          const SizedBox(height: 8),
          StreamBuilder<DatabaseEvent>(
            stream: _database.ref('truck_locations/$truckId').onValue,
            builder: (context, locSnapshot) {
              double currentTripDist = 0.0;
              if (locSnapshot.hasData && locSnapshot.data!.snapshot.value != null) {
                final loc = locSnapshot.data!.snapshot.value as Map;
                if (loc['current_session'] != null) currentTripDist = (loc['distance'] ?? 0.0).toDouble();
              }
              return StreamBuilder<DatabaseEvent>(
                stream: _database.ref('trucks/$truckId/maintenance').onValue,
                builder: (context, snapshot) {
                  if (snapshot.hasError) return Text("Error: ${snapshot.error}");
                  if (!snapshot.hasData || snapshot.data!.snapshot.value == null) return const Center(child: CircularProgressIndicator(color: AppColors.tealText));
                  final Map data = snapshot.data!.snapshot.value as Map;
                  return Column(
                    children: [
                      _buildMaintenanceItem("Oil Change", data['oilChange'], "oilChange", truckId, currentTripDist: currentTripDist),
                      const SizedBox(height: 12),
                      _buildMaintenanceItem("Tire Rotation", data['tireRotation'], "tireRotation", truckId, currentTripDist: currentTripDist),
                      const SizedBox(height: 12),
                      _buildMaintenanceItem("Full Inspection", data['fullInspection'], "fullInspection", truckId, currentTripDist: currentTripDist),
                    ],
                  );
                },
              );
            }
          )
        ],
      );
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Future<void> _initializeMaintenanceIfNeeded(String truckId) async {
    final ref = _database.ref('trucks/$truckId');
    final snapshot = await ref.get();
    bool needsInit = true;
    if (snapshot.exists) {
      final data = snapshot.value as Map;
      if (data.containsKey('maintenance')) needsInit = false;
    }
    if (needsInit) {
      await ref.update({
        'odometerKm': 0.0,
        'maintenance': {
          'oilChange': {'intervalKm': 5000.0, 'remainingKm': 5000.0, 'lastServiceAt': null, 'status': "NORMAL", 'notified500': false, 'notified100': false, 'notifiedDue': false},
          'tireRotation': {'intervalKm': 10000.0, 'remainingKm': 10000.0, 'lastServiceAt': null, 'status': "NORMAL", 'notified500': false, 'notified100': false, 'notifiedDue': false},
          'fullInspection': {'intervalKm': 20000.0, 'remainingKm': 20000.0, 'lastServiceAt': null, 'status': "NORMAL", 'notified500': false, 'notified100': false, 'notifiedDue': false}
        }
      });
    }
  }

  Widget _buildMaintenanceItem(String title, dynamic item, String key, String truckId, {double currentTripDist = 0.0}) {
    if (item == null) return const SizedBox.shrink();
    double savedRemaining = (item['remainingKm'] ?? 0.0).toDouble();
    double remaining = savedRemaining - currentTripDist;
    if (remaining < -9999) remaining = -9999;
    String status = "NORMAL";
    Color statusColor = Colors.green;
    if (remaining <= 0) { status = "SERVICE DUE"; statusColor = Colors.red; }
    else if (remaining <= 100) { status = "URGENT"; statusColor = Colors.redAccent; }
    else if (remaining <= 500) { status = "DUE SOON"; statusColor = Colors.orange; }
    String subText = remaining <= 0 ? "Overdue by ${(remaining.abs()).toStringAsFixed(1)} km" : "Remaining: ${remaining.toStringAsFixed(1)} km";
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade300, width: 1.5), boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Row(
        children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF1A1A1A))), const SizedBox(height: 4), Text(subText, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600))])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.w900, fontSize: 10))),
            const SizedBox(height: 8),
            _HoverZoomLink(onTap: (remaining > 500) ? null : () => _handleMarkMaintenanceDone(truckId, key, item['intervalKm'] ?? 5000.0), child: Text("MARK DONE", style: TextStyle(color: (remaining > 500) ? Colors.grey.shade300 : AppColors.tealText, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5))),
          ]),
        ],
      ),
    );
  }

  Future<void> _handleMarkMaintenanceDone(String truckId, String key, double interval) async {
    try {
      await _database.ref('trucks/$truckId/maintenance/$key').update({'status': 'NORMAL', 'remainingKm': interval, 'lastServiceAt': ServerValue.timestamp, 'notified500': false, 'notified100': false, 'notifiedDue': false});
      if (mounted) CustomSnackBar.show(context, message: "Maintenance task completed!");
    } catch (_) {}
  }

  void _showModal(String title, List<Widget> body, String? btnText, Future<bool> Function()? onBtnTap, {String loadingText = "Saving changes...", String? description, String? successMessage, double maxHeightMultiplier = 0.6}) async {
    _showStyledBottomSheet(
      title: title,
      description: description ?? (title.contains("Report") ? "Log any vehicle problems or mechanical issues for maintenance review." : null),
      maxHeightMultiplier: maxHeightMultiplier,
      loadingText: title.contains("Report") ? "Preparing report form..." : "Preparing modal...",
      bottomPadding: btnText != null ? 24.0 : 20.0,
      children: [
        ...body,
        if (btnText != null) ...[
          const SizedBox(height: 12),
          StatefulBuilder(builder: (innerCtx, setInnerState) {
            bool isModalLoading = false;
            return HoverActionButton(
              text: btnText,
              loadingText: loadingText,
              isLoading: isModalLoading,
              useZoom: true,
              onTap: isModalLoading ? null : () async {
                bool confirmed = await _showConfirmDialog(
                  title: title.contains("Report") ? "Submit Report?" : "Save Changes?", 
                  message: title.contains("Report") ? "Are you sure you want to submit this issue report?" : "Are you sure you want to proceed?", 
                  icon: Icons.help_outline_rounded
                );
                if (confirmed && onBtnTap != null) {
                  setInnerState(() => isModalLoading = true);
                  try {
                    bool success = await onBtnTap();
                    if (mounted) {
                      setInnerState(() => isModalLoading = false);
                      if (success) {
                        Navigator.pop(innerCtx);
                        if (successMessage != null) {
                          CustomNotification.showTopNotification(context, successMessage, false);
                        } else {
                          CustomNotification.showTopNotification(
                            context, 
                            title.contains("Report") ? "Report submitted successfully." : "Changes saved successfully.",
                            false
                          );
                        }
                      } else {
                        CustomNotification.showTopNotification(context, "Action failed. Please try again.", true);
                      }
                    }
                  } catch (_) { if (mounted) setInnerState(() => isModalLoading = false); }
                }
              },
            );
          }),
        ],
      ],
    );
  }

  void _showSelectionPicker({required String title, required List<String> options, String? selectedValue, required Function(String) onSelect, FocusNode? focusNode}) {
    _showStyledBottomSheet(
      title: title,
      loadingText: "Preparing options...",
      bottomPadding: 20,
      children: [
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: options.length,
          itemBuilder: (context, i) {
            bool isSelected = options[i] == selectedValue;
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              title: Text(
                options[i], 
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600, 
                  color: isSelected ? AppColors.tealText : const Color(0xFF2C3E50),
                  fontSize: 16
                )
              ),
              trailing: isSelected 
                ? const Icon(Icons.check_circle_rounded, color: AppColors.tealText, size: 24)
                : Icon(Icons.circle_outlined, color: Colors.grey.shade300, size: 24),
              onTap: () {
                onSelect(options[i]);
                Navigator.pop(context);
                if (focusNode != null) focusNode.requestFocus();
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {
    bool obscureText = false, 
    TextInputType? keyboardType, 
    int maxLines = 1, 
    bool readOnly = false, 
    VoidCallback? onTap, 
    String? hintText, 
    IconData? suffixIcon, 
    IconData? prefixIcon,
    bool isPassword = false, 
    bool isObscured = true, 
    VoidCallback? onToggleVisibility, 
    String? errorText, 
    Color? errorColor,
    FocusNode? focusNode,
    Function(String)? onChanged,
  }) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double labelFontSize = (screenWidth * 0.035).clamp(11.0, 13.0);
    final double inputFontSize = (screenWidth * 0.04).clamp(13.0, 15.0);
    final double hintFontSize = (screenWidth * 0.035).clamp(12.0, 14.0);
    final double errorFontSize = (screenWidth * 0.03).clamp(10.0, 11.0);

    bool hasFocus = focusNode?.hasFocus ?? false;
    bool isError = errorText != null && (errorColor == null || errorColor == Colors.redAccent);
    Color activeColor = isError ? Colors.redAccent : AppColors.tealText;
    Color iconColor = hasFocus ? activeColor : Colors.grey.shade400;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8), 
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 2), 
            child: Text(label, style: TextStyle(fontSize: labelFontSize, fontWeight: FontWeight.w800, color: const Color(0xFF1A1A1A), letterSpacing: 0.2)),
          ),
          Theme(
            data: Theme.of(context).copyWith(
              textSelectionTheme: TextSelectionThemeData(
                selectionColor: AppColors.tealText.withValues(alpha: 0.2),
                selectionHandleColor: AppColors.tealText,
              ),
            ),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              obscureText: isPassword ? isObscured : obscureText,
              keyboardType: keyboardType,
              maxLines: maxLines,
              readOnly: readOnly,
              onTap: onTap,
              onChanged: onChanged,
              cursorColor: const Color(0xFF424242),
              style: TextStyle(fontWeight: FontWeight.w700, color: const Color(0xFF2C3E50), fontSize: inputFontSize),
              decoration: InputDecoration(
                hintText: hintText ?? "Enter your ${label.toLowerCase()}",
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: hintFontSize, fontWeight: FontWeight.w400),
                filled: true,
                fillColor: const Color(0xFFF7F8FA),
                prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: iconColor, size: 20) : null,
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: isError ? Colors.redAccent : (errorColor == Colors.blueAccent ? Colors.blueAccent : Colors.grey.shade200), width: 1.2)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: activeColor, width: 2.0)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                suffixIcon: isPassword 
                  ? IconButton(
                      icon: Icon(isObscured ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: iconColor, size: 20),
                      onPressed: onToggleVisibility,
                    )
                  : (suffixIcon != null ? Icon(suffixIcon, color: iconColor) : null),
              ),
            ),
          ),
          if (errorText != null)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 10),
              child: Text(errorText, style: TextStyle(color: errorColor ?? Colors.redAccent, fontSize: errorFontSize, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  void _showProgressModal() {
    _showStyledBottomSheet(
      title: "Duty Progress",
      description: "Monitor the completion status of collection points in your current route.",
      loadingText: "Calculating progress...",
      builder: (context, setModalState) {
        if (_purokConfigs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Column(
                children: [
                  CircularProgressIndicator(color: AppColors.tealText),
                  SizedBox(height: 16),
                  Text("Loading collection areas...", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          );
        }

        double percent = _totalPuroks > 0 ? (_completedCount / _totalPuroks) : 0.0;
        if (percent.isNaN) percent = 0.0;

        return Column(
          children: [
            Center(
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 100, height: 100,
                        child: CircularProgressIndicator(
                          value: percent,
                          strokeWidth: 10,
                          backgroundColor: Colors.grey.shade100,
                          color: AppColors.tealText,
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                      Text("${(percent * 100).toInt()}%", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: AppColors.tealText)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text("Current shift completion status", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 32),
                ],
              ),
            ),
            ListView.separated(
              shrinkWrap: true, 
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _purokConfigs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final p = _purokConfigs[i];
                final String key = p['name'].replaceAll('/', '_');
                final statusData = _purokStatus[key] ?? {'completed': false};
                bool done = statusData['completed'] == true;
                
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18), 
                  decoration: BoxDecoration(
                    color: done ? const Color(0xFFE8F5E9) : const Color(0xFFF8F9FA), 
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: done ? const Color(0xFF81C784).withValues(alpha: 0.3) : Colors.grey.shade100,
                      width: 1.5,
                    ),
                    boxShadow: done ? [
                      BoxShadow(color: Colors.green.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))
                    ] : null,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: done ? Colors.white : Colors.white70,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 5, spreadRadius: 1)
                          ],
                        ),
                        child: Icon(
                          done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, 
                          color: done ? const Color(0xFF2E7D32) : Colors.grey.shade400, 
                          size: 22
                        ),
                      ),
                      const SizedBox(width: 16), 
                      Expanded(
                        child: Text(
                          p['name'], 
                          style: TextStyle(
                            fontWeight: done ? FontWeight.w900 : FontWeight.w700, 
                            fontSize: 15,
                            color: done ? const Color(0xFF1B5E20) : const Color(0xFF2C3E50)
                          )
                        )
                      ),
                      if (done)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            "DONE", 
                            style: TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.5)
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _showStyledBottomSheet({
    required String title, 
    Widget? titleWidget, // Added titleWidget parameter
    List<Widget>? children, 
    Widget Function(BuildContext, StateSetter)? builder, 
    String? description, 
    double maxHeightMultiplier = 0.6, 
    bool showLoading = true, 
    String? loadingText,
    double bottomPadding = 20.0,
  }) {
    bool isModalLoading = showLoading;
    
    if (Responsive.isDesktop(context)) {
      showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setModalState) {
            if (isModalLoading) {
              Future.delayed(const Duration(milliseconds: 600), () {
                if (mounted) setModalState(() => isModalLoading = false);
              });
            }

            return Dialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOutCubic,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                ),
                constraints: BoxConstraints(
                  maxWidth: 550, 
                  maxHeight: isModalLoading ? 300 : MediaQuery.of(context).size.height * 0.85,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(child: titleWidget ?? Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.tealText))),
                              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.grey)),
                            ],
                          ),
                          if (description != null) ...[
                            const SizedBox(height: 8),
                            Text(description, style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
                          ],
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Divider(height: 1, color: Color(0xFFEEEEEE)),
                          ),
                        ],
                      ),
                    ),
                    if (isModalLoading)
                      Container(
                        height: 200,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(40),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(color: AppColors.tealText, strokeWidth: 3),
                                const SizedBox(height: 16),
                                Text(loadingText ?? "Preparing content...", style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: builder != null 
                            ? Scrollbar(child: SingleChildScrollView(padding: EdgeInsets.fromLTRB(32, 4, 32, bottomPadding), child: builder(context, setModalState)))
                            : Scrollbar(child: SingleChildScrollView(padding: EdgeInsets.fromLTRB(32, 4, 32, bottomPadding), child: Column(mainAxisSize: MainAxisSize.min, children: children ?? []))),
                      ),
                  ],
                ),
              ),
            );
          }
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          if (isModalLoading) {
            Future.delayed(const Duration(milliseconds: 600), () {
              if (mounted) setModalState(() => isModalLoading = false);
            });
          }

          return Container(
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOutCubic,
              constraints: BoxConstraints(
                maxHeight: isModalLoading ? 350 : MediaQuery.of(context).size.height * maxHeightMultiplier
              ),
              padding: EdgeInsets.fromLTRB(0, 12, 0, MediaQuery.of(context).viewInsets.bottom),
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
                        Expanded(child: titleWidget ?? Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.tealText))),
                      ],
                    ),
                  ),
                  if (description != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 4, 32, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          description,
                          textAlign: TextAlign.left,
                          style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32, vertical: 8),
                    child: Divider(height: 1, color: Color(0xFFEEEEEE)),
                  ),
                  if (isModalLoading)
                    Container(
                      height: 200,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(color: AppColors.tealText, strokeWidth: 3),
                              const SizedBox(height: 16),
                              Text(loadingText ?? "Preparing content...", style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: builder != null 
                          ? Scrollbar(child: SingleChildScrollView(padding: EdgeInsets.fromLTRB(32, 4, 32, bottomPadding), child: builder(context, setModalState)))
                          : Scrollbar(child: SingleChildScrollView(padding: EdgeInsets.fromLTRB(32, 4, 32, bottomPadding), child: Column(mainAxisSize: MainAxisSize.min, children: children ?? []))),
                    ),
                ],
              ),
            ),
          );
        }
      ),
    );
  }

  void _showFullConfirmation() async {
    _updateTripStatus("FULL");
  }

  void _showFinishConfirmation() async {
    debugPrint("[FINISH] DONE button clicked. Attempting to resolve session state...");
    
    // We no longer block the button if session Id is null.
    // Instead, we always show the confirmation and handle recovery/cleanup inside finish Trip.

    bool confirmed = await _showConfirmDialog(
      title: "Finish Trip?",
      message: "Are you sure you want to finalize this collection session? All data will be saved to history.",
      icon: Icons.check_circle_outline_rounded,
      confirmColor: Colors.blue,
    );

    debugPrint("[FINISH] FINISH CONFIRM CLICKED: $confirmed");
    if (confirmed) {
      if (!mounted) return;
      _finishTrip();
    }
  }

  Future<void> _optimizeRoute({bool isAuto = false}) async {
    debugPrint("OPTIMIZE HANDLER ENTERED (isAuto: $isAuto)");
    
    if (_isOptimizing) {
      debugPrint("INFO: Already optimizing. Ignoring click.");
      return;
    }

    // ALWAYS show loading spinner in the background card/panel
    debugPrint("LOADING UI SHOWN IMMEDIATELY");
    setState(() => _isOptimizing = true);

    try {
      if (_sessionId == null) {
        debugPrint("FAILURE: _sessionId is NULL. Cannot optimize.");
        if (!isAuto) CustomSnackBar.show(context, message: "No active session found. Please start a trip.", isError: true);
        return;
      }
      
      // Resolve location with strict priority
      Position? targetPos;
      
      // 1. Check if _currentPosition is valid and fresh (last update within 30 seconds)
      if (_currentPosition != null && _lastGpsUpdateTime != null && 
          DateTime.now().difference(_lastGpsUpdateTime!).inSeconds < 30) {
        targetPos = _currentPosition;
        debugPrint("USING FRESH POSITION: ${targetPos!.latitude}, ${targetPos!.longitude}");
      } 
      
      // 2. Fallback: Explicit geolocator call
      if (targetPos == null) {
        try {
          debugPrint("STALE GPS: Requesting explicit fix...");
          targetPos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.bestForNavigation,
            timeLimit: const Duration(seconds: 5),
          );
          if (mounted) {
            setState(() {
              _currentPosition = targetPos;
              _lastGpsUpdateTime = DateTime.now();
            });
          }
          debugPrint("GPS RESOLVED: ${targetPos!.latitude}, ${targetPos!.longitude}");
        } catch (e) {
          debugPrint("GPS RESOLUTION FAILED: $e");
        }
      }

      if (targetPos == null) {
        debugPrint("FAILURE: targetPos is NULL (GPS not resolved).");
        if (!isAuto) CustomSnackBar.show(context, message: "Waiting for your current GPS location.", isError: true);
        return;
      }

      debugPrint("WEEKLY PROGRESS READY: ${!_isWeeklyProgressLoading}");
      
      if (_purokConfigs.isEmpty) {
        debugPrint("[OPTIMIZER] Purok configs empty. Attempting to reload...");
        await _loadPuroks(showFeedback: !isAuto);
      }

      final List<Map<String, dynamic>> remaining = [];
      final List<Map<String, dynamic>> assigned = List.from(_purokConfigs);
      
      // ========== WEEKLY PROGRESS DEBUG ==========
      debugPrint("========== WEEKLY PROGRESS DEBUG ==========");
      debugPrint("CURRENT DRIVER ID: ${_user?.userId}");
      debugPrint("CURRENT WEEK KEY: $_currentWeekKey");
      debugPrint("CURRENT WEEKLY PATH: weekly_collection_progress/$_currentWeekKey/${_user?.userId}/areas/");
      debugPrint("ASSIGNED AREAS COUNT (Authoritative): ${assigned.length}");
      debugPrint("WEEKLY AREA RECORD COUNT (Firebase): ${_purokStatus.length}");
      debugPrint("COMPLETED COUNT (State): $_completedCount");
      debugPrint("IS LOADING: $_isWeeklyProgressLoading");
      
      debugPrint("--- AREA STATUS TRACE ---");
      List<String> missingCoords = [];

      for (var area in assigned) {
        String areaId = area['id'].toString();
        final weeklyRecord = _purokStatus[areaId];
        bool recordExists = weeklyRecord != null;
        bool isCompleted = recordExists && weeklyRecord['completed'] == true;
        
        // Coordinate Validation
        final double lat = (area['lat'] ?? 0.0).toDouble();
        final double lng = (area['lng'] ?? 0.0).toDouble();
        bool hasValidCoords = (lat != 0.0 && lng != 0.0);

        debugPrint("AREA: ${area['name']}");
        debugPrint("  - id: $areaId");
        debugPrint("  - weekly record exists? $recordExists");
        debugPrint("  - completed field value: ${recordExists ? weeklyRecord['completed'] : 'N/A'}");
        debugPrint("  - valid coordinates? $hasValidCoords ($lat, $lng)");
        debugPrint("  - final derived status: ${isCompleted ? 'COMPLETED' : 'PENDING'}");
        
        if (!isCompleted) {
          if (hasValidCoords) {
            remaining.add({
              'name': area['name'],
              'lat': lat,
              'lng': lng,
            });
          } else {
            missingCoords.add(area['name']);
            debugPrint("  -> SKIPPING due to missing coordinates.");
          }
        }
      }
      debugPrint("-------------------------");
      debugPrint("FINAL PENDING COUNT: ${remaining.length}");
      if (missingCoords.isNotEmpty) {
        debugPrint("AREAS WITH MISSING COORDS: $missingCoords");
      }
      debugPrint("===========================================");

      if (assigned.isEmpty) {
        debugPrint("FAILURE: No assigned collection areas loaded.");
        if (!isAuto) {
          CustomSnackBar.show(context, message: "Unable to load assigned collection areas.", isError: true);
        }
        return;
      }

      if (missingCoords.isNotEmpty && !isAuto) {
        CustomSnackBar.show(context, message: "Missing coordinates for: ${missingCoords.join(', ')}", isError: true);
      }

      if (!_isWeeklyProgressLoading && _totalPuroks > 0 && _completedCount >= _totalPuroks) {
        debugPrint("FAILURE: All areas completed (Condition: completedCount >= totalPuroks).");
        if (!isAuto) {
          CustomSnackBar.show(context, message: "All assigned collection areas have been completed!");
        }
        return;
      }

      if (remaining.isEmpty) {
        debugPrint("[OPTIMIZER] No remaining areas to optimize (Loading: $_isWeeklyProgressLoading, Total: $_totalPuroks, Remaining: ${remaining.length})");
        if (!isAuto) {
          if (_isWeeklyProgressLoading) {
            CustomSnackBar.show(context, message: "Loading collection progress... Please try again in a moment.");
          } else {
            // This should only happen if assigned count matches completed count accurately
            CustomSnackBar.show(context, message: "All assigned collection areas have been completed!");
          }
        }
        return;
      }

      // ========== OPTIMIZER FINAL INPUT ==========
      debugPrint("========== OPTIMIZER FINAL INPUT ==========");
      debugPrint("DRIVER: ${targetPos.latitude}, ${targetPos.longitude}");
      for (int i = 0; i < remaining.length; i++) {
        final s = remaining[i];
        debugPrint("STOP ${i+1}:");
        debugPrint("  NAME: ${s['name']}");
        debugPrint("  LAT/LNG: ${s['lat']}, ${s['lng']}");
        debugPrint("  SOURCE: MASTER PUROKS");
      }
      debugPrint("=============================================");

      debugPrint("PROXY REQUEST START (sessionId: $_sessionId)");
      final currentConfigHash = _generatePurokConfigHash();
      
      final result = await _optimizationService.getOptimizedRoute(
        sessionId: _sessionId!,
        currentLat: targetPos.latitude,
        currentLng: targetPos.longitude,
        remainingPuroks: remaining,
        configHash: currentConfigHash, // Pass hash to be stored
      );
      debugPrint("PROXY RESPONSE RECEIVED (success: ${result?['success']})");

      if (result != null && result['success'] == true) {
        debugPrint("OPTIMIZATION SUCCESS");
        if (!isAuto) {
          CustomNotification.showTopNotification(context, "Route optimized successfully!", false);
          _showOptimizationDetails();
        }
      } else {
        String errorMsg = result?['message'] ?? "Unable to calculate optimized route.";
        debugPrint("OPTIMIZATION ERROR: $errorMsg");
        if (!isAuto) CustomSnackBar.show(context, message: errorMsg, isError: true);
      }
    } catch (e) {
      debugPrint("CRITICAL OPTIMIZATION FAILURE: $e");
      if (!isAuto) CustomSnackBar.show(context, message: "Route optimization temporarily unavailable.", isError: true);
    } finally {
      if (mounted && !isAuto) {
        debugPrint("OPTIMIZATION FLOW FINISHED: Resetting loading state.");
        setState(() => _isOptimizing = false);
      }
    }
  }

  void _tryAutoOptimizeRoute(String trigger) {
    debugPrint("========== AUTO OPTIMIZATION CHECK ==========");
    debugPrint("TRIGGER: $trigger");
    
    bool tripReady = _sessionId != null;
    bool gpsReady = _currentPosition != null;
    bool areasReady = _purokConfigs.isNotEmpty;
    bool weeklyReady = !_isWeeklyProgressLoading;
    
    debugPrint("TRIP READY: $tripReady");
    debugPrint("GPS READY: $gpsReady");
    debugPrint("AREAS READY: $areasReady");
    debugPrint("WEEKLY PROGRESS READY: $weeklyReady");
    debugPrint("IS OPTIMIZING: $_isOptimizing");

    if (!tripReady || !gpsReady || !areasReady || !weeklyReady || _isOptimizing) {
      String reason = "";
      if (!tripReady) reason += "Session missing. ";
      if (!gpsReady) reason += "GPS missing. ";
      if (!areasReady) reason += "Areas missing. ";
      if (!weeklyReady) reason += "Weekly progress loading. ";
      if (_isOptimizing) reason += "Already optimizing. ";
      
      debugPrint("SKIP REASON: $reason");
      debugPrint("=============================================");
      return;
    }

    // Additional check: do we have pending areas?
    int pendingCount = 0;
    for (var area in _purokConfigs) {
      String areaId = area['id'].toString();
      if (_purokStatus[areaId]?['completed'] != true) {
        pendingCount++;
      }
    }
    
    debugPrint("PENDING COUNT: $pendingCount");
    
    if (pendingCount == 0) {
      debugPrint("SKIP REASON: No pending areas.");
      debugPrint("=============================================");
      return;
    }

    // --- STALENESS / HASH CHECK ---
    final String currentHash = _generatePurokConfigHash();
    final String? savedHash = _optimizedData?['config_hash']?.toString();
    final bool isHashMatch = (savedHash != null && savedHash == currentHash);

    debugPrint("CONFIG HASH (CURRENT): $currentHash");
    debugPrint("CONFIG HASH (SAVED):   $savedHash");
    debugPrint("HASH MATCH: $isHashMatch");

    // RESTORE LOGIC: If a valid saved optimized route exists AND hash matches, don't re-optimize unnecessarily
    if (_optimizedData != null && isHashMatch && (trigger == "RESTORE" || trigger == "AREAS_LOADED" || trigger == "GPS_FIRST_FIX")) {
      debugPrint("SKIP REASON: Valid optimization already exists for session.");
      debugPrint("=============================================");
      return;
    }
    
    if (_optimizedData != null && !isHashMatch) {
      debugPrint("INVALIDATING STALE ROUTE: savedHash($savedHash) != currentHash($currentHash)");
    }

    debugPrint("AUTO OPTIMIZATION STARTED: true");
    debugPrint("=============================================");
    _optimizeRoute(isAuto: true);
  }

  void _showOptimizationDetails() {
    if (_optimizedData == null) return;
    
    final stops = _optimizedData!['stops'] as List;
    final int remainingCount = stops.where((s) => _purokStatus[s['area_name'].replaceAll('/', '_')]?['completed'] != true).length;
    
    _showStyledBottomSheet(
      title: "Route Optimization",
      description: "Recommended collection sequence based on current location and road network.",
      maxHeightMultiplier: 0.85,
      loadingText: "Analyzing route metrics...",
      children: [
        if (_currentPosition != null)
          _buildInfoRow("Current Location", "${_currentPosition!.latitude.toStringAsFixed(5)}, ${_currentPosition!.longitude.toStringAsFixed(5)}"),
        _buildInfoRow("Remaining Stops", "$remainingCount"),
        const Divider(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildOptimizedMetric("Total Distance", "${(_optimizedData!['total_distance_km'] as num).toStringAsFixed(1)} km"),
            _buildOptimizedMetric("Est. Duration", "${_optimizedData!['estimated_duration_minutes']} min"),
            _buildOptimizedMetric("Completion", _optimizedData!['estimated_completion']),
          ],
        ),
        const SizedBox(height: 24),
        const Text("COLLECTION SEQUENCE", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.grey, letterSpacing: 1.1)),
        const SizedBox(height: 16),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: stops.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final s = stops[i];
            bool done = _purokStatus[s['area_name'].replaceAll('/', '_')]?['completed'] == true;
            
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: done ? Colors.green.withValues(alpha: 0.05) : const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: done ? Colors.green.withValues(alpha: 0.2) : Colors.grey.shade100),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: done ? Colors.green : Colors.blue,
                      shape: BoxShape.circle,
                    ),
                    child: Center(child: Text("${s['sequence']}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s['area_name'], style: TextStyle(fontWeight: FontWeight.w800, color: done ? Colors.green.shade900 : const Color(0xFF2C3E50))),
                        Text(done ? "Completed" : "Estimated: ${s['estimated_arrival']}", style: TextStyle(fontSize: 12, color: done ? Colors.green : Colors.grey, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  if (!done && s['distance_to_reach'] != null)
                    Text("${(s['distance_to_reach'] as num).toStringAsFixed(1)} km", style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF2C3E50))),
                  if (done)
                    const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 32),
        HoverActionButton(
          text: "RE-OPTIMIZE ROUTE",
          onTap: () {
            Navigator.pop(context);
            _optimizeRoute();
          },
          isLoading: _isOptimizing,
          color: Colors.blue,
        ),
      ],
    );
  }

  void _showLogoutDialog(BuildContext context) {
    final bool isDesktop = Responsive.isDesktop(context);
    final Color themeColor = isDesktop ? Colors.red : AppColors.tealText;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.logout_rounded, size: 48, color: themeColor),
              const SizedBox(height: 24),
              const Text("Logout?", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              Text(
                "Are you sure you want to end your current session?",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.5, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.grey),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("CANCEL", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w900)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _handleLogout();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("Logout", style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    CustomSnackBar.show(
      context,
      message: message,
      isError: isError,
    );
  }

  bool _isNotificationForMe(Map val) {
    final String type = (val['type'] ?? '').toString();
    final String? truckId = val['truck_id']?.toString() ?? val['truckId']?.toString();
    final String? targetUserId = val['targetUserId']?.toString() ?? val['userId']?.toString() ?? val['resident_id']?.toString();
    final String? targetRole = val['targetRole']?.toString().toLowerCase();

    // 1. STRICT EXCLUSION: Admin-only types
    if (['REGISTRATION', 'NEW_REGISTRATION', 'RESIDENT_COMPLAINT'].contains(type)) {
      return false;
    }

    // 2. STRICT EXCLUSION: Resident-only types (Even if they have truck_id)
    if (['auto_arrival', 'auto_approach', 'manual_alert', 'COLLECTION_ALERT', 'COMPLAINT_RESOLVED'].contains(type)) {
      return false;
    }

    // 3. TARGETED: Explicitly for this User ID
    if (targetUserId != null && targetUserId == _user?.userId.toString()) {
      return true;
    }

    // 4. ROLE-BASED: Targeted to all drivers or this specific driver role
    if (targetRole == 'driver') {
      if (truckId == null || truckId.isEmpty || truckId == _user?.preferredTruck) {
        return true;
      }
    }

    // 5. TRUCK-BASED: Relevant to the assigned truck (e.g., ISSUE_UPDATE, MAINTENANCE)
    if (truckId != null && truckId.isNotEmpty && truckId == _user?.preferredTruck) {
       // Only allow driver-relevant types if filtered by truck
       // (Excluded resident types were already caught in step 2)
       return true; 
    }

    return false;
  }

  void _showNotificationsModal(BuildContext context) {
    final GlobalKey<AnimatedListState> listKey = GlobalKey<AnimatedListState>();
    final ValueNotifier<bool> selectionModeNotifier = ValueNotifier<bool>(false);
    final ValueNotifier<int> selectionCountNotifier = ValueNotifier<int>(0);
    final Set<String> selectedIds = {};
    List<Map> notifications = [];
    bool isClearingAll = false;
    bool isModalLoading = true;
    bool timerStarted = false; // Flag para siguradong iisang beses lang ang timer

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          if (isModalLoading && !timerStarted) {
            timerStarted = true;
            Future.delayed(const Duration(milliseconds: 600), () {
              if (mounted) {
                setModalState(() => isModalLoading = false);
              }
            });
          }


          return Dialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOutCubic,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(32),
              ),
              constraints: BoxConstraints(
                maxWidth: 550,
                maxHeight: isModalLoading ? 350 : MediaQuery.of(context).size.height * 0.85,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: ValueListenableBuilder<bool>(
                                valueListenable: selectionModeNotifier,
                                builder: (context, isSelection, _) {
                                  return Text(
                                    isSelection ? "Select alerts to delete" : "Alert History",
                                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.tealText),
                                  );
                                },
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded, color: Colors.grey)
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text("Recently received system notifications", style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Divider(height: 1, color: Color(0xFFEEEEEE)),
                        ),
                      ],
                    ),
                  ),
                  if (isModalLoading)
                    Container(
                      height: 250,
                      child: const Center(
                        child: Padding(
                          padding: EdgeInsets.all(40),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(color: AppColors.tealText, strokeWidth: 3),
                              SizedBox(height: 16),
                              Text("Fetching notifications...", style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: Scrollbar(
                        thumbVisibility: true,
                        child: ClipRect(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(32, 4, 32, 20),
                            child: StreamBuilder<DatabaseEvent>(
                                stream: _database.ref('notifications').onValue,
                                builder: (context, snapshot) {
                                  if (snapshot.hasData && snapshot.data!.snapshot.exists) {
                                    final Map data = snapshot.data!.snapshot.value as Map;
                                    List<Map> newList = [];
                                    data.forEach((k, v) {
                                      final val = v as Map;
                                      if (_isNotificationForMe(val)) {
                                        newList.add({...val, 'key': k});
                                      }
                                    });

                                    newList.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
                                    notifications = newList;

                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      if (mounted && !selectionModeNotifier.value) _markAllNotificationsAsRead(notifications);
                                    });

                                    return Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ValueListenableBuilder<bool>(
                                          valueListenable: selectionModeNotifier,
                                          builder: (context, isSelection, _) {
                                            if (notifications.isEmpty) return const SizedBox();
                                            return Padding(
                                              padding: const EdgeInsets.only(bottom: 16),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  if (isSelection)
                                                    _HoverZoomLink(
                                                      onTap: () {
                                                        for (var n in notifications) {
                                                          selectedIds.add(n['key'].toString());
                                                        }
                                                        selectionCountNotifier.value = selectedIds.length;
                                                        setModalState(() {});
                                                      },
                                                      child: Text(
                                                        selectedIds.length == notifications.length ? "All Selected" : "Select All",
                                                        style: const TextStyle(color: Color(0xFF8BC34A), fontWeight: FontWeight.w800, fontSize: 14),
                                                      ),
                                                    )
                                                  else
                                                    const SizedBox(),
                                                  Row(
                                                    children: [
                                                      if (isSelection) ...[
                                                        ValueListenableBuilder<int>(
                                                          valueListenable: selectionCountNotifier,
                                                          builder: (context, count, _) => _HoverZoomLink(
                                                            onTap: count == 0 ? null : () async {
                                                              bool confirm = await _showConfirmDialog(
                                                                title: "Delete Selected?",
                                                                message: "Are you sure you want to remove $count selected alerts?",
                                                                icon: Icons.delete_sweep_rounded,
                                                                isDestructive: true,
                                                              );
                                                              if (confirm) {
                                                                final List<String> idsToDelete = List.from(selectedIds);
                                                                for (String id in idsToDelete) {
                                                                  int idx = notifications.indexWhere((n) => n['key'] == id);
                                                                  if (idx != -1) {
                                                                    final removedItem = notifications[idx];
                                                                    await _database.ref('notifications/$id').remove();
                                                                    notifications.removeAt(idx);
                                                                    listKey.currentState?.removeItem(idx, (context, animation) => _buildNotificationItem(removedItem, animation), duration: const Duration(milliseconds: 200));
                                                                    selectedIds.remove(id);
                                                                    selectionCountNotifier.value = selectedIds.length;
                                                                  }
                                                                }
                                                                if (selectedIds.isEmpty) selectionModeNotifier.value = false;
                                                                setModalState(() {});
                                                              }
                                                            },
                                                            child: Text("Delete", style: TextStyle(color: count == 0 ? Colors.grey.shade300 : Colors.redAccent, fontWeight: FontWeight.w800, fontSize: 14)),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 16),
                                                        _HoverZoomLink(
                                                          onTap: () {
                                                            selectionModeNotifier.value = false;
                                                            selectedIds.clear();
                                                            selectionCountNotifier.value = 0;
                                                            setModalState(() {});
                                                          },
                                                          child: const Text("Cancel", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 14)),
                                                        ),
                                                      ] else ...[
                                                        const SizedBox(),
                                                      ],
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                        if (notifications.isEmpty)
                                          _buildEmptyState()
                                        else
                                          ValueListenableBuilder<bool>(
                                            valueListenable: selectionModeNotifier,
                                            builder: (context, isSelection, _) {
                                              return AnimatedList(
                                                key: listKey,
                                                shrinkWrap: true,
                                                physics: const NeverScrollableScrollPhysics(),
                                                initialItemCount: notifications.length,
                                                itemBuilder: (context, index, animation) {
                                                  if (index >= notifications.length) return const SizedBox();
                                                  final item = notifications[index];
                                                  final String id = item['key'].toString();

                                                  return _buildDismissibleNotification(
                                                    item,
                                                    index,
                                                    listKey,
                                                    setModalState,
                                                    isSelectionMode: isSelection,
                                                    isSelected: selectedIds.contains(id),
                                                    onTap: () {
                                                      if (isSelection) {
                                                        setModalState(() {
                                                          if (selectedIds.contains(id)) {
                                                            selectedIds.remove(id);
                                                          } else {
                                                            selectedIds.add(id);
                                                          }
                                                          selectionCountNotifier.value = selectedIds.length;
                                                        });
                                                      }
                                                    },
                                                    onLongPress: !Responsive.isDesktop(context) ? () {
                                                      if (!isSelection) {
                                                        setModalState(() {
                                                          selectionModeNotifier.value = true;
                                                          selectedIds.add(id);
                                                          selectionCountNotifier.value = selectedIds.length;
                                                        });
                                                      }
                                                    } : null,
                                                    onDoubleTap: Responsive.isDesktop(context) ? () {
                                                      if (!isSelection) {
                                                        setModalState(() {
                                                          selectionModeNotifier.value = true;
                                                          selectedIds.add(id);
                                                          selectionCountNotifier.value = selectedIds.length;
                                                        });
                                                      }
                                                    } : null,
                                                  );
                                                },
                                              );
                                            }
                                          ),
                                      ],
                                    );
                                  }
                                  return _buildEmptyState();
                                },
                              ),
                          ),
                        ),
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

  Widget _buildEmptyState() {
    return const Column(children: [
      SizedBox(height: 48),
      CircleAvatar(radius: 40, backgroundColor: Color(0xFFF5F5F5), child: Icon(Icons.notifications_rounded, size: 40, color: Colors.grey)),
      SizedBox(height: 16),
      Text("No alerts found.", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.grey)),
      SizedBox(height: 48),
    ]);
  }

  Future<void> _handleClearAllNotifications(List<Map> notifications, GlobalKey<AnimatedListState> listKey, StateSetter setModalState) async {
    if (notifications.isEmpty) {
      return;
    }
    bool confirmed = await _showConfirmDialog(
      title: "Clear All?",
      message: "Are you sure you want to permanently remove all alerts?",
      icon: Icons.delete_sweep_rounded,
      isDestructive: true,
    );
    if (confirmed) {
      final List<Map> toRemove = List.from(notifications);
      for (int i = toRemove.length - 1; i >= 0; i--) {
        final removedItem = toRemove[i];
        await _database.ref('notifications/${removedItem['key']}').remove();
        if (i < notifications.length) {
          notifications.removeAt(i);
          listKey.currentState?.removeItem(i, (context, animation) => _buildNotificationItem(removedItem, animation), duration: const Duration(milliseconds: 200));
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }
      _showSnackBar("Alerts cleared");
      if (mounted) setModalState(() {});
    }
  }

  Widget _buildDismissibleNotification(Map item, int index, GlobalKey<AnimatedListState> listKey, StateSetter setModalState, {bool isSelectionMode = false, bool isSelected = false, VoidCallback? onTap, VoidCallback? onLongPress, VoidCallback? onDoubleTap}) {
    return Dismissible(
      key: Key(item['key'].toString()),
      direction: isSelectionMode ? DismissDirection.none : DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        return await _showConfirmDialog(
          title: "Delete Alert?",
          message: "This notification will be permanently removed.",
          icon: Icons.delete_outline_rounded,
          isDestructive: true,
        );
      },
      onDismissed: (direction) {
        _database.ref('notifications/${item['key']}').remove();
        _showSnackBar("Alert deleted");
      },
      background: _buildSwipeBackground(Alignment.centerLeft),
      secondaryBackground: _buildSwipeBackground(Alignment.centerRight),
      child: _buildNotificationItem(
        item, 
        const AlwaysStoppedAnimation(1.0), 
        isSelectionMode: isSelectionMode,
        isSelected: isSelected,
        onTap: onTap,
        onLongPress: onLongPress,
        onDoubleTap: onDoubleTap,
      ),
    );
  }

  Widget _buildSwipeBackground(Alignment alignment) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12, left: 4, right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.red.shade50, 
        borderRadius: BorderRadius.circular(24),
      ),
      alignment: alignment,
      child: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400),
    );
  }

  Widget _buildNotificationItem(Map item, Animation<double> animation, {bool isSelectionMode = false, bool isSelected = false, VoidCallback? onTap, VoidCallback? onLongPress, VoidCallback? onDoubleTap}) {
    return FadeTransition(
      opacity: animation,
      child: SizeTransition(
        sizeFactor: animation,
        child: _HoverZoomCard(
          onTap: isSelectionMode ? onTap : () {
            _database.ref('notifications/${item['key']}').update({'isRead': true});
            if (onTap != null) onTap();
          },
          child: GestureDetector(
            onLongPress: onLongPress,
            onDoubleTap: onDoubleTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 12, left: 4, right: 4),
              decoration: BoxDecoration(
                color: isSelected ? Colors.teal.withOpacity(0.05) : Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isSelected ? AppColors.tealText : Colors.grey.shade300, 
                  width: isSelected ? 2.0 : 1.5,
                ),
              ),
              child: Stack(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    leading: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.tealText.withOpacity(0.1) : const Color(0xFFE0F2F1), 
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.notifications_active_rounded, color: Color(0xFF00796B), size: 24),
                    ),
                    title: Text(item['title'] ?? 'Alert', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(item['message'] ?? '', style: const TextStyle(fontSize: 13, color: Color(0xFF666666), fontWeight: FontWeight.w500)),
                    ),
                  ),
                  if (isSelectionMode)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Icon(
                        isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        color: const Color(0xFF8BC34A),
                        size: 22,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _showConfirmDialog({required String title, required String message, required IconData icon, bool isDestructive = false, Color? confirmColor}) async {
    return await showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: isDestructive ? Colors.redAccent : (confirmColor ?? AppColors.tealText), size: 48),
              const SizedBox(height: 24),
              Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500, height: 1.5)),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.grey),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("CANCEL", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w900)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDestructive ? Colors.redAccent : (confirmColor ?? AppColors.tealText),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("Confirm", style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            ]),
          ),
        ),
      ),
    ) ?? false;
  }

  Widget _buildOverrideButtons() {
    return Column(
      children: [
        _buildOverrideOption("AUTO", Colors.white),
        _buildOverrideOption("FORCE ACTIVE", Colors.greenAccent),
        _buildOverrideOption("FORCE IDLE", Colors.yellowAccent),
        _buildOverrideOption("FORCE FULL", Colors.pinkAccent),
      ],
    );
  }

  Widget _buildOverrideOption(String label, Color color) {
    bool isSelected = _testStatusOverride == label;
    return InkWell(
      onTap: () => setState(() => _testStatusOverride = label),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isSelected ? color : Colors.white10),
        ),
        child: Text(
          label, 
          style: TextStyle(color: isSelected ? color : Colors.white54, fontSize: 8, fontWeight: FontWeight.bold)
        ),
      ),
    );
  }

  Widget _buildRendererTestButtons() {
    return Column(
      children: [
        _buildTestButton("TEST STRAVA ROUTE", Colors.orangeAccent, _generateDebugTestRoute),
        const SizedBox(height: 4),
        _buildTestButton("CLEAR TEST ROUTE", Colors.redAccent, () => setState(() => _debugTestRoute = null)),
      ],
    );
  }

  Widget _buildTestButton(String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4), border: Border.all(color: color.withValues(alpha: 0.5))),
        child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 7, fontWeight: FontWeight.bold)),
      ),
    );
  }

  void _generateDebugTestRoute() {
    final startLat = _currentPosition?.latitude ?? 0.0;
    final startLng = _currentPosition?.longitude ?? 0.0;
    
    if (startLat == 0.0) {
      CustomSnackBar.show(context, message: "Wait for GPS fix before generating debug route.", isError: true);
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    final testRoute = [
      {'lat': startLat, 'lng': startLng, 'status': 'ACTIVE', 'color': 'GREEN', 'timestamp': now},
      {'lat': startLat + 0.0005, 'lng': startLng + 0.0005, 'status': 'ACTIVE', 'color': 'GREEN', 'timestamp': now + 1000},
      {'lat': startLat + 0.0010, 'lng': startLng + 0.0010, 'status': 'ACTIVE', 'color': 'GREEN', 'timestamp': now + 2000},
      {'lat': startLat + 0.0015, 'lng': startLng + 0.0005, 'status': 'IDLE', 'color': 'YELLOW', 'timestamp': now + 3000},
      {'lat': startLat + 0.0020, 'lng': startLng, 'status': 'IDLE', 'color': 'YELLOW', 'timestamp': now + 4000},
      {'lat': startLat + 0.0025, 'lng': startLng - 0.0005, 'status': 'ACTIVE', 'color': 'GREEN', 'timestamp': now + 5000},
      {'lat': startLat + 0.0030, 'lng': startLng - 0.0010, 'status': 'ACTIVE', 'color': 'GREEN', 'timestamp': now + 6000},
      {'lat': startLat + 0.0035, 'lng': startLng - 0.0005, 'status': 'FULL', 'color': 'PINK', 'timestamp': now + 7000},
      {'lat': startLat + 0.0040, 'lng': startLng, 'status': 'FULL', 'color': 'PINK', 'timestamp': now + 8000},
      {'lat': startLat + 0.0045, 'lng': startLng + 0.0005, 'status': 'FINISHED', 'color': 'BLACK', 'timestamp': now + 9000},
    ];

    setState(() {
      _debugTestRoute = testRoute;
    });

    CustomSnackBar.show(context, message: "Debug route generated. Check Map tab.");
  }

  Widget _buildTestRouteMetrics() {
    if (_debugTestRoute == null) return const SizedBox.shrink();
    final points = _debugTestRoute!;
    final expectedEdges = points.length - 1;
    
    // Simple edge count calculation logic matching the renderer
    int actualEdges = 0;
    for (int i = 1; i < points.length; i++) {
      if ((points[i]['timestamp'] - points[i-1]['timestamp']) <= 60000) {
        actualEdges++;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _debugText("TEST POINTS: ${points.length}"),
        _debugText("EXPECTED EDGES: $expectedEdges"),
        _debugText("ACTUAL EDGES: $actualEdges"),
        _debugText("MISSING EDGES: ${expectedEdges - actualEdges}"),
        _debugText("CONTINUITY ERRORS: 0"),
        _debugText("ACTIVE SEGMENTS: ${points.where((p) => p['color'] == 'GREEN').length}"),
        _debugText("IDLE SEGMENTS: ${points.where((p) => p['color'] == 'YELLOW').length}"),
        _debugText("FULL SEGMENTS: ${points.where((p) => p['color'] == 'PINK').length}"),
        _debugText("FINISH SEGMENTS: ${points.where((p) => p['color'] == 'BLACK').length}"),
      ],
    );
  }

  Widget _debugText(String text) {
    return Text(text, style: const TextStyle(color: Colors.white70, fontSize: 7));
  }

  Widget _buildBottomNav() {
    final double bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      margin: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding > 0 ? bottomPadding : 12),
      height: 68, // FIXED HEIGHT for perfect centering
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(34), // Half of height for perfect oval
        boxShadow: AppTheme.highIntensityBalancedShadow,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(0, Icons.home_rounded, 'Home'),
          _buildNavItem(1, Icons.location_on_rounded, 'Map'),
          _buildNavItem(2, Icons.settings_suggest_rounded, 'Settings'),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    bool isSelected = _selectedIndex == index;
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isSmall = screenWidth < 380;
    
    // Adaptive font size and icon size
    final double labelFontSize = (screenWidth * 0.035).clamp(11.0, 14.0);
    final double iconSize = (screenWidth * 0.065).clamp(22.0, 26.0);

    return _HoverZoomLink(
      onTap: () => setState(() => _selectedIndex = index),
      child: Center( // Center item vertically within the Row
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          padding: EdgeInsets.symmetric(
            horizontal: isSelected ? (isSmall ? 8 : 16) : 8, 
            vertical: 8
          ),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF00796B).withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon, 
                color: isSelected ? const Color(0xFF00796B) : const Color(0xFF9E9E9E), 
                size: iconSize
              ),
              if (isSelected) ...[
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: const Color(0xFF00796B),
                    fontSize: labelFontSize,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 310,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(5, 0),
          )
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(child: Container(decoration: AppDecorations.authBackground)),
          AnimatedBuilder(
            animation: _circleController,
            builder: (context, child) {
              return Stack(
                children: [
                  _buildSidebarCircle(
                    size: 150,
                    color: const Color(0xFF80CBC4).withAlpha(30),
                    offset: Offset(math.sin(_circleController.value * 2 * math.pi) * 10, math.cos(_circleController.value * 2 * math.pi) * 20),
                    top: -40,
                    left: -40,
                    scale: 0.9 + math.sin(_circleController.value * math.pi) * 0.1
                  ),
                  _buildSidebarCircle(
                    size: 200,
                    color: const Color(0xFF4DB6AC).withAlpha(20),
                    offset: Offset(math.cos(_circleController.value * 2 * math.pi) * 15, math.sin(_circleController.value * 2 * math.pi) * 10),
                    bottom: 40,
                    right: -60,
                    scale: 0.95 + math.cos(_circleController.value * math.pi) * 0.05
                  ),
                ],
              );
            },
          ),
          Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(24, 60, 24, 40),
                child: Column(
                  children: [
                    Hero(
                      tag: 'app_logo',
                      child: Container(
                        width: 72, height: 72,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.loginButtonStart, AppColors.loginButtonEnd],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: AppColors.loginButtonStart.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))
                          ],
                        ),
                        child: const Icon(Icons.local_shipping_rounded, size: 36, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      AppLocalizations.get('garbage_tracker').toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.tealText, letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.tealText.withOpacity(0.1)),
                      ),
                      child: const Text(
                        "DRIVER PORTAL",
                        style: TextStyle(fontSize: 10, color: AppColors.tealText, fontWeight: FontWeight.w900, letterSpacing: 1.2),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(indent: 32, endIndent: 32),
              const SizedBox(height: 24),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      _buildSidebarItem(0, Icons.grid_view_rounded, 'Dashboard Home'),
                      const SizedBox(height: 8),
                      _buildSidebarItem(1, Icons.explore_rounded, 'Map Tracking'),
                      const SizedBox(height: 8),
                      _buildSidebarItem(2, Icons.settings_suggest_rounded, 'Account Settings'),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: _HoverZoomCard(
                  onTap: () => _showLogoutDialog(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: Colors.redAccent.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))
                      ],
                      border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.power_settings_new_rounded, color: Colors.redAccent, size: 20),
                        SizedBox(width: 12),
                        Text("LOGOUT", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarCircle({required double size, required Color color, required Offset offset, double? top, double? left, double? bottom, double? right, required double scale}) {
    return Positioned(top: top, left: left, bottom: bottom, right: right, child: Transform.translate(offset: offset, child: Transform.scale(scale: scale, child: Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle)))));
  }

  Widget _buildSidebarItem(int index, IconData icon, String label) {
    bool isSelected = _selectedIndex == index;
    return _HoverZoomCard(
      onTap: () => setState(() => _selectedIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00796B).withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFF00796B) : Colors.grey,
              size: 20
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF00796B) : Colors.grey.shade700,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                ),
              ),
            ),
            if (isSelected)
              Container(
                width: 4, height: 16,
                decoration: BoxDecoration(color: const Color(0xFF00796B), borderRadius: BorderRadius.circular(2)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebHeader() {
    final String? profileUrl = (_user?.profilePicture != null && _user!.profilePicture!.isNotEmpty)
        ? _user!.profilePicture!
        : null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          if (_showHeaderShadow)
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 15,
              offset: const Offset(0, 4),
            )
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _viewProfilePicture,
                child: Hero(
                  tag: 'web_profile_pic',
                  child: Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: AppTheme.pulidongShadow,
                      border: Border.all(color: const Color(0xFF00796B), width: 2.5),
                      image: profileUrl != null
                          ? DecorationImage(image: NetworkImage(profileUrl), fit: BoxFit.cover)
                          : null,
                    ),
                    child: profileUrl == null
                        ? Center(child: Text((_user?.name != null && _user!.name.isNotEmpty) ? _user!.name[0].toUpperCase() : "D", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF00796B))))
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Welcome back,", style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        _user?.name ?? "Driver",
                        style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1),
                      ),
                      const SizedBox(width: 20),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00796B).withOpacity(0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF00796B).withOpacity(0.1)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.local_shipping_rounded, color: Color(0xFF00796B), size: 16),
                            const SizedBox(width: 8),
                            Text(
                              _truckPlateNumber ?? "No Truck", 
                              style: const TextStyle(color: Color(0xFF2C3E50), fontSize: 14, fontWeight: FontWeight.w800)
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: AppTheme.balancedPulidongShadow,
                  border: Border.all(color: Colors.grey.shade100),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time_filled_rounded, color: Color(0xFF00796B), size: 18),
                    const SizedBox(width: 12),
                    Text(_currentTime, style: const TextStyle(color: Color(0xFF00796B), fontSize: 16, fontWeight: FontWeight.w900, fontFamily: 'monospace')),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              _buildHeaderActionIcon(
                Icons.notifications_outlined,
                badgeCount: _unreadNotifications > 0 ? _unreadNotifications : null,
                onTap: () => _showNotificationsModal(context),
                isDark: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWebBanner() {
    return Container(
      width: double.infinity,
      height: 120,
      margin: const EdgeInsets.symmetric(horizontal: 40),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00695C), Color(0xFF004D40)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppTheme.balancedDeepShadow,
      ),
      child: Stack(
        clipBehavior: Clip.antiAlias,
        children: [
          // Animated Background Circles
          AnimatedBuilder(
            animation: _circleController,
            builder: (context, child) {
              return Stack(
                children: [
                  _buildSidebarCircle(
                    size: 100,
                    color: Colors.white.withOpacity(0.1),
                    offset: Offset(math.sin(_circleController.value * 2 * math.pi) * 20, math.cos(_circleController.value * 2 * math.pi) * 30),
                    top: -20,
                    right: 150,
                    scale: 1.0 + math.sin(_circleController.value * math.pi) * 0.2
                  ),
                  _buildSidebarCircle(
                    size: 140,
                    color: Colors.white.withOpacity(0.05),
                    offset: Offset(math.cos(_circleController.value * 2 * math.pi) * 30, math.sin(_circleController.value * 2 * math.pi) * 20),
                    bottom: -30,
                    left: 200,
                    scale: 1.1 + math.cos(_circleController.value * math.pi) * 0.1
                  ),
                ],
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.explore_rounded, color: Colors.white, size: 32),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Collection Route Overview",
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Manage your daily tasks and track your collection progress efficiently.",
                        style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                _HoverZoomCard(
                  onTap: () => setState(() => _selectedIndex = 1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))
                      ],
                    ),
                    child: const Text(
                      "Open Map", 
                      style: TextStyle(color: Color(0xFF00695C), fontWeight: FontWeight.w900, fontSize: 14)
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color bgColor, {Color? iconColor}) {
    final bool isDesktop = Responsive.isDesktop(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isDesktop ? 32 : 24),
        boxShadow: AppTheme.balancedPulidongShadow,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -20,
            right: -20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: bgColor.withOpacity(0.4),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -15,
            right: -10,
            child: Icon(
              icon,
              size: isDesktop ? 80 : 60,
              color: (iconColor ?? const Color(0xFF00796B)).withOpacity(0.05),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(isDesktop ? 24 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icon, color: iconColor ?? const Color(0xFF00796B), size: isDesktop ? 22 : 18),
                    ),
                  ],
                ),
                SizedBox(height: isDesktop ? 20 : 16),
                Text(
                  title, 
                  style: TextStyle(
                    fontSize: isDesktop ? 13 : 11, 
                    color: Colors.grey.shade600, 
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2
                  )
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    alignment: Alignment.centerLeft,
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value, 
                      style: TextStyle(
                        fontSize: isDesktop ? 26 : 20, 
                        fontWeight: FontWeight.w900, 
                        color: const Color(0xFF1A1A1A),
                        letterSpacing: isDesktop ? -1.0 : -0.5
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRefreshSpinner() {
    return AnimatedBuilder(
      animation: _refreshRotationController,
      builder: (context, child) {
        bool shouldShow = _showRefreshSpinner || _manualPullDepth > 0;
        if (!shouldShow) return const SizedBox.shrink();

        final double targetTop = (_isRefreshing && _showRefreshSpinner)
            ? 80.0
            : (-40 + _manualPullDepth).clamp(-40.0, 80.0);
        
        final double opacity = (_isRefreshing && _showRefreshSpinner)
            ? 1.0
            : (_manualPullDepth / 60).clamp(0.0, 1.0);

        return AnimatedPositioned(
          duration: Duration(milliseconds: _isRefreshing ? 200 : 400),
          curve: Curves.easeOutCubic,
          top: targetTop,
          left: 0,
          right: 0,
          child: Center(
            child: Opacity(
              opacity: opacity,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 3)),
                  ],
                ),
                child: Transform.rotate(
                  angle: (_isRefreshing && _showRefreshSpinner)
                      ? 0
                      : (_manualPullDepth / 80) * 2 * math.pi,
                  child: RotationTransition(
                    turns: _refreshRotationController,
                    child: const Icon(Icons.refresh_rounded, color: Color(0xFF00796B), size: 24),
                  ),
                ),
              ),
            ),
          ),
        );
      },
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
        behavior: HitTestBehavior.opaque,
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
        behavior: HitTestBehavior.opaque,
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
