import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoSliverRefreshControl;
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../utils/custom_notification.dart';
import '../api/api_service.dart';
import '../utils/session_manager.dart';
import '../utils/app_theme.dart';
import '../utils/system_logger.dart';
import '../utils/responsive.dart';
import 'analytics_screen.dart';
import 'track_trucks_screen.dart';
import 'complaints_screen.dart';
import 'admin_settings_screen.dart';
import 'data_management_screen.dart';
import 'user_management_screen.dart';
import '../widgets/mapbox_view.dart';
import '../services/admin_settings_service.dart';
import '../services/notification_service.dart';
import '../widgets/header_circle_painter.dart';
import '../widgets/hover_action_button.dart';
import '../widgets/fade_slide_entrance.dart';
import '../widgets/data_management_modal.dart';
import '../utils/route_persistence_manager.dart';
import '../utils/app_localizations.dart';
import '../utils/responsive_text.dart';
import '../models/user.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final ApiService _apiService = ApiService();
  final AdminSettingsService _adminSettingsService = AdminSettingsService();
  final ScrollController _scrollController = ScrollController();
  bool _showHeaderShadow = true;

  double _averageSpeed = 0.0;
  int _activeHotspots = 0;
  int _totalRoutesToday = 0;
  int _completedRoutesToday = 0;
  int _resolvedComplaints = 0;
  int _totalComplaints = 0;
  int _activeTrucks = 0;
  int _pendingComplaints = 0;
  int _inProgressComplaints = 0;
  int _residentsCount = 0;
  int _unreadNotificationsCount = 0;
  double _coveragePercent = 0.0;
  int _selectedIndex = 0;
  bool _isSidebarExtended = true;
  bool _isRefreshing = false;
  bool _showRefreshSpinner = false;
  late AnimationController _circleController;
  late AnimationController _refreshRotationController;
  UserData? _user;
  StreamSubscription? _userSubscription;
  String _currentTime = "";
  Timer? _clockTimer;

  List<Map<dynamic, dynamic>> _fleetStatus = [];
  List<Map<dynamic, dynamic>> _recentLogs = [];

  @override
  void initState() {
    super.initState();
    _loadUser();
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
    RoutePersistenceManager.saveLastRoute('/admin_dashboard');
    _adminSettingsService.startListening();
    _setupListeners();
    _refreshAllStats();
    _checkAutoBackupDownload();
    _setupLogsListener();
  }

  void _loadUser() async {
    _user = await SessionManager.getUser();
    if (_user != null) {
      NotificationService.startListening(_user!);
      _setupUserListener();
    }
    if (mounted) setState(() {});
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
      setState(() {
        _currentTime = time;
      });
    }
  }

  @override
  void dispose() {
    _circleController.dispose();
    _refreshRotationController.dispose();
    _clockTimer?.cancel();
    _userSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _setupLogsListener() {
    _database.ref('system_logs').limitToLast(10).onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map? data = event.snapshot.value as Map?;
        if (data == null) return;
        final List<Map<dynamic, dynamic>> logs = [];
        data.forEach((key, value) {
          if (value is Map) logs.add(Map<dynamic, dynamic>.from(value));
        });
        logs.sort((a, b) => (b['timestamp'] ?? 0).toString().compareTo((a['timestamp'] ?? 0).toString()));
        if (mounted) setState(() => _recentLogs = logs);
      }
    });
  }

  Future<void> _checkAutoBackupDownload() async {
    try {
      final user = await SessionManager.getUser();
      if (user == null || user.role != 'admin') return;
      final settingsRes = await _apiService.getUserSettings(user.userId, user.role);
      final settingsData = settingsRes.data;
      if (settingsData is Map && settingsData['success'] == true && settingsData['data'] != null && settingsData['data']['auto_backup'] == true) {
        final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final lastDownload = await SessionManager.getLastAutoDownloadDate();
        if (lastDownload != today) {
          final response = await _apiService.triggerAutoBackupChecker();
          final data = response.data;
          if (data is Map && data['success'] == true && data['url'] != null) {
            final uri = Uri.parse(data['url']);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
              await SessionManager.setLastAutoDownloadDate(today);
              if (mounted) CustomNotification.showTopNotification(context, "Daily auto-backup downloaded: ${data['filename']}", false);
            }
          }
        }
      }
    } catch (e) { debugPrint("Auto-backup check error: $e"); }
  }

  Future<void> _refreshAllStats({bool manual = false}) async {
    if (_isRefreshing) return;
    
    debugPrint("[REFRESH] Starting refresh. Manual: $manual");
    
    if (mounted) {
      setState(() {
        _isRefreshing = true;
        _showRefreshSpinner = manual;
      });
    }
    _refreshRotationController.repeat();

    try {
      await Future.wait([
        _fetchComplaints(),
        _fetchUserCounts(),
        Future.delayed(const Duration(milliseconds: 1500)),
      ]);
    } catch (e) {
      debugPrint("[REFRESH] Error during data fetch: $e");
    }

    if (manual) {
      debugPrint("[REFRESH] Data loaded, holding for 2 seconds...");
      // Stay displayed and keep spinning for 2 more seconds after data is loaded
      // so the user can clearly see the refresh finished before it retreats.
      await Future.delayed(const Duration(seconds: 2));
    }

    if (mounted) {
      debugPrint("[REFRESH] Retreating spinner...");
      setState(() {
        _isRefreshing = false;
      });
      // Delay setting _showRefreshSpinner to false to allow retreat animation
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) setState(() => _showRefreshSpinner = false);
      _refreshRotationController.stop();
      
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
                      Text(
                        "Dashboard metrics synchronized",
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF1A1A1A)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      }
    }
    debugPrint("[REFRESH] Refresh sequence complete.");
  }

  Future<void> _fetchUserCounts() async {
    try {
      final response = await _apiService.getUsers();
      if (response.data['success'] == true) {
        final List residents = response.data['residents'] ?? [];
        if (mounted) setState(() => _residentsCount = residents.length);
      }
    } catch (e) { debugPrint("Error fetching user counts: $e"); }
  }

  void _setupListeners() {
    _database.ref('truck_locations').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map? data = event.snapshot.value as Map?;
        if (data == null) return;
        
        final Map<String, Map<dynamic, dynamic>> driverToLatestTruck = {};
        
        data.forEach((key, value) {
          if (value != null) {
            final truckMap = Map<dynamic, dynamic>.from(value as Map);
            final String nodeKey = key.toString();
            final String? dId = truckMap['driver_id']?.toString();
            
            truckMap['internal_id'] = nodeKey;
            if (truckMap['truck_id'] == null) {
              truckMap['truck_id'] = nodeKey;
            }

            if (dId == null) {
              driverToLatestTruck["node_$nodeKey"] = truckMap;
            } else {
              if (!driverToLatestTruck.containsKey(dId)) {
                driverToLatestTruck[dId] = truckMap;
              } else {
                final existing = driverToLatestTruck[dId]!;
                final bool existingOnline = existing['isOnline'] == true;
                final bool currentOnline = truckMap['isOnline'] == true;
                final int existingSeen = (existing['lastSeen'] ?? 0) as int;
                final int currentSeen = (truckMap['lastSeen'] ?? 0) as int;
                
                if (currentOnline && !existingOnline) {
                  driverToLatestTruck[dId] = truckMap;
                } else if (currentOnline == existingOnline && currentSeen > existingSeen) {
                  driverToLatestTruck[dId] = truckMap;
                }
              }
            }
          }
        });

        final List<Map<dynamic, dynamic>> trucks = driverToLatestTruck.values.toList();
        double totalSpeed = 0.0;
        int activeWithSpeed = 0;

        for (var t in trucks) {
          if (t['isOnline'] == true) {
            final speed = double.tryParse(t['speed']?.toString() ?? '0') ?? 0.0;
            if (speed > 0) {
              totalSpeed += speed;
              activeWithSpeed++;
            }
          }
        }

        if (mounted) {
          setState(() {
            _activeTrucks = trucks.where((t) => t['isOnline'] == true).length;
            _fleetStatus = trucks;
            _averageSpeed = activeWithSpeed > 0 ? totalSpeed / activeWithSpeed : 0.0;
          });
        }
      }
    });

    _database.ref('driver_routes').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map? data = event.snapshot.value as Map?;
        if (data == null) return;
        int total = 0;
        int completed = 0;
        data.forEach((key, value) {
          if (value != null && value is Map) {
            total++;
            if (value['route_status'] == 'COMPLETED' || value['status'] == 'COMPLETED') completed++;
          }
        });
        if (mounted) {
          setState(() {
            _totalRoutesToday = total;
            _completedRoutesToday = completed;
            _coveragePercent = total > 0 ? (completed / total) * 100 : 0.0;
          });
        }
      }
    });

    _database.ref('complaints').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map? data = event.snapshot.value as Map?;
        if (data == null) return;
        int pending = 0; int inProgress = 0; int resolved = 0; int total = 0;
        String normalize(dynamic s) {
          if (s == null) return 'PENDING';
          String str = s.toString().toLowerCase().trim();
          if (str == 'in_progress' || (str.contains('in') && str.contains('progress'))) return 'IN_PROGRESS';
          if (str == 'resolved' || str == 'completed') return 'RESOLVED';
          return 'PENDING';
        }
        final Map<String, int> areaComplaints = {};
        data.forEach((key, value) {
          if (value != null && value is Map) {
            total++;
            final status = normalize(value['status']);
            if (status == 'PENDING') {
              pending++;
              if (value['purok'] != null) {
                final area = value['purok'].toString();
                areaComplaints[area] = (areaComplaints[area] ?? 0) + 1;
              }
            } else if (status == 'IN_PROGRESS') inProgress++;
            else if (status == 'RESOLVED') resolved++;
          }
        });
        if (mounted) {
          setState(() {
            _totalComplaints = total; _resolvedComplaints = resolved;
            _pendingComplaints = pending; _inProgressComplaints = inProgress;
            _activeHotspots = areaComplaints.values.where((count) => count > 3).length;
          });
        }
      }
    });

    _database.ref('notifications').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map? data = event.snapshot.value as Map?;
        if (data == null) return;
        int unread = 0;
        data.forEach((key, value) {
          if (value != null && value is Map && _isNotificationForMe(value) && value['isRead'] == false) unread++;
        });
        if (mounted) setState(() => _unreadNotificationsCount = unread);
      } else { if (mounted) setState(() => _unreadNotificationsCount = 0); }
    });
  }

  bool _isNotificationForMe(Map val) {
    final String type = (val['type'] ?? '').toString();
    final String targetRole = (val['targetRole'] ?? '').toString();
    if (targetRole == 'admin') return true;
    if (['DRIVER_ISSUE', 'RESIDENT_COMPLAINT', 'REGISTRATION', 'NEW_REGISTRATION', 'TRUCK_ISSUE'].contains(type)) {
      return true;
    }
    return false;
  }

  Future<void> _fetchComplaints() async {
    try {
      final response = await _apiService.getComplaints();
      if (response.data['success'] == true) {
        final List complaints = response.data['data'] ?? [];
        String normalize(dynamic s) {
          if (s == null) return 'PENDING';
          String str = s.toString().toLowerCase().trim();
          if (str == 'in_progress' || (str.contains('in') && str.contains('progress'))) return 'IN_PROGRESS';
          if (str == 'resolved' || str == 'completed') return 'RESOLVED';
          return 'PENDING';
        }
        if (mounted) {
          setState(() {
            _totalComplaints = complaints.length;
            _resolvedComplaints = complaints.where((c) => normalize(c['status']) == 'RESOLVED').length;
            _pendingComplaints = complaints.where((c) => normalize(c['status']) == 'PENDING').length;
            _inProgressComplaints = complaints.where((c) => normalize(c['status']) == 'IN_PROGRESS').length;
            final Map<String, int> areaComplaints = {};
            for (var c in complaints) {
              if (normalize(c['status']) == 'PENDING' && c['purok'] != null) {
                final area = c['purok'].toString();
                areaComplaints[area] = (areaComplaints[area] ?? 0) + 1;
              }
            }
            _activeHotspots = areaComplaints.values.where((count) => count > 3).length;
          });
        }
      }
    } catch (e) { debugPrint("Error fetching complaints: $e"); }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isMobile = constraints.maxWidth < 600;
        bool isTablet = constraints.maxWidth >= 600 && constraints.maxWidth < 1024;
        bool isDesktop = constraints.maxWidth >= 1024;

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: const Color(0xFFF8F9FA),
          extendBody: true,
          drawer: (isMobile || isTablet) ? _buildMobileDrawer() : null,
          body: Row(
            children: [
              if (isDesktop) _buildSidebar(),
              Expanded(
                child: IndexedStack(
                  index: _selectedIndex,
                  children: [
                    _buildMainDashboard(isMobile, isTablet),
                    TrackTrucksScreen(isEmbedded: true, onBack: () { _refreshAllStats(); if (mounted) setState(() => _selectedIndex = 0); }),
                    AnalyticsScreen(isEmbedded: true, onBack: () { _refreshAllStats(); if (mounted) setState(() => _selectedIndex = 0); }, onNavigate: (index) => setState(() => _selectedIndex = index)),
                    ComplaintsScreen(isEmbedded: true, onBack: () { _refreshAllStats(); if (mounted) setState(() => _selectedIndex = 0); }),
                    UserManagementScreen(isEmbedded: true, onBack: () { _refreshAllStats(); if (mounted) setState(() => _selectedIndex = 0); }),
                    DataManagementScreen(isEmbedded: true, onBack: () { _refreshAllStats(); if (mounted) setState(() => _selectedIndex = 0); }),
                    AdminSettingsScreen(isEmbedded: true, onBack: () { _refreshAllStats(); if (mounted) setState(() => _selectedIndex = 0); }),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: (isMobile || isTablet) ? _buildBottomNav() : null,
        );
      },
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
          Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(24, 60, 24, 40),
                child: Column(
                  children: [
                    Hero(
                      tag: 'admin_sidebar_logo',
                      child: Container(
                        width: 76, height: 76,
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
                        child: const Icon(Icons.admin_panel_settings_rounded, size: 36, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      AppLocalizations.get('garbage_tracker').toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Color(0xFF00695C), letterSpacing: -0.5),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00695C).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        "ADMINISTRATOR",
                        style: TextStyle(fontSize: 9, color: Color(0xFF00695C), fontWeight: FontWeight.w900, letterSpacing: 1.2),
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
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      _buildSidebarItem(Icons.dashboard_rounded, "Dashboard Overview", 0),
                      const SizedBox(height: 8),
                      _buildSidebarItem(Icons.map_rounded, "Fleet GIS Tracking", 1),
                      const SizedBox(height: 8),
                      _buildSidebarItem(Icons.analytics_rounded, "System Analytics", 2),
                      const SizedBox(height: 8),
                      _buildSidebarItem(Icons.chat_bubble_rounded, "Incident Reports", 3),
                      const SizedBox(height: 8),
                      _buildSidebarItem(Icons.people_outline_rounded, "User Management", 4),
                      const SizedBox(height: 8),
                      _buildSidebarItem(Icons.storage_rounded, "Database Center", 5),
                      const SizedBox(height: 8),
                      _buildSidebarItem(Icons.settings_suggest_rounded, "System Settings", 6),
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
                        const SizedBox(width: 12),
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
    return Positioned(
      top: top, left: left, bottom: bottom, right: right,
      child: Transform.translate(
        offset: offset,
        child: Transform.scale(
          scale: scale,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarItem(IconData icon, String label, int index) {
    final bool isSelected = _selectedIndex == index;
    return _HoverZoomCard(
      onTap: () {
        if (index == 0) _refreshAllStats();
        setState(() => _selectedIndex = index);
      },
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
              color: isSelected ? const Color(0xFF00796B) : Colors.grey.shade600,
              size: 20
            ),
            if (_isSidebarExtended) ...[
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? const Color(0xFF00796B) : Colors.grey.shade700,
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            if (isSelected && _isSidebarExtended)
              Container(
                width: 4, height: 16,
                decoration: BoxDecoration(color: const Color(0xFF00796B), borderRadius: BorderRadius.circular(2)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileDrawer() {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double drawerWidth = (screenWidth * 0.8).clamp(280.0, 320.0);

    return Drawer(
      width: drawerWidth,
      backgroundColor: Colors.white,
      child: Stack(
        children: [
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
                    top: -30,
                    left: -30,
                    scale: 0.9 + math.sin(_circleController.value * math.pi) * 0.1
                  ),
                  _buildSidebarCircle(
                    size: 180,
                    color: const Color(0xFF4DB6AC).withAlpha(15),
                    offset: Offset(math.cos(_circleController.value * 2 * math.pi) * 15, math.sin(_circleController.value * 2 * math.pi) * 10),
                    bottom: -40,
                    right: -40,
                    scale: 0.95 + math.cos(_circleController.value * math.pi) * 0.05
                  ),
                ],
              );
            },
          ),
          SafeArea(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 40, 24, 30),
                  child: Column(
                    children: [
                      Hero(
                        tag: 'admin_drawer_logo',
                        child: Container(
                          width: 76, height: 76,
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
                          child: const Icon(Icons.admin_panel_settings_rounded, size: 36, color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        AppLocalizations.get('garbage_tracker').toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19, color: Color(0xFF1A1A1A), letterSpacing: -0.5),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00695C).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          "SYSTEM ADMINISTRATOR",
                          style: TextStyle(fontSize: 9, color: Color(0xFF00695C), fontWeight: FontWeight.w900, letterSpacing: 1.1),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(indent: 32, endIndent: 32, height: 1),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      _buildDrawerItem(Icons.chat_bubble_rounded, "Incident Reports", 3),
                      _buildDrawerItem(Icons.people_outline_rounded, "User Accounts", 4),
                      _buildDrawerItem(Icons.storage_rounded, "Data Management", 5),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: _HoverZoomCard(
                    onTap: () {
                      Navigator.pop(context);
                      _showLogoutDialog(context);
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.red.shade400, Colors.red.shade700],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: Colors.red.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.power_settings_new_rounded, color: Colors.white, size: 20),
                          const SizedBox(width: 12),
                          const Text("LOGOUT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1)),
                        ],
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

  Widget _buildDrawerItem(IconData icon, String label, int index) {
    bool isSelected = _selectedIndex == index;
    return ListTile(
      onTap: () {
        Navigator.pop(context);
        if (index == 0) _refreshAllStats();
        setState(() => _selectedIndex = index);
      },
      leading: Icon(icon, color: isSelected ? const Color(0xFF00695C) : Colors.grey.shade600, size: 22),
      title: Text(
        label,
        style: TextStyle(
          color: isSelected ? const Color(0xFF00695C) : Colors.grey.shade700,
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
        ),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      selected: isSelected,
      selectedTileColor: const Color(0xFF00695C).withOpacity(0.08),
    );
  }

  Widget _buildMainDashboard(bool isMobile, bool isTablet) {
    if (isMobile || isTablet) {
      return LayoutBuilder(builder: (context, constraints) {
        return Scaffold(
          backgroundColor: const Color(0xFFF8F9FA),
          body: Stack(
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: (ScrollNotification scroll) {
                  // Detect user release by checking for ScrollUpdate with no drag details
                  // or the end of the scroll activity.
                  bool isRelease = (scroll is ScrollUpdateNotification && scroll.dragDetails == null) || 
                                  (scroll is ScrollEndNotification);

                  if (isRelease && !_isRefreshing) {
                    if (_scrollController.hasClients && _scrollController.offset < -70) {
                      _refreshAllStats(manual: true);
                    }
                  }
                  return false;
                },
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  child: AnimatedBuilder(
                    animation: _scrollController,
                    builder: (context, child) {
                      final double offset = _scrollController.hasClients ? _scrollController.offset : 0;
                      // Counter the pull-down bounce so header/content stay fixed visually during pull
                      // We use offset directly (which is negative during pull) to move content up
                      return Transform.translate(
                        offset: Offset(0, offset < 0 ? offset : 0),
                        child: Column(
                          children: [
                            _buildHeader(constraints.maxWidth),
                            Center(
                              child: Container(
                                constraints: const BoxConstraints(maxWidth: 1200),
                                padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 6),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("Overview",
                                            style: TextStyle(
                                                fontSize: isMobile ? 22 : 26,
                                                fontWeight: FontWeight.w900,
                                                color: const Color(0xFF1A1A1A),
                                                letterSpacing: -0.5)),
                                        Text("System-wide Activity",
                                            style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.grey.shade600)),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    _buildStatGrid(isMobile, isTablet),
                                    const SizedBox(height: 16),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("Fleet GIS",
                                            style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w900,
                                                color: const Color(0xFF1A1A1A))),
                                        Text("Real-time truck locations and status",
                                            style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.grey.shade600)),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    _buildMapWidget(true),
                                    const SizedBox(height: 16),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 4),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text("Quick Stats",
                                              style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w900,
                                                  color: Color(0xFF1A1A1A))),
                                          Text("System performance overview",
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.grey.shade600)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    _buildSummarySection(),
                                    const SizedBox(height: 12),
                                    _buildFleetSection(),
                                    const SizedBox(height: 16),
                                    _buildActivityLogSection(),
                                    const SizedBox(height: 12),
                                    _buildAdminActionsGrid(true),
                                    const SizedBox(height: 120),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              // Custom Pull-to-Refresh Spinner (Sticky while refreshing)
              AnimatedBuilder(
                animation: Listenable.merge([_scrollController, _refreshRotationController]),
                builder: (context, child) {
                  final double offset = _scrollController.hasClients ? _scrollController.offset : 0;
                  
                  // Logic to show spinner: 
                  // 1. If actively pulling down (offset < 0)
                  // 2. If currently performing a manual refresh or retreating (_showRefreshSpinner)
                  bool shouldShow = (offset < 0) || _showRefreshSpinner;
                  
                  if (!shouldShow) {
                    return const SizedBox.shrink();
                  }

                  final double pullDistance = offset.abs();
                  
                  // If refreshing, stick at 80. 
                  // If just pulling or retreating, follow the pull logic (up to 80 or back to -40).
                  final double targetTop = (_isRefreshing && _showRefreshSpinner)
                      ? 80.0 
                      : (-40 + pullDistance).clamp(-40.0, 80.0);
                  
                  final double opacity = (_isRefreshing && _showRefreshSpinner)
                      ? 1.0 
                      : (pullDistance / 60).clamp(0.0, 1.0);

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
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Transform.rotate(
                            // Interactive rotation: rotates as you pull (clockwise) or push back (counter-clockwise)
                            angle: (_isRefreshing && _showRefreshSpinner)
                                ? 0 
                                : (pullDistance / 80) * 2 * math.pi,
                            child: RotationTransition(
                              turns: _refreshRotationController,
                              child: const Icon(
                                Icons.refresh_rounded,
                                color: Color(0xFF00796B),
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      });
    }

    return Column(
      children: [
        _buildWebHeader(),
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: EdgeInsets.zero,
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            child: Center(
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  _buildWebBanner(),
                  const SizedBox(height: 32),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      const SizedBox(height: 10),
                      _buildStatGrid(isMobile, isTablet),
                      const SizedBox(height: 16),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                            flex: 2,
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Fleet GIS",
                                      style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFF1A1A1A))),
                                  Text("Real-time truck locations and status",
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey.shade600)),
                                  const SizedBox(height: 12),
                                  _buildMapWidget(false),
                                  const SizedBox(height: 20),
                                  _buildAdminActionsGrid(false)
                                ])),
                        const SizedBox(width: 20),
                        Expanded(
                            flex: 1,
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Quick Stats",
                                      style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFF1A1A1A))),
                                  Text("System performance overview",
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey.shade600)),
                                  const SizedBox(height: 12),
                                  _buildSummarySection(),
                                  const SizedBox(height: 20),
                                  _buildActivityLogSection(),
                                  const SizedBox(height: 20),
                                  _buildFleetSection()
                                  ])),
                        ]),
                        const SizedBox(height: 110),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }


  Widget _buildHeader(double width) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double screenWidth = MediaQuery.of(context).size.width;
    bool isMobile = width < 600;
    double bgHeight = isMobile ? (screenHeight * 0.22).clamp(180, 220) : 220;

    final double welcomeFontSize = (screenWidth * 0.035).clamp(11.0, 14.0);
    final double nameFontSize = (screenWidth * 0.05).clamp(16.0, 20.0);

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
                      Row(
                        children: [
                          _HoverZoomCard(
                            onTap: () => _scaffoldKey.currentState?.openDrawer(),
                            scale: 1.1,
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.menu_rounded, color: Colors.white, size: 24),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _HoverZoomCard(
                            scale: 1.05,
                            child: Container(
                              height: 48,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Center(
                                child: Text(
                                  _currentTime,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: (screenWidth * 0.035).clamp(12.0, 14.0),
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'monospace',
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
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
          padding: EdgeInsets.only(top: bgHeight - 60, left: 16, right: 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
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
                    // Restored Profile Picture Container
                    GestureDetector(
                      onTap: _viewProfilePicture,
                      child: Hero(
                        tag: 'admin_profile_pic_header',
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
                                    (_user?.name != null && _user!.name.isNotEmpty) ? _user!.name[0].toUpperCase() : "A",
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
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text("Administrator", style: TextStyle(color: Colors.grey.shade600, fontSize: welcomeFontSize, fontWeight: FontWeight.w600)),
                          Text(
                            _user?.name ?? "System Admin",
                            style: TextStyle(color: const Color(0xFF1A1A1A), fontSize: nameFontSize, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Plain Edit Text Button on the right
                    TextButton(
                      onPressed: () => _showDataManagementModal(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        overlayColor: Colors.transparent,
                      ),
                      child: const Text(
                        "Edit", 
                        style: TextStyle(
                          color: Color(0xFF00695C), 
                          fontWeight: FontWeight.w900, 
                          fontSize: 14,
                        )
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                HoverActionButton(
                  text: "Track Fleet GIS",
                  onTap: () => setState(() => _selectedIndex = 1),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderActionIcon(IconData icon, {int? badgeCount, VoidCallback? onTap}) {
    return _HoverZoomCard(
      onTap: onTap,
      scale: 1.1,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          if (badgeCount != null)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(
                  color: Color(0xFFFF5252),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  "$badgeCount",
                  style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWebHeader() {
    final String? profileUrl = (_user?.profilePicture != null && _user!.profilePicture!.isNotEmpty) ? _user!.profilePicture : null;
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
                      boxShadow: AppTheme.balancedPulidongShadow,
                      border: Border.all(color: const Color(0xFF00796B), width: 2.5),
                      image: profileUrl != null
                          ? DecorationImage(image: NetworkImage(profileUrl), fit: BoxFit.cover)
                          : null,
                    ),
                    child: profileUrl == null
                        ? Center(child: Text((_user?.name ?? "A")[0].toUpperCase(), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF00796B))))
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
                        _user?.name ?? "Administrator",
                        style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1),
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
              _buildWebHeaderActionIcon(Icons.notifications_outlined, badgeCount: _unreadNotificationsCount > 0 ? _unreadNotificationsCount : null, onTap: () => _showNotificationsModal(context)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWebHeaderActionIcon(IconData icon, {int? badgeCount, VoidCallback? onTap}) {
    return _HoverZoomCard(
      onTap: onTap,
      scale: 1.1,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF00796B).withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF00796B).withOpacity(0.1)),
          ),
          child: const Icon(Icons.notifications_outlined, color: Color(0xFF00796B), size: 24),
        ),
        if (badgeCount != null)
          Positioned(
            right: -2, top: -2,
            child: Container(padding: const EdgeInsets.all(5), decoration: const BoxDecoration(color: Color(0xFFFF4081), shape: BoxShape.circle), child: Text("$badgeCount", style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900))),
          ),
      ]),
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
                  child: const Icon(Icons.dashboard_customize_rounded, color: Colors.white, size: 32),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Administrative Overview & System Impact",
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Monitor real-time fleet activity, manage users, and analyze system-wide collection performance.",
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

  void _showDataManagementModal(BuildContext context) {
    if (_user == null) return;
    bool isModalLoading = true;
    _showStyledBottomSheet(
      context: context,
      title: "Edit Account",
      description: "Update your administrative contact details and credentials.",
      maxHeightMultiplier: 0.9,
      children: [
        StatefulBuilder(builder: (ctx, setModalState) {
          if (isModalLoading) {
            Future.delayed(const Duration(milliseconds: 800), () {
              if (mounted) setModalState(() => isModalLoading = false);
            });
            return const Center(child: Padding(padding: EdgeInsets.all(60), child: CircularProgressIndicator(color: AppColors.tealText)));
          }
          return DataManagementModal(user: _user!, onSuccess: _loadUser);
        }),
      ],
    );
  }

  void _showStyledBottomSheet({required BuildContext context, required String title, required List<Widget> children, String? description, double maxHeightMultiplier = 0.6}) {
    final bool isDesktop = Responsive.isDesktop(context);
    
    if (isDesktop) {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 550, maxHeight: 600),
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
                  Flexible(child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: children))),
                ],
              ),
            ),
          ),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        clipBehavior: Clip.antiAlias,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * maxHeightMultiplier),
        padding: EdgeInsets.fromLTRB(0, 12, 0, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom),
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
                crossAxisAlignment: CrossAxisAlignment.center,
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
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: SingleChildScrollView(
                  clipBehavior: Clip.antiAlias, 
                  padding: const EdgeInsets.only(bottom: 40), 
                  child: Column(mainAxisSize: MainAxisSize.min, children: children)
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _viewProfilePicture() {
    if (_user == null) return;
    final String profileUrl = (_user!.profilePicture != null && _user!.profilePicture!.isNotEmpty) ? _user!.profilePicture! : "";
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
                GestureDetector(onTap: () => Navigator.pop(context), child: Container(color: Colors.transparent)),
                Center(
                  child: Hero(
                    tag: 'admin_profile_pic_header',
                    child: Container(
                      width: 300, height: 300,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                        image: profileUrl.isNotEmpty ? DecorationImage(image: NetworkImage(profileUrl), fit: BoxFit.cover) : null,
                      ),
                      child: profileUrl.isEmpty
                          ? Center(child: Text(_user!.name.isNotEmpty ? _user!.name[0].toUpperCase() : "A", style: const TextStyle(fontSize: 80, fontWeight: FontWeight.bold, color: Colors.white)))
                          : null,
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white, size: 32), onPressed: () => Navigator.pop(context)),
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

  Widget _buildStatGrid(bool isMobile, bool isTablet) {
    return GridView.count(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: (isMobile || isTablet) ? 2 : 4,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: (isMobile || isTablet) ? 1.0 : 1.35,
      children: [
        _buildModernStatCard("Active Trucks", "$_activeTrucks",
            Icons.local_shipping_rounded, const Color(0xFF43A047)),
        _buildModernStatCard("Pending Issues", "$_pendingComplaints",
            Icons.warning_amber_rounded, const Color(0xFFE53935)),
        _buildModernStatCard("Route Coverage", "${_coveragePercent.toInt()}%",
            Icons.map_rounded, const Color(0xFFFB8C00)),
        _buildModernStatCard("Total Residents", "$_residentsCount",
            Icons.people_alt_rounded, const Color(0xFF8E24AA)),
      ],
    );
  }

  Widget _buildModernStatCard(String title, String value, IconData icon,
      Color color, {String? badge}) {
    final bool isDesktop = Responsive.isDesktop(context);
    final double cardPadding = isDesktop ? 20.0 : 16.0;
    final Color bgColor = color.withOpacity(0.02);
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
                    color: color.withOpacity(0.05), shape: BoxShape.circle)),
          ),
          Positioned(
            bottom: -15,
            right: -10,
            child: Icon(icon, size: 80, color: color.withOpacity(0.05)),
          ),
          if (badge != null)
            Positioned(
              top: cardPadding,
              right: cardPadding,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withAlpha(40),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withAlpha(60), width: 1),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.w900, fontSize: 13),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.all(cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: bgColor, borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: color, size: 24),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    alignment: Alignment.centerLeft,
                    fit: BoxFit.scaleDown,
                    child: Text(value,
                        style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1A1A1A))),
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(title,
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapWidget(bool isMobile) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: AppTheme.balancedPulidongShadow,
          border: Border.all(color: Colors.white, width: 2)),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                            color: Color(0xFF00C853), shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: FittedBox(
                        alignment: Alignment.centerLeft,
                        fit: BoxFit.scaleDown,
                        child: Text("Live Fleet Monitoring",
                            style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF1A1A1A),
                                fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _HoverZoomLink(
                onTap: () => setState(() => _selectedIndex = 1),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                      color: const Color(0xFFE0F2F1),
                      borderRadius: BorderRadius.circular(12)),
                  child: const Text("Full Map",
                      style: TextStyle(
                          color: Color(0xFF00796B),
                          fontWeight: FontWeight.w900,
                          fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
        Container(
            height: isMobile ? 220 : 400,
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: const Color(0xFFF8F9FA),
                border: Border.all(color: Colors.grey.shade200)),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: MapboxView(
                    mode: 'dashboard',
                    onTap: () => setState(() => _selectedIndex = 1)))),
        Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _buildModernLegendItem(const Color(0xFF00C853), "Active"),
              const SizedBox(width: 16),
              _buildModernLegendItem(const Color(0xFFFFAB00), "Idle"),
              const SizedBox(width: 16),
              _buildModernLegendItem(const Color(0xFF9E9E9E), "Offline")
            ])),
      ]),
    );
  }

  Widget _buildModernLegendItem(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))), const SizedBox(width: 8), Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey.shade700))]);
  }

  Widget _buildActivityLogSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(32), 
        boxShadow: AppTheme.balancedPulidongShadow,
        border: Border.all(color: Colors.white, width: 2)
      ),
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("Recent Activity", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
        const SizedBox(height: 20),
        if (_recentLogs.isEmpty) const Center(child: Text("No recent activity logs", style: TextStyle(color: Colors.grey, fontSize: 13)))
        else ...[
          Column(children: _recentLogs.take(2).map((log) => _buildRecentActivityItem(log)).toList()),
          if (_recentLogs.length > 2)
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => _showAllActivityLogs(),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF00796B),
                  overlayColor: Colors.transparent,
                ),
                child: const Text("VIEW ALL ACTIVITY", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.1, fontSize: 12))
              ),
            ),
        ],
      ]),
    );
  }

  void _showAllActivityLogs() {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    bool isModalLoading = true;

    Widget modalContent(StateSetter setModalState) {
      if (isModalLoading) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) setModalState(() => isModalLoading = false);
        });
      }

      return Container(
        padding: EdgeInsets.fromLTRB(24, isMobile ? 12 : 24, 24, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: isMobile ? const BorderRadius.vertical(top: Radius.circular(32)) : BorderRadius.circular(32),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMobile) 
              Center(
                child: Container(
                  width: 40, 
                  height: 4, 
                  margin: const EdgeInsets.only(bottom: 20), 
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))
                )
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("System Activity Log", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF00796B))),
                      SizedBox(height: 4),
                      Text("Complete history of system events and actions.", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 20),
            if (isModalLoading)
              const Padding(
                padding: EdgeInsets.all(60),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppColors.tealText),
                      SizedBox(height: 16),
                      Text(
                        "Loading system logs...",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 32),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _recentLogs.length,
                    separatorBuilder: (context, i) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final log = _recentLogs[index];
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200, width: 1.2),
                        ),
                        child: _buildRecentActivityItemRow(log),
                      );
                    },
                  ),
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
          builder: (context, setModalState) => Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
            child: modalContent(setModalState),
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: StatefulBuilder(
              builder: (context, setModalState) => modalContent(setModalState),
            ),
          ),
        ),
      );
    }
  }

  Widget _buildRecentActivityItemRow(Map<dynamic, dynamic> log) {
    final String type = (log['type'] ?? 'OTHER').toString().toUpperCase();
    final String message = (log['message'] ?? "System Event").toString();
    final String date = (log['date'] ?? "Just now").toString();
    IconData icon = Icons.info_outline_rounded; Color color = Colors.grey;
    switch (type) {
      case 'LOGIN': icon = Icons.login_rounded; color = const Color(0xFF4CAF50); break;
      case 'LOGOUT': icon = Icons.logout_rounded; color = const Color(0xFFF44336); break;
      case 'EXPORT': icon = Icons.download_rounded; color = const Color(0xFF2196F3); break;
      case 'UPDATE': icon = Icons.settings_rounded; color = const Color(0xFFFF9800); break;
    }
    return Row(children: [
      Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withAlpha(20), shape: BoxShape.circle), child: Icon(icon, color: color, size: 14)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(message, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF2C3E50)), maxLines: 1, overflow: TextOverflow.ellipsis), Text(date, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500))])),
    ]);
  }

  Widget _buildRecentActivityItem(Map<dynamic, dynamic> log) {
    final String type = (log['type'] ?? 'OTHER').toString().toUpperCase();
    final String message = (log['message'] ?? "System Event").toString();
    final String date = (log['date'] ?? "Just now").toString();
    IconData icon = Icons.info_outline_rounded; Color color = Colors.grey;
    switch (type) {
      case 'LOGIN': icon = Icons.login_rounded; color = const Color(0xFF4CAF50); break;
      case 'LOGOUT': icon = Icons.logout_rounded; color = const Color(0xFFF44336); break;
      case 'EXPORT': icon = Icons.download_rounded; color = const Color(0xFF2196F3); break;
      case 'UPDATE': icon = Icons.settings_rounded; color = const Color(0xFFFF9800); break;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withAlpha(20), shape: BoxShape.circle), child: Icon(icon, color: color, size: 14)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(message, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF2C3E50)), maxLines: 1, overflow: TextOverflow.ellipsis), Text(date, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500))])),
      ]),
    );
  }

  Widget _buildFleetSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(32), 
        boxShadow: AppTheme.balancedPulidongShadow,
        border: Border.all(color: Colors.white, width: 2)
      ),
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("Fleet Overview", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
        const SizedBox(height: 20),
        if (_fleetStatus.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: Text("No active fleet data", style: TextStyle(color: Colors.grey))))
        else ...[
          Column(children: _fleetStatus.where((t) => t['isOnline'] == true).take(2).map((truck) => _buildModernFleetItem(truck)).toList()),
          const SizedBox(height: 12),
          if (_fleetStatus.where((t) => t['isOnline'] == true).length > 2)
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => _showAllFleetStatus(),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF00796B),
                  overlayColor: Colors.transparent,
                ),
                child: const Text("VIEW ALL FLEET STATUS", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.1, fontSize: 12))
              ),
            ),
        ],
      ]),
    );
  }

  void _showAllFleetStatus() {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    bool isModalLoading = true;

    Widget modalContent(StateSetter setModalState) {
      if (isModalLoading) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) setModalState(() => isModalLoading = false);
        });
      }

      final List<Map<dynamic, dynamic>> onlineTrucks = _fleetStatus.where((t) => t['isOnline'] == true).toList();
      
      return Container(
        padding: EdgeInsets.fromLTRB(24, isMobile ? 12 : 24, 24, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: isMobile ? const BorderRadius.vertical(top: Radius.circular(32)) : BorderRadius.circular(32),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMobile) 
              Center(
                child: Container(
                  width: 40, 
                  height: 4, 
                  margin: const EdgeInsets.only(bottom: 20), 
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))
                )
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Full Fleet Status", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF00796B))),
                      SizedBox(height: 4),
                      Text("Real-time detailed telemetry for all online units.", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 20),
            if (isModalLoading)
              const Padding(
                padding: EdgeInsets.all(60),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppColors.tealText),
                      SizedBox(height: 16),
                      Text(
                        "Loading fleet status...",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 32),
                  child: onlineTrucks.isEmpty 
                      ? const Padding(padding: EdgeInsets.all(40), child: Center(child: Text("No trucks are currently online.")))
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: onlineTrucks.length,
                          separatorBuilder: (context, i) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final truck = onlineTrucks[index];
                            return _buildModernFleetItem(truck);
                          },
                        ),
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
          builder: (context, setModalState) => Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
            child: modalContent(setModalState),
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: StatefulBuilder(
              builder: (context, setModalState) => modalContent(setModalState),
            ),
          ),
        ),
      );
    }
  }

  Widget _buildModernFleetItem(Map<dynamic, dynamic> truck) {
    final String id = (truck['truck_id'] ?? truck['internal_id'] ?? "Unknown").toString();
    final String status = (truck['status'] ?? "Idle").toString().toUpperCase();
    final Color statusColor = status == 'ACTIVE' ? const Color(0xFF4CAF50) : const Color(0xFFFFAB00);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: statusColor.withAlpha(20), borderRadius: BorderRadius.circular(10)), child: Icon(Icons.local_shipping_rounded, color: statusColor, size: 20)),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(id, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF1A1A1A))), Text(status, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w800))])),
        const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 16),
      ]),
    );
  }

  Widget _buildSummarySection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(32), 
        boxShadow: AppTheme.balancedPulidongShadow,
        border: Border.all(color: Colors.white, width: 2)
      ),
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [Icon(Icons.insights_rounded, color: Color(0xFF009688), size: 24), SizedBox(width: 12), Text("Performance", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)))]),
        const SizedBox(height: 24),
        _buildModernSummaryRow("Collection Progress", "$_completedRoutesToday / $_totalRoutesToday", _totalRoutesToday > 0 ? _completedRoutesToday / _totalRoutesToday : 0.0, const Color(0xFF1E88E5)),
        const SizedBox(height: 20),
        _buildModernSummaryRow("Complaint Resolution", "$_resolvedComplaints / $_totalComplaints", _totalComplaints > 0 ? _resolvedComplaints / _totalComplaints : 0.0, const Color(0xFF4CAF50)),
        const SizedBox(height: 24), const Divider(), const SizedBox(height: 12),
        _buildModernInfoRow("Average Speed", "${_averageSpeed.toStringAsFixed(1)} km/h"),
        const SizedBox(height: 12), _buildModernInfoRow("Active Hotspots", "$_activeHotspots Areas"),
      ]),
    );
  }

  Widget _buildModernSummaryRow(String label, String value, double progress, Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w700)), Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13))]),
      const SizedBox(height: 10),
      ClipRRect(borderRadius: BorderRadius.circular(10), child: LinearProgressIndicator(value: progress, backgroundColor: Colors.grey.shade100, valueColor: AlwaysStoppedAnimation<Color>(color), minHeight: 8)),
    ]);
  }

  Widget _buildModernInfoRow(String label, String value) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w700)), Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14))]);
  }

  Widget _buildAdminActionsGrid(bool isMobile) {
    if (isMobile) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Quick Actions",
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1A1A1A))),
                Text("Manage system components and data",
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600)),
              ],
            )),
        _buildModernActionCard("Analytics", "View system performance",
            Icons.bar_chart_rounded, const Color(0xFF1E88E5),
            onTap: () => setState(() => _selectedIndex = 2)),
        const SizedBox(height: 10),
        _buildModernActionCard("Users", "Manage account access",
            Icons.people_outline_rounded, const Color(0xFF8E24AA),
            onTap: () => setState(() => _selectedIndex = 4)),
        const SizedBox(height: 12),
        _buildModernActionCard("Database Center", "System record management",
            Icons.storage_rounded, const Color(0xFF009688),
            onTap: () => setState(() => _selectedIndex = 5)),
        const SizedBox(height: 12),
        _buildModernActionCard("Incidents", "Review resident reports",
            Icons.chat_bubble_rounded, const Color(0xFFE53935),
            onTap: () => setState(() => _selectedIndex = 3)),
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Quick Actions",
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1A1A1A))),
              Text("Manage system components and data",
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600)),
            ],
          )),
      GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 12,
        childAspectRatio: 2.8,
        children: [
          _buildModernActionCard("Analytics", "View system performance",
              Icons.bar_chart_rounded, const Color(0xFF1E88E5),
              onTap: () => setState(() => _selectedIndex = 2)),
          _buildModernActionCard("Users", "Manage account access",
              Icons.people_outline_rounded, const Color(0xFF8E24AA),
              onTap: () => setState(() => _selectedIndex = 4)),
          _buildModernActionCard("Database Center", "System record management",
              Icons.storage_rounded, const Color(0xFF009688),
              onTap: () => setState(() => _selectedIndex = 5)),
          _buildModernActionCard("Incidents", "Review resident reports",
              Icons.chat_bubble_rounded, const Color(0xFFE53935),
              onTap: () => setState(() => _selectedIndex = 3)),
        ],
      ),
    ]);
  }

  Widget _buildModernActionCard(String title, String subtitle, IconData icon,
      Color color, {VoidCallback? onTap}) {
    bool isDesktop = Responsive.isDesktop(context);
    return _HoverZoomCard(
      onTap: onTap,
      child: Container(
        margin: isDesktop ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 2),
        padding: isDesktop ? const EdgeInsets.symmetric(horizontal: 24, vertical: 12) : const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(isDesktop ? 24 : 24),
          boxShadow: AppTheme.pulidongShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        color: Color(0xFF1A1A1A)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: Color(0xFFE0E0E0), size: 16)
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderIconButton(IconData icon, {int? badgeCount, VoidCallback? onTap, bool isInAppBar = false}) {
    return GestureDetector(onTap: onTap, child: Stack(clipBehavior: Clip.none, children: [
      Container(
        width: 44, height: 44, 
        decoration: BoxDecoration(
          color: isInAppBar ? Colors.white : Colors.white.withAlpha(180), 
          borderRadius: BorderRadius.circular(12), 
          boxShadow: AppTheme.balancedPulidongShadow,
          border: Border.all(color: Colors.grey.shade200)
        ), 
        child: Icon(icon, color: const Color(0xFF1A1A1A), size: 22)
      ),
      if (badgeCount != null) Positioned(right: -4, top: -4, child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Color(0xFFFF1744), shape: BoxShape.circle), child: Text("$badgeCount", style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)))),
    ]));
  }

  Widget _buildBottomNav() {
    final double bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      margin: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding > 0 ? bottomPadding : 12),
      height: 68,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(34),
        boxShadow: AppTheme.highIntensityBalancedShadow,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(0, Icons.home_rounded, 'Home'),
          _buildNavItem(1, Icons.location_on_rounded, 'Track'),
          _buildNavItem(2, Icons.analytics_rounded, 'Analytics'),
          _buildNavItem(6, Icons.settings_suggest_rounded, 'Settings'),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    bool isSelected = _selectedIndex == index;
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isSmall = screenWidth < 380;
    
    final double labelFontSize = (screenWidth * 0.035).clamp(11.0, 14.0);
    final double iconSize = (screenWidth * 0.065).clamp(22.0, 26.0);

    return _HoverZoomLink(
      onTap: () {
        if (index == 0) _refreshAllStats();
        setState(() => _selectedIndex = index);
      },
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          padding: EdgeInsets.symmetric(
            horizontal: isSelected ? (isSmall ? 8 : 16) : 8, 
            vertical: 8
          ),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF00796B).withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: isSelected ? const Color(0xFF00796B) : Colors.grey.shade400, size: iconSize),
              if (isSelected) ...[
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: const Color(0xFF00796B),
                    fontWeight: FontWeight.w900,
                    fontSize: labelFontSize,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showNotificationsModal(BuildContext context) {
    // Clear badge immediately when modal opens
    _markAllAdminNotificationsAsRead();
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    bool isModalLoading = true;

    Widget modalContent(StateSetter setModalState) {
      if (isModalLoading) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) setModalState(() => isModalLoading = false);
        });
      }

      List<Map> notifications = [];

      return Container(
        padding: EdgeInsets.fromLTRB(24, isMobile ? 12 : 24, 24, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: isMobile ? const BorderRadius.vertical(top: Radius.circular(32)) : BorderRadius.circular(32),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMobile) 
              Center(
                child: Container(
                  width: 40, 
                  height: 4, 
                  margin: const EdgeInsets.only(bottom: 20), 
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))
                )
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Notifications", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF00695C))),
                      SizedBox(height: 4),
                      Text("Stay updated with system events and alerts.", style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 20),
            if (isModalLoading)
              const Padding(
                padding: EdgeInsets.all(60),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppColors.tealText),
                      SizedBox(height: 16),
                      Text(
                        "Loading notifications...",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Flexible(
                child: StreamBuilder<DatabaseEvent>(
                  stream: _database.ref('notifications').onValue,
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data!.snapshot.exists) {
                      final Map data = snapshot.data!.snapshot.value as Map;
                      List<Map> newList = [];
                      data.forEach((k, v) {
                        final val = v as Map;
                        if (_isNotificationForMe(val)) {
                          newList.add({...val, 'id': k});
                        }
                      });

                      newList.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
                      notifications = newList;

                      if (notifications.isEmpty) return _buildEmptyState();

                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 32),
                        itemCount: notifications.length,
                        separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF5F5F5)),
                        itemBuilder: (context, index) {
                          final notification = notifications[index];
                          return _buildNotificationItem(notification, const AlwaysStoppedAnimation(1.0));
                        },
                      );
                    }
                    return _buildEmptyState();
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
          builder: (context, setModalState) => Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
            child: modalContent(setModalState),
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: StatefulBuilder(
              builder: (context, setModalState) => modalContent(setModalState),
            ),
          ),
        ),
      );
    }
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

  Widget _buildDismissibleNotification(Map item, int index, GlobalKey<AnimatedListState> listKey, StateSetter setModalState, {bool isSelectionMode = false, bool isSelected = false, VoidCallback? onTap, VoidCallback? onDoubleTap, VoidCallback? onLongPress}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Dismissible(
        key: Key(item['id'].toString()),
        direction: isSelectionMode ? DismissDirection.none : DismissDirection.horizontal,
        confirmDismiss: (direction) async {
          return await _showConfirmDialog(
            title: "Delete Alert?",
            message: "This notification will be permanently removed.",
            isDestructive: true,
          );
        },
        onDismissed: (direction) {
          final String key = item['id'].toString();
          _database.ref('notifications/$key').remove();
          _showSnackBar("Notification deleted successfully");
        },
        background: _buildSwipeBackground(Alignment.centerLeft),
        secondaryBackground: _buildSwipeBackground(Alignment.centerRight),
        child: _buildNotificationItem(item, const AlwaysStoppedAnimation(1.0), isSelectionMode: isSelectionMode, isSelected: isSelected, onTap: onTap, onDoubleTap: onDoubleTap, onLongPress: onLongPress),
      ),
    );
  }

  Widget _buildSwipeBackground(Alignment alignment) {
    return Container(
      margin: const EdgeInsets.only(bottom: 0, left: 10, right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(24)),
      alignment: alignment,
      child: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400),
    );
  }

  Widget _buildNotificationItem(Map item, Animation<double> animation, {bool isSelectionMode = false, bool isSelected = false, VoidCallback? onTap, VoidCallback? onDoubleTap, VoidCallback? onLongPress}) {
    final bool isRead = item['isRead'] ?? false;
    final String type = (item['type'] ?? '').toString();
    
    IconData icon = Icons.notifications_rounded;
    Color iconColor = const Color(0xFF00BFA5);
    
    if (type == 'DRIVER_ISSUE') {
      icon = Icons.error_rounded;
      iconColor = Colors.red;
    } else if (type == 'RESIDENT_COMPLAINT') {
      icon = Icons.warning_rounded;
      iconColor = Colors.orange;
    }

    return FadeTransition(
      opacity: animation,
      child: SizeTransition(
        sizeFactor: animation,
        child: _HoverZoomCard(
          onTap: onTap,
          child: GestureDetector(
            onDoubleTap: onDoubleTap,
            onLongPress: onLongPress,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFE0F2F1) : Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: isSelected ? const Color(0xFF00796B) : Colors.grey.shade100, width: isSelected ? 2 : 1),
                boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Stack(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    leading: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: isSelected ? const Color(0xFF00796B).withOpacity(0.1) : const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(16)),
                      child: Icon(icon, color: iconColor, size: 24),
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
                        color: Colors.green,
                        size: 22,
                      ),
                    ),
                  if (!isRead && !isSelectionMode)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showSnackBar(String message) {
    CustomNotification.showTopNotification(context, message, false);
  }

  Future<bool> _showConfirmDialog({required String title, required String message, bool isDestructive = false}) async {
    return await showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.fromLTRB(32, 40, 32, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.5)),
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
                        backgroundColor: isDestructive ? Colors.red : const Color(0xFF00796B),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("CONFIRM", style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ) ?? false;
  }

  void _markAllAdminNotificationsAsRead() async {
    try {
      final snap = await _database.ref('notifications').get();
      if (snap.exists && snap.value != null) {
        final Map data = snap.value as Map;
        final Map<String, dynamic> updates = {};
        data.forEach((k, v) {
          if (_isNotificationForMe(v as Map) && v['isRead'] == false) {
            updates['notifications/$k/isRead'] = true;
          }
        });
        if (updates.isNotEmpty) {
          await _database.ref().update(updates);
        }
      }
    } catch (e) {
      debugPrint("Error clearing notification badge: $e");
    }
  }

  void _showLogoutDialog(BuildContext context) {
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
              const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 48),
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
                        await SystemLogger.logEvent("LOGOUT", "Admin session ended");
                        NotificationService.stopListening();
                        await SessionManager.logout();
                        await RoutePersistenceManager.clearLastRoute();
                        if (mounted) {
                          CustomNotification.showTopNotification(context, "Logout successful", false);
                          Navigator.pushReplacementNamed(context, '/');
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("LOGOUT", style: TextStyle(fontWeight: FontWeight.w900)),
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
