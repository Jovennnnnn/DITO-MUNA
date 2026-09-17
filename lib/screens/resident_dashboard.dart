import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart' as geo;
import '../utils/prediction_engine.dart';
import '../utils/session_manager.dart';
import '../models/user.dart';
import '../utils/app_theme.dart';
import 'resident_track_truck_screen.dart';
import 'resident_complaints_screen.dart';
import 'resident_settings_screen.dart';
import '../utils/responsive.dart';
import '../widgets/mapbox_view.dart';
import '../widgets/fade_slide_entrance.dart';
import '../widgets/hover_action_button.dart';
import '../widgets/header_circle_painter.dart';
import '../widgets/data_management_modal.dart';
import '../widgets/custom_snackbar.dart';
import '../api/api_service.dart';
import 'package:dio/dio.dart';
import '../utils/route_persistence_manager.dart';
import '../utils/app_localizations.dart';
import '../services/notification_service.dart';

class ResidentDashboard extends StatefulWidget {
  const ResidentDashboard({super.key});

  @override
  State<ResidentDashboard> createState() => _ResidentDashboardState();
}

class _ResidentDashboardState extends State<ResidentDashboard> with TickerProviderStateMixin {
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final ApiService _apiService = ApiService();
  UserData? _user;
  geo.Position? _currentPosition;
  int _activeTrucks = 0;
  int _totalTrucks = 0;
  int _unreadNotificationsCount = 0;
  int _selectedIndex = 0;
  int _complaintsRefreshCount = 0;
  String? _targetComplaintId;
  bool _shouldShowDataManagement = false;
  String _etaText = "--";
  String _currentTime = "";
  Timer? _clockTimer;
  Future<Response>? _complaintsFuture;
  final ScrollController _scrollController = ScrollController();
  bool _showHeaderShadow = true;

  bool _isRefreshing = false;
  bool _showRefreshSpinner = false;
  double _manualPullDepth = 0.0;
  late AnimationController _refreshRotationController;

  void _refreshComplaints() {
    if (mounted) {
      setState(() {
        _complaintsFuture = _apiService.getComplaints();
        _complaintsRefreshCount++;
      });
    }
  }

  StreamSubscription? _truckSubscription;
  StreamSubscription? _notificationSubscription;
  StreamSubscription? _totalTruckSubscription;
  StreamSubscription? _userRealtimeSubscription;

  final Map<String, DateTime> _sentProximityAlerts = {};
  late AnimationController _circleController;

  @override
  void initState() {
    super.initState();
    RoutePersistenceManager.saveLastRoute('/resident_dashboard');
    _loadUser();
    _startClock();
    _getCurrentLocation();
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
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _truckSubscription?.cancel();
    _notificationSubscription?.cancel();
    _totalTruckSubscription?.cancel();
    _userRealtimeSubscription?.cancel();
    _circleController.dispose();
    _refreshRotationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;
    geo.LocationPermission permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
      if (permission == geo.LocationPermission.denied) return;
    }
    if (permission == geo.LocationPermission.deniedForever) return;
    geo.Geolocator.getPositionStream().listen((pos) {
      if (mounted) setState(() => _currentPosition = pos);
    });
    try {
      geo.Position pos = await geo.Geolocator.getCurrentPosition();
      if (mounted) setState(() => _currentPosition = pos);
    } catch (_) {}
  }

  void _startClock() {
    _updateTime();
    _clockTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) => _updateTime());
  }

  void _updateTime() {
    final String time = DateFormat('hh:mm:ss a').format(DateTime.now());
    if (mounted && _currentTime != time) setState(() => _currentTime = time);
  }

  Future<void> _refreshAllStats({bool manual = false}) async {
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
      _refreshData(),
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
                        Text("Dashboard updated",
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

  Future<void> _refreshData() async {
    _loadUser();
    _refreshComplaints();
    await Future.delayed(const Duration(milliseconds: 800));
  }

  void _loadUser() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final sessionUser = await SessionManager.getUser();
      if (sessionUser != null) {
        setState(() {
          _user = sessionUser;
          _complaintsFuture = _apiService.getComplaints();
        });
        NotificationService.startListening(_user!);
        _setupListeners();
      }
    });
  }

  void _setupListeners() {
    if (_user == null) return;
    _userRealtimeSubscription?.cancel();
    _userRealtimeSubscription = _database.ref('residents/${_user!.userId}').onValue.listen((event) {
      if (event.snapshot.exists) {
        final Map data = event.snapshot.value as Map;
        if (mounted) {
          final updatedUser = _user!.copyWith(
            name: data['name']?.toString(),
            purok: data['purok']?.toString(),
            email: data['email']?.toString(),
            phone: data['phone']?.toString(),
            completeAddress: data['complete_address']?.toString(),
            profilePicture: data['profile_picture']?.toString(),
          );
          setState(() {
            _user = updatedUser;
          });
          // Persist to session
          SessionManager.saveUser(updatedUser.toJson());
        }
      }
    });

    _truckSubscription?.cancel();
    _truckSubscription = _database.ref('truck_locations').onValue.listen((event) {
      if (event.snapshot.exists) {
        final Map data = event.snapshot.value as Map;
        int active = 0;
        double minEta = double.infinity;
        data.forEach((key, value) {
          final val = value as Map;
          final status = (val['status'] ?? '').toString().toUpperCase();
          if (val['isOnline'] == true && (status == 'ACTIVE' || status == 'COLLECTING' || status == 'IDLE')) {
            active++;
            if (_currentPosition != null && val['latitude'] != null && val['longitude'] != null) {
              try {
                double dist = geo.Geolocator.distanceBetween(_currentPosition!.latitude, _currentPosition!.longitude, (val['latitude'] as num).toDouble(), (val['longitude'] as num).toDouble()) / 1000.0;
                double speed = (val['speed'] ?? 15.0).toDouble();
                double eta = PredictionEngine.estimateArrivalTime(dist, [speed > 5 ? speed : 15.0]);
                if (eta < minEta) minEta = eta;
              } catch (_) {}
            }
          }
        });
        String etaDisplay = "--";
        if (active > 0) {
          etaDisplay = minEta != double.infinity ? "${minEta.toStringAsFixed(0)} mins" : "Approaching";
          if (minEta <= 10 && _user?.purok != null) {
            final String alertKey = "${_user!.userId}_proximity_${_user!.purok}";
            final lastAlert = _sentProximityAlerts[alertKey];
            if (lastAlert == null || DateTime.now().difference(lastAlert).inMinutes > 30) {
              _sentProximityAlerts[alertKey] = DateTime.now();
              _database.ref('notifications').push().set({
                'type': 'TRUCK_PROXIMITY',
                'title': 'Truck is Arriving!',
                'message': 'A garbage truck is approximately ${minEta.toStringAsFixed(0)} minutes away from ${_user!.purok}. Please prepare your trash.',
                'purok': _user!.purok,
                'timestamp': ServerValue.timestamp,
                'isRead': false,
              });
            }
          }
        }
        if (mounted) setState(() { _activeTrucks = active; _etaText = etaDisplay; });
      }
    });

    _totalTruckSubscription?.cancel();
    _totalTruckSubscription = _database.ref('trucks').onValue.listen((event) {
      if (event.snapshot.exists) {
        final Map data = event.snapshot.value as Map;
        if (mounted) setState(() => _totalTrucks = data.length);
      }
    });

    _notificationSubscription?.cancel();
    _notificationSubscription = _database.ref('notifications').onValue.listen((event) {
      if (event.snapshot.exists) {
        final Map data = event.snapshot.value as Map; int unread = 0;
        data.forEach((key, value) {
          final val = value as Map;
          if (val['isRead'] == false) {
             final String type = (val['type'] ?? '').toString();
             final String targetPurok = (val['purok'] ?? val['area'] ?? '').toString();
             final String residentId = (val['resident_id'] ?? '').toString();
             bool isRelevant = (type == 'TRUCK_PROXIMITY' && (targetPurok == '' || targetPurok == _user?.purok)) || (type == 'COMPLAINT_RESOLVED' && residentId == _user?.userId.toString());
             if (isRelevant) unread++;
          }
        });
        if (mounted) setState(() => _unreadNotificationsCount = unread);
      }
    });
  }

  void _handleLogout() {
    final bool isDesktop = Responsive.isDesktop(context);
    final Color themeColor = isDesktop ? Colors.red : AppColors.tealText;
    final String btnText = isDesktop ? "Logout" : "Logout"; // User said "Logout" for web sidebar text, let's keep consistency for button text in modal too

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
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
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.5),
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
                      onPressed: () async {
                        NotificationService.stopListening();
                        await SessionManager.logout();
                        await RoutePersistenceManager.clearLastRoute();
                        if (!mounted) return;
                        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
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

  void _viewProfilePicture() {
    if (_user == null) return;
    final String profileUrl = _user?.profilePictureUrl ?? "";
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Profile",
      barrierColor: Colors.black.withOpacity(0.5),
      pageBuilder: (context, _, __) => BackdropFilter(
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
                  tag: 'web_profile_pic',
                  child: Container(
                    width: 320,
                    height: 320,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 5,
                        )
                      ],
                      image: profileUrl.isNotEmpty
                          ? DecorationImage(image: NetworkImage(profileUrl), fit: BoxFit.cover)
                          : null,
                    ),
                    child: profileUrl.isEmpty
                        ? const Icon(Icons.person, size: 160, color: Colors.white)
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = Responsive.isDesktop(context);
    
    Widget mainLayout;
    if (isDesktop) {
      mainLayout = Row(
        children: [
          _buildSidebar(), 
          Expanded(child: _buildMainContent())
        ]
      );
    } else {
      mainLayout = Stack(
        children: [
          _buildMainContent(), 
          Positioned(left: 0, right: 0, bottom: 0, child: _buildBottomNav())
        ]
      );
    }

    return Scaffold(
      backgroundColor: AppColors.dashboardBg,
      extendBody: !isDesktop,
      body: Stack(
        children: [
          mainLayout,
          _buildRefreshSpinner(),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return IndexedStack(index: _selectedIndex, children: [
        FadeSlideEntrance(key: const ValueKey("home"), child: _buildHomeTab()),
        FadeSlideEntrance(key: const ValueKey("track"), child: ResidentTrackTruckScreen(isEmbedded: true, onBack: () => setState(() => _selectedIndex = 0))),
        FadeSlideEntrance(key: ValueKey("complaints_$_complaintsRefreshCount"), child: ResidentComplaintsScreen(isEmbedded: true, targetComplaintId: _targetComplaintId, onDataChanged: _refreshComplaints, onBack: () {
          setState(() {
            _selectedIndex = 0;
            _targetComplaintId = null;
          });
        })),
        FadeSlideEntrance(key: const ValueKey("settings"), child: ResidentSettingsScreen(isEmbedded: true, showDataManagementOnLoad: _shouldShowDataManagement, onBack: () => setState(() { _selectedIndex = 0; _shouldShowDataManagement = false; }), onProfileUpdate: _loadUser)),
    ]);
  }

  Widget _buildWebHeader() {
    final String? profileUrl = _user?.profilePictureUrl;
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
          // 1. Left Section: Profile + Greeting + Location Info
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
                        ? Center(child: Text((_user?.name != null && _user!.name.isNotEmpty) ? _user!.name[0].toUpperCase() : "R", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF00796B))))
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
                        _user?.name ?? "Resident",
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
                            const Icon(Icons.location_on_rounded, color: Color(0xFF00796B), size: 16),
                            const SizedBox(width: 8),
                            Text(
                              _user?.purok ?? "Detecting...", 
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
          // 2. Right Section: Time and Notifications
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
              _buildHeaderActionIcon(Icons.notifications_outlined, badgeCount: _unreadNotificationsCount > 0 ? _unreadNotificationsCount : null, onTap: () => _showNotificationsModal(context), isDark: true),
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
                  child: const Icon(Icons.map_rounded, color: Colors.white, size: 32),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Track Your Local Garbage Collection",
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Real-time updates on truck locations and ETAs in your area.",
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
                      "Track Now", 
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

  Widget _buildHomeTab() {
    return LayoutBuilder(builder: (context, constraints) {
      final bool isDesktop = Responsive.isDesktop(context);
      
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerMove: (event) {
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
            _refreshAllStats(manual: true);
          } else if (!_isRefreshing) {
            setState(() {
              _manualPullDepth = 0;
              _showRefreshSpinner = false;
            });
          }
        },
        child: isDesktop ? _buildDesktopHome() : _buildMobileHome(constraints.maxWidth),
      );
    });
  }

  Widget _buildDesktopHome() {
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
                              Expanded(
                                flex: 3,
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _buildStatCard(
                                            "Active Trucks",
                                            "$_activeTrucks / $_totalTrucks",
                                            Icons.local_shipping_rounded,
                                            AppColors.statActiveBg,
                                            isLive: true,
                                          ),
                                        ),
                                        const SizedBox(width: 20),
                                        Expanded(
                                          child: _buildStatCard(
                                            "Estimated Time",
                                            _etaText,
                                            Icons.access_time_filled_rounded,
                                            AppColors.statEtaBg,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 24),
                                    _buildMapCard(),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(left: 0, bottom: 16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text("Reports & Feedback", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                                          Text("File new reports and track your submitted complaints.", style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                    ),
                                    _buildActionCard("File Complaint", "Report collection issues", Icons.feedback_rounded, const Color(0xFFFFF0F2), const Color(0xFFFF1744)),
                                    const SizedBox(height: 24),
                                    _buildTransactionHistoryCard(),
                                    const SizedBox(height: 24),
                                    _buildScheduleCard(),
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

  Widget _buildMobileHome(double maxWidth) {
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(maxWidth),
                  const SizedBox(height: 8),
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(children: [
                        Expanded(child: _buildStatCard("Active Trucks", "$_activeTrucks / $_totalTrucks", Icons.local_shipping_rounded, AppColors.statActiveBg, isLive: true)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildStatCard("Estimated Time", _etaText, Icons.access_time_filled_rounded, AppColors.statEtaBg))
                      ])),
                  const SizedBox(height: 16),
                  _buildMapCard(),
                  _buildSectionHeader("Reports & Feedback", "File new reports and track your submitted complaints."),
                  _buildActionCard("File Complaint", "Report issues", Icons.feedback_rounded, const Color(0xFFFFF0F2), const Color(0xFFFF1744)),
                  const SizedBox(height: 16),
                  _buildTransactionHistoryCard(),
                  const SizedBox(height: 16),
                  _buildScheduleCard(),
                  const SizedBox(height: 110),
                ],
              ),
            );
          }
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, [String? subtitle]) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1A1A1A),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMapCard() {
    bool isDesktop = Responsive.isDesktop(context);
    return Container(
      margin: isDesktop ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isDesktop ? 32 : 28),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: AppTheme.balancedPulidongShadow,
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: const Color(0xFFE3F2FD), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.location_on_rounded, color: Color(0xFF2196F3), size: 24)),
            title: const Text("Live Tracking",
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            subtitle: const Text("Real-time monitoring",
                style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
            trailing: _HoverZoomLink(
              onTap: () => setState(() => _selectedIndex = 1),
              child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration:
                      BoxDecoration(color: const Color(0xFFE0F2F1), borderRadius: BorderRadius.circular(12)),
                  child: const Text("Open Map",
                      style: TextStyle(
                          color: Color(0xFF00796B), fontWeight: FontWeight.w900, fontSize: 13))),
            ),
          ),
          Container(
            height: isDesktop ? 450 : 300,
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: const MapboxView(mode: 'dashboard'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleCard() {
    bool isDesktop = Responsive.isDesktop(context);
    return Container(
        margin: isDesktop ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: AppTheme.pulidongShadow),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("Collection Schedule", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
          const SizedBox(height: 4),
          const Text("Stay updated with your local collection times", style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
          const SizedBox(height: 24),
          _buildScheduleRow("Frequency", _getDynamicFrequency(), isBadge: true),
          const Divider(height: 32),
          _buildScheduleRow("Estimated Time", _getDynamicTime(), isBold: true),
          const Divider(height: 32),
          _buildScheduleRow("Area", _user?.purok ?? "Area", icon: Icons.location_searching_rounded)
        ]));
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
          // Animated Background Decoration
          Positioned.fill(
            child: Container(decoration: AppDecorations.authBackground),
          ),
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
          // Sidebar Content
          Column(
            children: [
              // Sidebar Header
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
                            BoxShadow(
                              color: AppColors.loginButtonStart.withOpacity(0.3),
                              blurRadius: 15,
                              offset: const Offset(0, 8),
                            )
                          ],
                        ),
                        child: const Icon(Icons.house_rounded, size: 36, color: Colors.white),
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
                        "RESIDENT PORTAL",
                        style: TextStyle(fontSize: 10, color: AppColors.tealText, fontWeight: FontWeight.w900, letterSpacing: 1.2),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(indent: 32, endIndent: 32),
              const SizedBox(height: 24),
              // Sidebar Items
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      _buildSidebarItem(0, Icons.home_rounded, 'Dashboard Home'),
                      const SizedBox(height: 8),
                      _buildSidebarItem(1, Icons.location_on_rounded, 'Truck Tracking'),
                      const SizedBox(height: 8),
                      _buildSidebarItem(2, Icons.chat_bubble_outline_rounded, 'Report Complaints'),
                      const SizedBox(height: 8),
                      _buildSidebarItem(3, Icons.person_outline_rounded, 'Account Settings'),
                    ],
                  ),
                ),
              ),
              // Sidebar Footer
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: _HoverZoomCard(
                  onTap: _handleLogout,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12), // Reduced height
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

  Widget _buildHeader(double width) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double screenWidth = MediaQuery.of(context).size.width;
    bool isMobile = width < 600;
    double bgHeight = isMobile ? (screenHeight * 0.22).clamp(180, 220) : 220;

    // Mobile/Tablet Layout (Original with Satin Green)
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
                builder: (context, child) => CustomPaint(
                  size: Size(double.infinity, bgHeight),
                  painter: HeaderCirclePainter(_circleController.value),
                ),
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
                            badgeCount: _unreadNotificationsCount > 0 ? _unreadNotificationsCount : null,
                            onTap: () => _showNotificationsModal(context),
                          ),
                          const SizedBox(width: 10),
                          _buildHeaderActionIcon(
                            Icons.logout_rounded,
                            onTap: _handleLogout,
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
                            image: (_user?.profilePictureUrl != null && _user!.profilePictureUrl!.isNotEmpty)
                                ? DecorationImage(
                                    image: NetworkImage(_user!.profilePictureUrl!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: (_user?.profilePictureUrl == null || _user!.profilePictureUrl!.isEmpty)
                              ? Center(
                                  child: Text(
                                    (_user?.name != null && _user!.name.isNotEmpty) ? _user!.name[0].toUpperCase() : "R",
                                    style: TextStyle(
                                      fontSize: (screenWidth * 0.06).clamp(20.0, 24.0),
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF00695C),
                                    ),
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
                            "Welcome back,",
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
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.location_on_rounded, color: Color(0xFF00796B), size: 14),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _user?.purok ?? "Detecting...",
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: locationFontSize,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _HoverZoomLink(
                      onTap: () => _showDataManagementModal(),
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
                  text: "Track Trash Truck",
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
    Color bgColor = isDark ? AppColors.tealText.withOpacity(0.1) : Colors.white.withOpacity(0.15);

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
              decoration: const BoxDecoration(color: Color(0xFFFF5252), shape: BoxShape.circle),
              child: Text("$badgeCount", style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
            ),
          ),
      ]),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color bgColor, {bool isLive = false}) {
    final bool isDesktop = Responsive.isDesktop(context);
    final Color primaryColor = isLive ? const Color(0xFF00796B) : const Color(0xFFFBC02D);
    
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isDesktop ? 32 : 28),
        boxShadow: AppTheme.balancedPulidongShadow,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Stack(
        children: [
          // Background "Glass" Highlight
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
          // Large Faded Background Icon
          Positioned(
            bottom: -15,
            right: -10,
            child: Icon(
              icon,
              size: 80,
              color: primaryColor.withOpacity(0.05),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
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
                      child: Icon(icon, color: primaryColor, size: 22),
                    ),
                    if (isLive) 
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE0F2F1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF00796B).withOpacity(0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF00796B),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              "LIVE", 
                              style: TextStyle(
                                color: Color(0xFF00796B), 
                                fontSize: 10, 
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5
                              )
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  title, 
                  style: TextStyle(
                    fontSize: 13, 
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
                        fontSize: 26, 
                        fontWeight: FontWeight.w900, 
                        color: isLive ? const Color(0xFF00796B) : const Color(0xFF1A1A1A),
                        letterSpacing: -1.0
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

  Widget _buildActionCard(String title, String subtitle, IconData icon, Color bgColor, Color iconColor) {
    bool isDesktop = Responsive.isDesktop(context);
    return _HoverZoomCard(
      onTap: () {
        if (title.contains("Track")) {
          setState(() => _selectedIndex = 1);
        } else if (title.contains("Settings")) {
          setState(() => _selectedIndex = 3);
        } else if (title.contains("Complaint")) {
          bool isModalLoading = true;
          if (Responsive.isDesktop(context)) {
            showDialog(
              context: context,
              builder: (context) => StatefulBuilder(
                builder: (context, setModalState) {
                  if (isModalLoading) {
                    Future.delayed(const Duration(milliseconds: 800), () {
                      if (mounted) setModalState(() => isModalLoading = false);
                    });
                  }
                  return Dialog(
                    backgroundColor: Colors.white,
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
                        maxHeight: isModalLoading ? 380 : MediaQuery.of(context).size.height * 0.85,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Expanded(child: Text("New Complaint", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.tealText))),
                                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.grey)),
                                  ],
                                ),
                                const Text("Report an issue or concern to the garbage collection service.", style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
                                const SizedBox(height: 16),
                                const Divider(height: 1),
                              ],
                            ),
                          ),
                          if (isModalLoading)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(color: AppColors.tealText),
                                    SizedBox(height: 16),
                                    Text("Preparing your complaint form...", 
                                        style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                            )
                          else
                            Flexible(
                              child: AddComplaintModal(
                                showHeader: false,
                                onSuccess: () {
                                  _refreshComplaints();
                                }
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }
              ),
            );
          } else {
            showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (context) => StatefulBuilder(
                  builder: (context, setModalState) {
                    if (isModalLoading) {
                      Future.delayed(const Duration(milliseconds: 800), () {
                        if (mounted) setModalState(() => isModalLoading = false);
                      });
                    }
                    return Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeInOutCubic,
                        constraints: BoxConstraints(
                          maxHeight: isModalLoading ? 380 : MediaQuery.of(context).size.height * 0.85,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 12), decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10))),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Expanded(child: Text("New Complaint", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.tealText))),
                                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.grey)),
                                    ],
                                  ),
                                  const Text("Report an issue or concern to the garbage collection service.", style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
                                  const SizedBox(height: 16),
                                  const Divider(height: 1),
                                ],
                              ),
                            ),
                            if (isModalLoading)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 60),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CircularProgressIndicator(color: AppColors.tealText),
                                      SizedBox(height: 16),
                                      Text("Preparing your complaint form...", 
                                          style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),
                              )
                            else
                              Flexible(
                                child: AddComplaintModal(
                                  showHeader: false,
                                  onSuccess: () {
                                    _refreshComplaints();
                                  }
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }
                ));
          }
        } else {
          Navigator.pushNamed(context, '/file_complaint');
        }
      },
      child: Container(
        margin: isDesktop ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 20),
        padding: isDesktop ? const EdgeInsets.all(28) : const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(isDesktop ? 28 : 24),
          boxShadow: AppTheme.pulidongShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(16)),
                    child: Icon(icon, color: iconColor, size: 26)),
                const SizedBox(width: 20),
                Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Color(0xFF1A1A1A))),
                  Text(subtitle,
                      style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500))
                ])),
                const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFE0E0E0), size: 16)
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleRow(String label, String value, {bool isBadge = false, bool isBold = false, IconData? icon}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600, fontSize: 14))
        ),
        const SizedBox(width: 12),
        if (isBadge) 
          Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(20)), child: Text(value, style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.w800, fontSize: 12))) 
        else if (icon != null) 
          Row(children: [Icon(icon, size: 14, color: const Color(0xFF3F51B5)), const SizedBox(width: 6), Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF3F51B5)))]) 
        else 
          Text(value, style: TextStyle(fontWeight: isBold ? FontWeight.w900 : FontWeight.w700, fontSize: 14, color: const Color(0xFF1A1A1A)))
      ]
    );
  }

  Widget _buildBottomNav() {
    final double bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(margin: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding > 0 ? bottomPadding : 12), height: 68, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(34), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 25, offset: const Offset(0, 10), spreadRadius: 2), BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2), spreadRadius: 1)], border: Border.all(color: Colors.white, width: 1.5)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_buildNavItem(0, Icons.home_rounded, 'Home'), _buildNavItem(1, Icons.location_on_rounded, 'Track'), _buildNavItem(2, Icons.chat_bubble_rounded, 'Report'), _buildNavItem(3, Icons.settings_suggest_rounded, 'Settings')]));
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    bool isSelected = _selectedIndex == index;
    final double screenWidth = MediaQuery.of(context).size.width;
    final double labelFontSize = (screenWidth * 0.035).clamp(11.0, 14.0);
    final double iconSize = (screenWidth * 0.065).clamp(22.0, 26.0);
    return _HoverZoomLink(onTap: () { setState(() { _selectedIndex = index; if (index != 3) _shouldShowDataManagement = false; }); }, child: Center(child: AnimatedContainer(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut, padding: EdgeInsets.symmetric(horizontal: isSelected ? 16 : 8, vertical: 8), decoration: BoxDecoration(color: isSelected ? const Color(0xFF00796B).withOpacity(0.1) : Colors.transparent, borderRadius: BorderRadius.circular(18)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: isSelected ? const Color(0xFF00796B) : const Color(0xFF9E9E9E), size: iconSize), if (isSelected) ...[const SizedBox(width: 8), Text(label, style: TextStyle(color: const Color(0xFF00796B), fontSize: labelFontSize, fontWeight: FontWeight.w900, letterSpacing: -0.3))]] ))));
  }

  Widget _buildTransactionHistoryCard() {
    bool isDesktop = Responsive.isDesktop(context);
    return Container(
      margin: isDesktop ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: AppTheme.pulidongShadow,
      ),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Complaint History", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 24),
          if (_user == null)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: AppColors.tealText, strokeWidth: 3)))
          else
            FutureBuilder<Response>(
              future: _complaintsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: AppColors.tealText, strokeWidth: 3)));
                }
                if (snapshot.hasError || !snapshot.hasData || snapshot.data?.data['success'] != true) {
                  return const Text("No complaints recorded.", style: TextStyle(color: Colors.grey));
                }
                final List all = snapshot.data!.data['data'] ?? [];
                final List filtered = all
                    .where((c) =>
                        (c['user_id'] ?? c['resident_id']).toString() == _user?.userId.toString())
                    .toList();
                if (filtered.isEmpty) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(color: Color(0xFFF8F9FA), shape: BoxShape.circle),
                        child: const Icon(Icons.assignment_turned_in_rounded, size: 40, color: Colors.black12),
                      ),
                      const SizedBox(height: 12),
                      const Text("No Found Complaint History",
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.grey)),
                      const SizedBox(height: 20),
                    ],
                  );
                }
                return Column(
                  children: filtered.take(2).map((c) {
                    return _HoverZoomCard(
                      onTap: () {
                        setState(() {
                          _targetComplaintId = c['complaint_id'].toString();
                          _selectedIndex = 2;
                          _complaintsRefreshCount++; // Force recreate to trigger auto-scroll
                        });
                      },
                      child: _buildTransactionItem(c),
                    );
                  }).toList(),
                );
              },
            ),
          const SizedBox(height: 16),
          Center(
            child: _HoverZoomLink(
              onTap: () {
                if (_user != null && _complaintsFuture != null) {
                  _showAllComplaintsModal(context);
                }
              },
              child: const Text("View All History",
                  style: TextStyle(color: Color(0xFF00796B), fontWeight: FontWeight.w800, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  void _showAllComplaintsModal(BuildContext context) {
    bool isModalLoading = true;
    
    void _showModal(BuildContext context) {
      showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setModalState) {
            if (isModalLoading) {
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted) setModalState(() => isModalLoading = false);
              });
            }

            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOutCubic,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                ),
                constraints: BoxConstraints(
                  maxWidth: 600, 
                  maxHeight: isModalLoading 
                      ? 350 
                      : 650,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!Responsive.isDesktop(context))
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(top: 12),
                        decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10)),
                      ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                          Responsive.isDesktop(context) ? 32 : 24,
                          Responsive.isDesktop(context) ? 32 : 12,
                          Responsive.isDesktop(context) ? 32 : 24,
                          Responsive.isDesktop(context) ? 32 : 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Text("All Complaint Records",
                                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF00796B))),
                              ),
                              IconButton(
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(Icons.close_rounded, color: Colors.grey)),
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text("Click on a report to view details and status.",
                                  style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Divider(height: 1),
                          ),
                          if (isModalLoading)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.all(40),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(color: AppColors.tealText),
                                    SizedBox(height: 16),
                                    Text("Fetching your complaint records...",
                                        style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                            )
                          else
                            Flexible(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 400),
                                child: FutureBuilder<Response>(
                                  future: _complaintsFuture,
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState == ConnectionState.waiting) {
                                      return const Center(
                                        child: Padding(
                                          padding: EdgeInsets.all(40),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              CircularProgressIndicator(color: AppColors.tealText, strokeWidth: 3),
                                              SizedBox(height: 16),
                                              Text("Loading details...",
                                                  style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
                                            ],
                                          )
                                        )
                                      );
                                    }
                                    final List all = snapshot.data?.data['data'] ?? [];
                                    final List filtered = all
                                        .where((c) => (c['user_id'] ?? c['resident_id']).toString() == _user?.userId.toString())
                                        .toList();

                                    if (filtered.isEmpty) {
                                      return const Center(child: Text("No records found.", style: TextStyle(color: Colors.grey)));
                                    }

                                    return Scrollbar(
                                      thumbVisibility: true,
                                      child: ListView.builder(
                                        shrinkWrap: true,
                                        padding: const EdgeInsets.only(right: 12),
                                        itemCount: filtered.length,
                                        itemBuilder: (context, index) {
                                          final c = filtered[index];
                                          return _HoverZoomCard(
                                            onTap: () {
                                              Navigator.pop(context);
                                              final String cid = c['complaint_id'].toString();
                                              setState(() {
                                                _selectedIndex = 2;
                                                _targetComplaintId = cid;
                                                _complaintsRefreshCount++; // Force recreate
                                              });
                                            },
                                            child: _buildTransactionItem(c),
                                          );
                                        },
                                      ),
                                    );
                                  },
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
          },
        ),
      );
    }

    void _showBottomSheet(BuildContext context) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => StatefulBuilder(
          builder: (context, setModalState) {
            if (isModalLoading) {
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted) setModalState(() => isModalLoading = false);
              });
            }

            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOutCubic,
                constraints: BoxConstraints(
                  maxHeight: isModalLoading 
                      ? 380 
                      : MediaQuery.of(context).size.height * 0.8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(top: 12),
                      decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Text("All Complaint Records",
                                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF00796B))),
                              ),
                              IconButton(
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(Icons.close_rounded, color: Colors.grey)),
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text("Click on a report to view details and status.",
                                  style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Divider(height: 1),
                          ),
                          if (isModalLoading)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.all(40),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(color: AppColors.tealText),
                                    SizedBox(height: 16),
                                    Text("Fetching your complaint records...",
                                        style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                            )
                          else
                            Flexible(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                                child: FutureBuilder<Response>(
                                  future: _complaintsFuture,
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState == ConnectionState.waiting) {
                                      return const Center(
                                        child: Padding(
                                          padding: EdgeInsets.all(40),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              CircularProgressIndicator(color: AppColors.tealText, strokeWidth: 3),
                                              SizedBox(height: 16),
                                              Text("Loading details...",
                                                  style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
                                            ],
                                          )
                                        )
                                      );
                                    }
                                    final List all = snapshot.data?.data['data'] ?? [];
                                    final List filtered = all
                                        .where((c) => (c['user_id'] ?? c['resident_id']).toString() == _user?.userId.toString())
                                        .toList();

                                    if (filtered.isEmpty) {
                                      return const Center(child: Text("No records found.", style: TextStyle(color: Colors.grey)));
                                    }

                                    return ListView.builder(
                                      shrinkWrap: true,
                                      padding: const EdgeInsets.only(bottom: 20),
                                      itemCount: filtered.length,
                                      itemBuilder: (context, index) {
                                        final c = filtered[index];
                                        return _HoverZoomCard(
                                          onTap: () {
                                            Navigator.pop(context);
                                            final String cid = c['complaint_id'].toString();
                                            setState(() {
                                              _selectedIndex = 2;
                                              _targetComplaintId = cid;
                                              _complaintsRefreshCount++; // Force recreate
                                            });
                                          },
                                          child: _buildTransactionItem(c),
                                        );
                                      },
                                    );
                                  },
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
          },
        ),
      );
    }

    if (Responsive.isDesktop(context)) {
      _showModal(context);
    } else {
      _showBottomSheet(context);
    }
  }

  Widget _buildTransactionItem(Map c) {
    bool hasResponse = c['admin_response'] != null && c['admin_response'].toString().isNotEmpty;
    Color statusColor = hasResponse ? const Color(0xFF3F51B5) : Colors.grey;
    Color statusBgColor = hasResponse ? const Color(0xFFE8EAF6) : Colors.grey.shade100;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.description_outlined, size: 18, color: statusColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              c['category'] ?? "Unknown Complaint",
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1A1A1A)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasResponse)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: statusBgColor, borderRadius: BorderRadius.circular(8)),
              child: Text("Responded", style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.w900)),
            ),
        ],
      ),
    );
  }

  String _getDynamicFrequency() {
    if (_user?.purok == null || _user!.purok!.isEmpty) return "Weekly";
    final String p = _user!.purok!;
    if (p.contains("Sentro") || p.contains("Home Subdivision") || p.contains("Tanco")) return "Daily";
    return "Weekly";
  }

  String _getDynamicTime() {
    if (_user?.purok == null || _user!.purok!.isEmpty) return "8:00 AM - 10:00 AM";
    final String p = _user!.purok!;
    if (p.contains("1") || p.contains("2") || p.contains("3") || p.contains("4")) {
      return "6:00 AM - 8:00 AM";
    }
    if (p.contains("Dos Riles") || p.contains("Sentro") || p.contains("San Isidro")) {
      return "8:00 AM - 10:00 AM";
    }
    if (p.contains("Paraiso") || p.contains("Riverside") || p.contains("Kalaw")) {
      return "10:00 AM - 12:00 PM";
    }
    return "1:00 PM - 3:00 PM";
  }

  void _showNotificationsModal(BuildContext context) {
    final GlobalKey<AnimatedListState> listKey = GlobalKey<AnimatedListState>();
    List<Map> notifications = [];
    bool isClearingAll = false;

    // Selection State
    bool isSelectionMode = false;
    Set<String> selectedKeys = {};
    bool isModalLoading = true; // Moved outside showDialog builder
    bool timerStarted = false; // Flag para siguradong iisang beses lang ang timer

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            if (isModalLoading && !timerStarted) {
              timerStarted = true;
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted) {
                  setModalState(() => isModalLoading = false);
                }
              });
            }



            void toggleSelection(String key) {
              setModalState(() {
                if (selectedKeys.contains(key)) {
                  selectedKeys.remove(key);
                } else {
                  selectedKeys.add(key);
                }
              });
            }

            void cancelSelection() {
              setModalState(() {
                isSelectionMode = false;
                selectedKeys.clear();
              });
            }

            void selectAll() {
              setModalState(() {
                for (var n in notifications) {
                  selectedKeys.add(n['key'].toString());
                }
              });
            }

            Future<void> deleteSelected() async {
              if (selectedKeys.isEmpty) return;
              bool confirmed = await _showConfirmDialog(
                  title: "Delete Selected?",
                  message: "Remove ${selectedKeys.length} selected alerts permanently?",
                  isDestructive: true);

              if (confirmed) {
                setModalState(() => isClearingAll = true);
                final keysToRemove = List<String>.from(selectedKeys);
                
                for (String key in keysToRemove) {
                  int idx = notifications.indexWhere((n) => n['key'] == key);
                  if (idx != -1) {
                    final removedItem = notifications[idx];
                    notifications.removeAt(idx);
                    
                    listKey.currentState?.removeItem(
                      idx,
                      (context, animation) => SlideTransition(
                        position: animation.drive(Tween<Offset>(begin: const Offset(1.5, 0.0), end: Offset.zero)),
                        child: FadeTransition(
                          opacity: animation,
                          child: SizeTransition(sizeFactor: animation, axisAlignment: -1.0, child: _buildNotificationItem(removedItem, const AlwaysStoppedAnimation(1.0))),
                        ),
                      ),
                      duration: const Duration(milliseconds: 300),
                    );
                    _database.ref('notifications/$key').remove();
                    await Future.delayed(const Duration(milliseconds: 80));
                  }
                }
                
                setModalState(() {
                  selectedKeys.clear();
                  isSelectionMode = false;
                  isClearingAll = false;
                });
                _showSnackBar("Successfully deleted selected notifications");
              }
            }

            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOutCubic,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                ),
                constraints: BoxConstraints(
                  maxWidth: 500, 
                  maxHeight: isModalLoading 
                      ? 350 
                      : MediaQuery.of(context).size.height * 0.75,
                ),
                padding: const EdgeInsets.fromLTRB(0, 12, 0, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              isSelectionMode ? "Select Alerts" : "Notifications",
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF00796B),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 4, 28, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          isSelectionMode ? "${selectedKeys.length} alerts selected" : "Recently received system notifications",
                          style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 28),
                      child: Divider(height: 32),
                    ),
                    if (isModalLoading)
                      const Expanded(
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(color: AppColors.tealText),
                                SizedBox(height: 16),
                                Text("Loading your notifications...",
                                    style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: StreamBuilder<DatabaseEvent>(
                        stream: _database.ref('notifications').onValue,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(40),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(color: AppColors.tealText),
                                    SizedBox(height: 16),
                                    Text("Loading your notifications...",
                                        style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                            );
                          }
                          if (snapshot.hasData && snapshot.data!.snapshot.exists) {
                            if (!isClearingAll) {
                              final Map data = snapshot.data!.snapshot.value as Map;
                              List<Map> newList = [];
                              data.forEach((k, v) {
                                final val = v as Map;
                                final String type = (val['type'] ?? '').toString();
                                final String targetPurok =
                                    (val['purok'] ?? val['area'] ?? '').toString();
                                final String residentId = (val['resident_id'] ?? '').toString();
                                bool isRelevant = (type == 'TRUCK_PROXIMITY' &&
                                        (targetPurok == '' || targetPurok == _user?.purok)) ||
                                    (type == 'COMPLAINT_RESOLVED' &&
                                        residentId == _user?.userId.toString());
                                if (isRelevant) {
                                  val['key'] = k;
                                  newList.add(val);
                                }
                              });
                              newList.sort(
                                  (a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
                              notifications = newList;
                            }

                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Action Toolbar (Only shown in Selection Mode)
                                if (isSelectionMode && notifications.isNotEmpty && !isClearingAll)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        _HoverZoomLink(
                                          onTap: selectAll,
                                          child: Text(
                                            selectedKeys.length == notifications.length ? "All Selected" : "Select All",
                                            style: const TextStyle(color: Color(0xFF8BC34A), fontWeight: FontWeight.w800, fontSize: 13),
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            if (selectedKeys.isNotEmpty)
                                              _HoverZoomLink(
                                                onTap: deleteSelected,
                                                child: const Text("Delete",
                                                    style: TextStyle(
                                                        color: Colors.red,
                                                        fontWeight: FontWeight.w900,
                                                        fontSize: 13)),
                                              ),
                                            const SizedBox(width: 16),
                                            _HoverZoomLink(
                                              onTap: cancelSelection,
                                              child: const Text("Cancel",
                                                  style: TextStyle(
                                                      color: Colors.grey,
                                                      fontWeight: FontWeight.w800,
                                                      fontSize: 13)),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                if (notifications.isEmpty && !isClearingAll)
                                  _buildEmptyState()
                                else
                                  Flexible(
                                    child: Stack(
                                      children: [
                                        if (isClearingAll)
                                          Positioned.fill(child: Center(child: _buildEmptyState())),
                                        ClipRect(
                                          child: SingleChildScrollView(
                                            physics: const BouncingScrollPhysics(),
                                            clipBehavior: Clip.none,
                                            padding: const EdgeInsets.symmetric(horizontal: 28),
                                            child: AnimatedList(
                                              key: listKey,
                                              shrinkWrap: true,
                                              physics: const NeverScrollableScrollPhysics(),
                                              initialItemCount: notifications.length,
                                              itemBuilder: (context, index, animation) {
                                                if (index >= notifications.length)
                                                  return const SizedBox();
                                                final item = notifications[index];
                                                final String key = item['key'].toString();
                                                return _buildDismissibleNotification(
                                                    item,
                                                    index,
                                                    listKey,
                                                    setModalState,
                                                    notifications,
                                                    isSelectionMode: isSelectionMode,
                                                    isSelected: selectedKeys.contains(key),
                                                    onDoubleTap: Responsive.isDesktop(context) ? () {
                                                      setModalState(() {
                                                        isSelectionMode = true;
                                                        selectedKeys.add(key);
                                                      });
                                                    } : null,
                                                    onLongPress: !Responsive.isDesktop(context) ? () {
                                                      setModalState(() {
                                                        isSelectionMode = true;
                                                        selectedKeys.add(key);
                                                      });
                                                    } : null,
                                                    onTap: () {
                                                      if (isSelectionMode) toggleSelection(key);
                                                    }
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            );
                          }
                          return _buildEmptyState();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      _markNotificationsAsRead(notifications);
    });
  }

  void _markNotificationsAsRead(List<Map> notifications) async {
    for (var notif in notifications) {
      if (notif['isRead'] == false) {
        final String key = notif['key'].toString();
        await _database.ref('notifications/$key').update({'isRead': true});
      }
    }
  }

  Widget _buildEmptyState() {
    return const Column(children: [
      const SizedBox(height: 48),
      CircleAvatar(
          radius: 40,
          backgroundColor: Color(0xFFF5F5F5)),
      SizedBox(height: 16),
      Text("All caught up!", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.grey)),
      SizedBox(height: 48)
    ]);
  }

  Future<void> _handleClearAllNotifications(
      List<Map> notifications, GlobalKey<AnimatedListState> listKey, StateSetter setModalState) async {
    if (notifications.isEmpty) return;
    bool confirmed = await _showConfirmDialog(
        title: "Clear All?",
        message: "Permanently remove all alerts?",
        isDestructive: true);
    if (confirmed) {
      final List<Map> toRemove = List.from(notifications);
      // Immediately mark as clearing to hide the button
      setModalState(() {});

      for (int i = 0; i < toRemove.length; i++) {
        if (notifications.isEmpty) break;
        final removedItem = notifications[0];
        final String key = removedItem['key'].toString();

        // 1. Remove from local list to keep UI in sync
        notifications.removeAt(0);

        // 2. Trigger removal animation (Slide right + Fade)
        listKey.currentState?.removeItem(
          0,
          (context, animation) {
            return SlideTransition(
              position: animation.drive(Tween<Offset>(
                begin: const Offset(1.5, 0.0), // Slide right out of view
                end: Offset.zero,
              )),
              child: FadeTransition(
                opacity: animation,
                child: SizeTransition(
                  sizeFactor: animation,
                  axisAlignment: -1.0, // Shrink towards top
                  child: _buildNotificationItem(removedItem, const AlwaysStoppedAnimation(1.0)),
                ),
              ),
            );
          },
          duration: const Duration(milliseconds: 400),
        );

        // 3. Remove from Firebase
        _database.ref('notifications/$key').remove();

        // 4. Update UI step by step
        setModalState(() {});

        await Future.delayed(const Duration(milliseconds: 100));
      }

      _showSnackBar("Successful cleared all notifications");
      if (mounted) setModalState(() {});
    }
  }

  Widget _buildDismissibleNotification(Map item, int index, GlobalKey<AnimatedListState> listKey,
      StateSetter setModalState, List<Map> currentList, {bool isSelectionMode = false, bool isSelected = false, VoidCallback? onTap, VoidCallback? onDoubleTap, VoidCallback? onLongPress}) {
    return Dismissible(
        key: Key(item['key'].toString()),
        direction: isSelectionMode ? DismissDirection.none : DismissDirection.horizontal,
        confirmDismiss: (direction) async {
          return await _showConfirmDialog(
              title: "Delete Notification?",
              message: "Are you sure you want to remove this alert?",
              isDestructive: true);
        },
        onDismissed: (direction) {
          final String key = item['key'].toString();
          _database.ref('notifications/$key').remove();
          _showSnackBar("Successful delete notification");
        },
        background: _buildSwipeBackground(Alignment.centerLeft),
        secondaryBackground: _buildSwipeBackground(Alignment.centerRight),
        child: _buildNotificationItem(item, const AlwaysStoppedAnimation(1.0), isSelectionMode: isSelectionMode, isSelected: isSelected, onTap: onTap, onDoubleTap: onDoubleTap, onLongPress: onLongPress));
  }

  Widget _buildSwipeBackground(Alignment alignment) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12, left: 10, right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(24)),
      alignment: alignment,
    );
  }

  Future<bool> _showConfirmDialog(
      {required String title, required String message, bool isDestructive = false}) async {
    return await showDialog(
            context: context,
            builder: (context) => Dialog(
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 16),
                        Text(message,
                            textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                        const SizedBox(height: 32),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context, false),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: Colors.grey.shade300),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text("CANCEL", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w900)),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: HoverActionButton(
                                  text: "CONFIRM",
                                  color: isDestructive ? null : const Color(0xFF00796B),
                                  isDestructive: isDestructive,
                                  onTap: () => Navigator.pop(context, true)),
                            ),
                          ],
                        ),
                      ])),
                ))) ??
        false;
  }

  Map<String, dynamic> _getNotificationStyle(String type) {
    if (type == 'TRUCK_PROXIMITY') {
      return {
        'icon': Icons.local_shipping_rounded,
        'color': const Color(0xFFFF9800),
        'bgColor': const Color(0xFFFFF3E0),
      };
    } else if (type == 'COMPLAINT_RESOLVED') {
      return {
        'icon': Icons.assignment_turned_in_rounded,
        'color': const Color(0xFF3F51B5),
        'bgColor': const Color(0xFFE8EAF6),
      };
    } else if (type == 'MAINTENANCE_ALERT') {
      return {
        'icon': Icons.warning_rounded,
        'color': const Color(0xFFF44336),
        'bgColor': const Color(0xFFFFEBEE),
      };
    } else if (type == 'ISSUE_UPDATE') {
      return {
        'icon': Icons.info_rounded,
        'color': const Color(0xFF03A9F4),
        'bgColor': const Color(0xFFE1F5FE),
      };
    } else {
      return {
        'icon': Icons.notifications_rounded,
        'color': const Color(0xFF00796B),
        'bgColor': const Color(0xFFE0F2F1),
      };
    }
  }

  Widget _buildNotificationItem(Map item, Animation<double> animation, {bool isSelectionMode = false, bool isSelected = false, VoidCallback? onTap, VoidCallback? onDoubleTap, VoidCallback? onLongPress}) {
    final String type = (item['type'] ?? '').toString();
    final style = _getNotificationStyle(type);
    final Color themeColor = style['color'];
    final Color bgColor = style['bgColor'];
    final IconData icon = style['icon'];

    return FadeTransition(
        opacity: animation,
        child: SizeTransition(
            sizeFactor: animation,
            child: _HoverZoomCard(
                onTap: isSelectionMode ? onTap : () {
                  Navigator.pop(context);
                  if (type == 'COMPLAINT_RESOLVED')
                    setState(() => _selectedIndex = 2);
                  else if (type == 'TRUCK_PROXIMITY') setState(() => _selectedIndex = 1);
                },
                child: GestureDetector(
                  onDoubleTap: onDoubleTap,
                  onLongPress: onLongPress,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(bottom: 12, left: 4, right: 4),
                    decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFE0F2F1) : Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: isSelected ? const Color(0xFF00796B) : Colors.black12, width: isSelected ? 2 : 1.5)),
                    child: Stack(
                      children: [
                        ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            leading: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: isSelected ? const Color(0xFF00796B).withOpacity(0.1) : bgColor, borderRadius: BorderRadius.circular(16)),
                                child: Icon(
                                    icon,
                                    color: themeColor,
                                    size: 24)),
                            title: Text(item['title'] ?? 'Alert',
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                            subtitle: Text(item['message'] ?? '',
                                style: const TextStyle(fontSize: 13, color: Color(0xFF666666)))),
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
                ))));
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    CustomSnackBar.show(context, message: message, isError: isError);
  }

  void _showDataManagementModal() {
    if (_user == null) return;
    _showStyledBottomSheet(
      title: "Edit Account",
      description: "Update your profile details and account settings here.",
      maxHeightMultiplier: 0.9,
      children: [
        DataManagementModal(user: _user!, onSuccess: _loadUser),
      ],
    );
  }

  void _showStyledBottomSheet({required String title, required List<Widget> children, String? description, double maxHeightMultiplier = 0.6}) {
    bool isModalLoading = true;
    
    if (Responsive.isDesktop(context)) {
      showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setModalState) {
            if (isModalLoading) {
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted) setModalState(() => isModalLoading = false);
              });
            }

            return Dialog(
              backgroundColor: Colors.white,
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
                  maxHeight: isModalLoading ? 300 : 600
                ),
                child: Container(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.tealText))),
                          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.grey)),
                        ],
                      ),
                      if (description != null && description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(description, style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
                      ],
                      const Divider(height: 32),
                      if (isModalLoading)
                        const Expanded(
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.all(40),
                              child: CircularProgressIndicator(color: AppColors.tealText),
                            ),
                          ),
                        )
                      else
                        Flexible(child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: children))),
                    ],
                  ),
                ),
              ),
            );
          },
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
            Future.delayed(const Duration(milliseconds: 800), () {
              if (mounted) setModalState(() => isModalLoading = false);
            });
          }

          return Container(
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOutCubic,
              constraints: BoxConstraints(
                maxHeight: isModalLoading ? 300 : MediaQuery.of(context).size.height * maxHeightMultiplier
              ),
              padding: EdgeInsets.fromLTRB(0, 12, 0, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom),
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
                  if (description != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          description,
                          textAlign: TextAlign.left,
                          style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  const Divider(height: 32),
                  if (isModalLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(color: AppColors.tealText),
                      ),
                    )
                  else
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.only(bottom: 40), 
                          child: Column(mainAxisSize: MainAxisSize.min, children: children)
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
