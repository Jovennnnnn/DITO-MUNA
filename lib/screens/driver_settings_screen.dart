import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/app_theme.dart';
import '../utils/session_manager.dart';
import '../models/user.dart';
import '../api/api_service.dart';
import '../utils/custom_notification.dart';
import '../utils/app_localizations.dart';
import '../utils/responsive.dart';
import '../widgets/custom_snackbar.dart';
import '../widgets/data_management_modal.dart';
import '../widgets/legal_agreement_dialog.dart';
import '../widgets/hover_action_button.dart';
import '../widgets/fade_slide_entrance.dart';

class DriverSettingsScreen extends StatefulWidget {
  final bool isEmbedded;
  final VoidCallback? onBack;
  final String? currentSessionId;

  const DriverSettingsScreen({
    super.key, 
    this.isEmbedded = false, 
    this.onBack,
    this.currentSessionId,
  });

  @override
  State<DriverSettingsScreen> createState() => _DriverSettingsScreenState();
}

class _DriverSettingsScreenState extends State<DriverSettingsScreen> with TickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  UserData? _user;
  
  bool _isNavigating = false;
  bool _isLoading = false;
  StreamSubscription? _userSubscription;
  final ScrollController _scrollController = ScrollController();
  bool _showHeaderShadow = true;

  bool _isRefreshing = false;
  bool _showRefreshSpinner = false;
  double _manualPullDepth = 0.0;
  late AnimationController _refreshRotationController;

  // Settings values
  bool _dutyAlerts = true;
  bool _collectionNotifications = true;
  bool _maintenanceNotifications = true;
  bool _emergencyAlerts = true;
  
  // Device/App info
  String _gpsAccuracy = "Checking...";
  final String _appVersion = "1.0.0";
  String? _truckPlateNumber;
  StreamSubscription? _truckSubscription;

  // Controllers for edit profile
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();

  // Controllers for password change
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUser();
    _loadSettings();
    _startGpsMonitor();

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
    _userSubscription?.cancel();
    _truckSubscription?.cancel();
    _scrollController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _refreshRotationController.dispose();
    super.dispose();
  }

  Future<void> _refreshAllStats({bool manual = false}) async {
    if (_isRefreshing) return;
    
    if (mounted) {
      setState(() {
        _isRefreshing = true;
        _showRefreshSpinner = manual;
        _manualPullDepth = manual ? 80.0 : 0.0;
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
                        Text("Settings updated",
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
    _loadSettings();
    await Future.delayed(const Duration(milliseconds: 800));
  }

  void _loadUser() async {
    _user = await SessionManager.getUser();
    if (_user != null) {
      _nameController.text = _user!.name;
      _phoneController.text = _user!.phone ?? "";
      _emailController.text = _user!.email;
      _addressController.text = _user!.completeAddress ?? "";
      _setupTruckListener();
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
            // Merge Firebase data with current user object to avoid losing fields
            final Map<String, dynamic> currentData = _user!.toJson();
            data.forEach((k, v) => currentData[k] = v);
            final updatedUser = UserData.fromJson(currentData);
            
            if (_user?.preferredTruck != updatedUser.preferredTruck) {
              _user = updatedUser;
              _setupTruckListener(); // Restart truck listener if truck ID changed
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
    final truckId = _user?.preferredTruck;
    if (truckId == null || truckId.isEmpty) return;

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

  void _loadTruckDetails() async {
    // This is now handled by _setupTruckListener
  }

  void _loadSettings() async {
    if (_user == null) return;
    
    // SYNC: Ensure we respect the system-level permission choice
    final bool systemEnabled = await SessionManager.isAppNotificationsEnabled();
    
    final ref = _database.ref('driver_settings/${_user!.userId}');
    final snapshot = await ref.get();
    if (snapshot.exists) {
      final data = snapshot.value as Map;
      setState(() {
        _dutyAlerts = systemEnabled && (data['dutyAlerts'] ?? true);
        _collectionNotifications = systemEnabled && (data['collectionNotifications'] ?? true);
        _maintenanceNotifications = systemEnabled && (data['maintenanceNotifications'] ?? true);
        _emergencyAlerts = systemEnabled && (data['emergencyAlerts'] ?? true);
      });
    } else {
      // Initialize with default values respecting system choice
      await ref.set({
        'dutyAlerts': systemEnabled,
        'collectionNotifications': systemEnabled,
        'maintenanceNotifications': systemEnabled,
        'emergencyAlerts': systemEnabled,
        'lastUpdated': ServerValue.timestamp,
      });
      setState(() {
        _dutyAlerts = systemEnabled;
        _collectionNotifications = systemEnabled;
        _maintenanceNotifications = systemEnabled;
        _emergencyAlerts = systemEnabled;
      });
    }
  }

  void _startGpsMonitor() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
      );
      if (mounted) {
        setState(() {
          _gpsAccuracy = "±${position.accuracy.toStringAsFixed(1)} meters";
        });
      }
    } catch (e) {
      if (mounted) setState(() => _gpsAccuracy = "GPS Disabled");
    }
  }

  Future<void> _updateSettings(String key, bool value) async {
    if (_user == null) return;
    
    String label = "";
    if (key == 'dutyAlerts') {
      label = "Duty Alerts";
    } else if (key == 'maintenanceNotifications') {
      label = "Maintenance Notifications";
    }

    try {
      await _database.ref('driver_settings/${_user!.userId}').update({
        key: value,
        'lastUpdated': ServerValue.timestamp,
      });

      if (mounted) {
        setState(() {
          if (key == 'dutyAlerts') {
            _dutyAlerts = value;
            SessionManager.setAppNotificationsEnabled(value);
          } else if (key == 'maintenanceNotifications') {
            _maintenanceNotifications = value;
            SessionManager.setAppNotificationsEnabled(value);
          }
        });
        
        // SYNC WITH OS: Redirect to app settings if toggled OFF to revoke permission
        // or if toggled ON but permission is currently denied.
        if (!kIsWeb) {
          PermissionStatus status = await Permission.notification.status;
          if (!value && status.isGranted) {
             CustomNotification.showTopNotification(context, "Redirecting to system settings to disable permissions...", false);
             await Future.delayed(const Duration(seconds: 1));
             await openAppSettings();
          } else if (value && !status.isGranted) {
             CustomNotification.showTopNotification(context, "Permissions are required to enable this alert.", true);
             await Future.delayed(const Duration(seconds: 1));
             await openAppSettings();
          } else {
             CustomNotification.showTopNotification(context, "$label ${value ? 'enabled' : 'disabled'} successfully.", false);
          }
        } else {
          CustomNotification.showTopNotification(context, "$label ${value ? 'enabled' : 'disabled'} successfully.", false);
        }
      }
    } catch (e) {
      if (mounted) {
        CustomNotification.showTopNotification(context, "Failed to update $label. Try again.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content = SafeArea(
      child: Stack(
        children: [
          Listener(
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
            child: Column(
              children: [
                _buildHeader(),
                const SizedBox(height: 12),
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
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Column(
                                children: [
                                  _buildSectionHeader(Icons.person_rounded, "Profile Information"),
                                  _buildProfilePictureSection(),
                                  const SizedBox(height: 16),
                                  _buildProfileCard(),
                                  const SizedBox(height: 24),

                                  _buildSectionHeader(Icons.route_rounded, "Route Management"),
                                  _buildRouteManagement(),
                                  const SizedBox(height: 24),

                                  _buildSectionHeader(Icons.local_shipping_rounded, "Truck Information"),
                                  _buildTruckInformation(),
                                  const SizedBox(height: 24),

                                  _buildSectionHeader(Icons.notifications_rounded, "Notifications"),
                                  _buildNotificationsSection(),
                                  const SizedBox(height: 24),

                                  _buildSectionHeader(Icons.security_rounded, "Security & Data"),
                                  _buildSecurityDataSection(),
                                  const SizedBox(height: 24),

                                  _buildSectionHeader(Icons.help_outline_rounded, "Support & Legal"),
                                  _buildSupportLegalSection(),
                                  const SizedBox(height: 24),

                                  _buildSectionHeader(Icons.info_outline_rounded, "App Information"),
                                  _buildAppInformation(),
                                  const SizedBox(height: 32),
                                  
                                  _buildLogoutButton(),
                                  const SizedBox(height: 16),
                                  _buildDeleteAccountButton(),
                                  SizedBox(height: Responsive.isDesktop(context) ? 24 : 100),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          AnimatedBuilder(
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
          ),
        ],
      ),
    );

    if (widget.isEmbedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: FadeSlideEntrance(
        child: content,
      ),
    );
  }

  Widget _buildHeader() {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = Responsive.isDesktop(context);
    
    if (isDesktop) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
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
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2F1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.settings_suggest_rounded, color: AppColors.tealText, size: 28),
            ),
            const SizedBox(width: 20),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Account Settings",
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1A1A1A),
                        letterSpacing: -0.5)),
                Text("Manage your personal information and application preferences.",
                    style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
              ],
            ),
            const Spacer(),
          ],
        ),
      );
    }

    // Adaptive font sizes
    final double titleFontSize = (screenWidth * 0.055).clamp(18.0, 22.0);
    final double subtitleFontSize = (screenWidth * 0.03).clamp(10.0, 12.0);
    final double iconContainerSize = (screenWidth * 0.12).clamp(40.0, 48.0);
    final double iconSize = (screenWidth * 0.06).clamp(20.0, 24.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16), // Pinantay sa padding ng resident settings header
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: const Color(0xFFEEEEEE), width: _showHeaderShadow ? 0 : 1)),
        boxShadow: [
          if (_showHeaderShadow)
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
        ],
      ),
      child: Row(
        children: [
          if (widget.onBack != null) ...[
            _buildCircularBackButton(),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Account Settings", style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.w900, color: const Color(0xFF1A1A1A), letterSpacing: -0.5)),
                Text("Manage your driver profile and preferences", style: TextStyle(fontSize: subtitleFontSize, color: const Color(0xFF757575), fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Container(
            width: iconContainerSize,
            height: iconContainerSize,
            decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.settings_suggest_rounded, color: AppColors.tealText, size: iconSize),
          ),
        ],
      ),
    );
  }

  Widget _buildCircularBackButton() {
    return GestureDetector(
      onTap: widget.onBack ?? () => Navigator.pop(context),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1A1A1A), size: 18),
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double headerFontSize = (screenWidth * 0.035).clamp(11.0, 13.0);
    final double iconSize = (screenWidth * 0.045).clamp(16.0, 18.0);

    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: iconSize, color: AppColors.tealText),
          const SizedBox(width: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: headerFontSize,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF1A1A1A),
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double labelFontSize = (screenWidth * 0.03).clamp(10.0, 12.0);
    final double valueFontSize = (screenWidth * 0.04).clamp(14.0, 16.0);

    return Stack(
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            boxShadow: AppTheme.balancedPulidongShadow,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProfileRow("Full Name", _user?.name ?? "Loading...", labelFontSize: labelFontSize, valueFontSize: valueFontSize),
              const Divider(height: 32, thickness: 0.5),
              _buildProfileRow("Email Address", _user?.email ?? "Not set", labelFontSize: labelFontSize, valueFontSize: valueFontSize),
              const Divider(height: 32, thickness: 0.5),
              _buildProfileRow("Contact Number", _user?.phone ?? "Not set", labelFontSize: labelFontSize, valueFontSize: valueFontSize),
              const Divider(height: 32, thickness: 0.5),
              _buildProfileRow("Assigned Truck", _user?.preferredTruck ?? "None", labelFontSize: labelFontSize, valueFontSize: valueFontSize),
              const Divider(height: 32, thickness: 0.5),
              _buildProfileRow("Plate Number", _truckPlateNumber ?? "N/A", labelFontSize: labelFontSize, valueFontSize: valueFontSize),
            ],
          ),
        ),
        Positioned(
          top: 16,
          right: 16,
          child: _HoverZoomLink(
            onTap: _showDataManagementModal,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.edit_rounded, size: 16, color: Color(0xFF00796B)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfilePictureSection() {
    final String displayName = _user?.name.isNotEmpty == true ? _user!.name : "Driver";
    final String? profileUrl = _user?.profilePicture;
    final double screenWidth = MediaQuery.of(context).size.width;
    final double picSize = (screenWidth * 0.2).clamp(64.0, 80.0);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: AppTheme.balancedPulidongShadow,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _viewProfilePictureLarge,
            child: Stack(
              children: [
                Container(
                  width: picSize,
                  height: picSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF00695C), width: 2),
                    image: profileUrl != null && profileUrl.isNotEmpty
                        ? DecorationImage(image: NetworkImage(profileUrl), fit: BoxFit.cover)
                        : null,
                  ),
                  child: profileUrl == null || profileUrl.isEmpty
                      ? Center(
                          child: Text(
                            displayName.isNotEmpty ? displayName[0].toUpperCase() : "D",
                            style: TextStyle(fontSize: picSize * 0.4, fontWeight: FontWeight.bold, color: const Color(0xFF00695C)),
                          )
                        )
                      : null,
                ),
                if (_isLoading)
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(color: Colors.black26, shape: BoxShape.circle),
                      child: const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Driver", style: TextStyle(fontSize: (screenWidth * 0.03).clamp(10.0, 12.0), color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  displayName,
                  style: TextStyle(fontSize: (screenWidth * 0.04).clamp(14.0, 16.0), fontWeight: FontWeight.w800, color: const Color(0xFF2C3E50)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildCompactActionBtn(
                      label: "Upload",
                      icon: Icons.camera_alt_rounded,
                      onTap: _showUploadOptions,
                      color: AppColors.tealText,
                    ),
                    if (profileUrl != null && profileUrl.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      _buildCompactActionBtn(
                        label: "Delete",
                        icon: Icons.delete_outline_rounded,
                        onTap: _confirmDeletePicture,
                        color: Colors.redAccent,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactActionBtn({required String label, required IconData icon, required VoidCallback onTap, required Color color}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      ),
    );
  }

  void _viewProfilePictureLarge() {
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
                    tag: 'settings_profile_pic_${_user?.userId ?? 'default'}',
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
                                (_user?.name != null && _user!.name.isNotEmpty) ? _user!.name[0].toUpperCase() : "D",
                                style: const TextStyle(fontSize: 80, fontWeight: FontWeight.bold, color: const Color(0xFF00695C)),
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

  void _showUploadOptions() {
    if (Responsive.isDesktop(context) || Responsive.isTablet(context)) {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: _buildUploadOptionsContent(),
          ),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) => _buildUploadOptionsContent(),
    );
  }

  Widget _buildUploadOptionsContent() {
    final bool isDesktop = Responsive.isDesktop(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Upload Photo",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.tealText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            "Choose how you want to upload your profile picture.",
            style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 24),
          _buildUploadOptionItem(
            icon: isDesktop ? Icons.file_upload_rounded : Icons.photo_library_rounded,
            label: isDesktop ? "Choose from File" : "Choose from Gallery",
            onTap: () {
              Navigator.pop(context);
              _handleImageSelection(ImageSource.gallery);
            },
          ),
          const SizedBox(height: 12),
          _buildUploadOptionItem(
            icon: Icons.camera_enhance_rounded,
            label: "Take a Selfie",
            onTap: () {
              Navigator.pop(context);
              _handleImageSelection(ImageSource.camera);
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildUploadOptionItem({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.tealText.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.tealText, size: 20),
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF2C3E50)),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _handleImageSelection(ImageSource source) async {
    if (_user == null) return;

    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: source,
      preferredCameraDevice: CameraDevice.front,
    );

    if (image == null) return;

    final String fileName = image.name.toLowerCase();
    bool isValid = fileName.endsWith('.png') || 
                   fileName.endsWith('.jpg') || 
                   fileName.endsWith('.jpeg');
    
    if (!isValid) {
      if (mounted) {
        CustomNotification.showTopNotification(context, "Only PNG and JPEG images are allowed.");
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      final bytes = await image.readAsBytes();
      
      final response = await _apiService.uploadProfilePicture(
        userId: _user!.userId,
        role: _user!.role,
        fileName: image.name,
        imageBytes: bytes.toList(),
      );

      if (response.data['success'] == true) {
        final String profileUrl = response.data['url'];

        // Update Firebase Realtime Database
        await _database.ref('users/${_user!.userId}').update({'profile_picture': profileUrl});
        
        // Update Local Session
        final updatedUser = {..._user!.toJson(), 'profile_picture': profileUrl};
        await SessionManager.saveUser(updatedUser);
        
        _loadUser(); // Refresh local user state
        
        if (mounted) {
          CustomNotification.showTopNotification(context, "Profile picture updated successfully.", false);
        }
      } else {
        throw Exception(response.data['message'] ?? "Upload failed");
      }
    } catch (e) {
      if (mounted) {
        CustomNotification.showTopNotification(context, "Failed to upload image: $e");
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _confirmDeletePicture() async {
    final confirmed = await _showConfirmActionDialog(
      title: "Delete Photo?",
      message: "Are you sure you want to remove your profile picture? This will revert to your initials.",
      confirmText: "Delete Photo",
      isDestructive: true,
      icon: null, // Removed icon
    );

    if (confirmed) {
      setState(() => _isLoading = true);
      try {
        await _database.ref('users/${_user!.userId}').update({'profile_picture': null});
        
        await _apiService.updateProfile(
          userId: _user!.userId,
          role: _user!.role,
          name: _user!.name,
          phone: _user!.phone ?? "",
          email: _user!.email,
          preferredTruck: _user!.preferredTruck ?? "",
          address: _user!.completeAddress ?? "",
          profilePicture: "", // Clear in MySQL
        );

        final updatedUser = {..._user!.toJson()};
        updatedUser.remove('profile_picture');
        await SessionManager.saveUser(updatedUser);
        
        _loadUser();
        
        if (mounted) {
          CustomNotification.showTopNotification(context, "Profile picture removed.", false);
        }
      } catch (e) {
        if (mounted) CustomNotification.showTopNotification(context, "Error deleting photo: $e");
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildProfileRow(String label, String value, {double? labelFontSize, double? valueFontSize}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: labelFontSize ?? 11, color: Colors.grey.shade600, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: valueFontSize ?? 16, color: const Color(0xFF2C3E50)),
        ),
      ],
    );
  }

  Widget _buildRouteManagement() {
    return _buildSectionCard(
      children: [
        _buildMenuAction(Icons.route_rounded, "View Daily Routes", () => _showDailyRoutes()),
        _buildDivider(),
        _buildMenuAction(Icons.analytics_rounded, "Performance Stats", () => _showPerformanceStats()),
      ],
    );
  }

  Widget _buildTruckInformation() {
    return _buildSectionCard(
      children: [
        _buildMenuAction(Icons.local_shipping_rounded, "Truck Details", () => _showTruckDetails()),
        _buildDivider(),
        _buildMenuAction(Icons.engineering_rounded, "Maintenance Schedule", () => _showMaintenanceSchedule()),
        _buildDivider(),
        _buildMenuAction(Icons.report_problem_rounded, "Report Issue", () => _showReportIssue()),
        _buildDivider(),
        _buildMenuAction(Icons.history_rounded, "Issue History", () => _showIssueHistory()),
      ],
    );
  }

  Widget _buildNotificationsSection() {
    return _buildSectionCard(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildToggleRow("Duty Alerts", _dutyAlerts, (v) => _updateSettings('dutyAlerts', v)),
        _buildDivider(),
        _buildToggleRow("Maintenance Alerts", _maintenanceNotifications, (v) => _updateSettings('maintenanceNotifications', v)),
      ],
    );
  }

  Widget _buildToggleRow(String label, bool value, Function(bool) onChanged) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double fontSize = (screenWidth * 0.04).clamp(14.0, 16.0);
    final double iconPadding = (screenWidth * 0.02).clamp(6.0, 8.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(iconPadding),
                decoration: BoxDecoration(
                  color: AppColors.tealText.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  label.contains("Duty") ? Icons.notification_important_rounded : Icons.engineering_rounded, 
                  size: 18, 
                  color: AppColors.tealText
                ),
              ),
              const SizedBox(width: 16),
              Text(
                label, 
                style: TextStyle(
                  fontWeight: FontWeight.w600, 
                  fontSize: fontSize, 
                  color: const Color(0xFF2C3E50)
                )
              ),
            ],
          ),
          Switch(
            value: value, 
            onChanged: onChanged, 
            activeTrackColor: AppColors.tealText.withValues(alpha: 0.5),
            activeColor: AppColors.tealText,
            inactiveTrackColor: Colors.grey.shade200,
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityDataSection() {
    return _buildSectionCard(
      children: [
        _buildMenuAction(Icons.password_rounded, "Change Password", () => _showChangePasswordModal()),
      ],
    );
  }

  Widget _buildSupportLegalSection() {
    return _buildSectionCard(
      children: [
        _buildMenuAction(Icons.language_rounded, "Language", () => _showLanguageModal()),
        _buildDivider(),
        _buildMenuAction(Icons.gavel_rounded, "Terms & Conditions", () => LegalAgreementDialog.show(context, isTerms: true)),
        _buildDivider(),
        _buildMenuAction(Icons.privacy_tip_rounded, "Privacy Policy", () => LegalAgreementDialog.show(context, isTerms: false)),
        _buildDivider(),
        _buildMenuAction(Icons.quiz_rounded, "FAQs", () => _showFAQsModal()),
        _buildDivider(),
        _buildMenuAction(Icons.contact_support_rounded, "Contact Support", () => _showContactSupportModal()),
        _buildDivider(),
        _buildMenuAction(Icons.info_rounded, "About Us", () => _showAboutUsModal()),
      ],
    );
  }

  Widget _buildAppInformation() {
    return _buildSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      children: [
        _buildInfoRow("Version", _appVersion),
        const SizedBox(height: 16),
        _buildInfoRow("GPS Accuracy", _gpsAccuracy, valueColor: AppColors.statusGreen),
        const SizedBox(height: 16),
        _buildInfoRow("Last Updated", "April 2026"),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double fontSize = (screenWidth * 0.04).clamp(13.0, 15.0);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600, fontSize: fontSize)),
        Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: fontSize, color: valueColor ?? const Color(0xFF2C3E50))),
      ],
    );
  }

  Widget _buildSectionCard({
    required List<Widget> children,
    EdgeInsets? padding
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: AppTheme.balancedPulidongShadow,
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(0),
        child: Column(children: children),
      ),
    );
  }

  Widget _buildMenuAction(IconData icon, String title, VoidCallback onTap, {bool showIcon = true, EdgeInsets? padding, Color? textColor}) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double titleFontSize = (screenWidth * 0.04).clamp(14.0, 16.0);
    final double iconSize = (screenWidth * 0.045).clamp(16.0, 18.0);
    final double iconPadding = (screenWidth * 0.02).clamp(6.0, 8.0);

    return InkWell(
      onTap: () {
        if (_isNavigating) return;
        onTap();
      },
      hoverColor: Colors.transparent,
      splashColor: (textColor ?? AppColors.tealText).withOpacity(0.05),
      highlightColor: Colors.transparent,
      child: Padding(
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(iconPadding),
              decoration: BoxDecoration(
                color: (textColor ?? AppColors.tealText).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: iconSize, color: textColor ?? AppColors.tealText),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title, 
                style: TextStyle(
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.w600, 
                  color: textColor ?? const Color(0xFF2C3E50)
                )
              ),
            ),
            if (showIcon) Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey.shade300),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(height: 1, color: Colors.grey.shade300, indent: 24, endIndent: 24); // Darker grey
  }

  Widget _buildLogoutButton() {
    return HoverActionButton(
      text: "Logout",
      loadingText: "Logging out...",
      isLoading: _isNavigating,
      onTap: () => _showLogoutDialog(context),
    );
  }

  Widget _buildDeleteAccountButton() {
    return HoverActionButton(
      text: "Delete Account",
      loadingText: "Deleting Account...",
      isLoading: _isNavigating,
      isDestructive: true,
      onTap: () => _showDeleteAccountConfirmation(),
    );
  }

  // --- TRUCK INFORMATION METHODS ---

  void _showTruckDetails() async {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);

    try {
      final currentTruckId = _user?.preferredTruck ?? "Unknown";
      final idCtrl = TextEditingController(text: currentTruckId);
      final plateCtrl = TextEditingController(text: _truckPlateNumber ?? "");
      
      String? plateError;

      if (!context.mounted) return;

      final idFocus = FocusNode();
      final plateFocus = FocusNode();

      _showModal("Truck Details", [
        StatefulBuilder(
          builder: (context, setModalState) {
            idFocus.addListener(() { if (mounted) setModalState(() {}); });
            plateFocus.addListener(() { if (mounted) setModalState(() {}); });

            void validatePlate(String val) {
              // Standard PH Plate Format: ABC 123 or ABC 1234
              final reg = RegExp(r'^[A-Z]{3}\s\d{3,4}$');
              if (val.isEmpty) {
                setModalState(() => plateError = "Plate number is required");
              } else if (!reg.hasMatch(val)) {
                setModalState(() => plateError = "Invalid format (e.g., ABC 1234)");
              } else {
                setModalState(() => plateError = null);
              }
            }

            return Column(
              children: [
                _buildTextField("Truck ID", idCtrl, focusNode: idFocus, prefixIcon: Icons.local_shipping_outlined),
                _buildTextField(
                  "Plate Number", 
                  plateCtrl,
                  focusNode: plateFocus,
                  hintText: "e.g., ABC 1234",
                  errorText: plateError,
                  onChanged: validatePlate,
                  prefixIcon: Icons.badge_outlined,
                ),
              ],
            );
          }
        ),
      ], "SAVE CHANGES", () async {
        final newTruckId = idCtrl.text.trim();
        final newPlate = plateCtrl.text.trim();
        final currentTruckId = _user?.preferredTruck ?? "Unknown";
        final currentPlate = _truckPlateNumber ?? "";

        // VALIDATION: No changes detected
        if (newTruckId == currentTruckId && newPlate == currentPlate) {
          CustomNotification.showTopNotification(context, "No changes detected. Info is already up to date.");
          return false;
        }

        // VALIDATION: Empty fields
        if (newTruckId.isEmpty || newPlate.isEmpty) {
          return false;
        }

        // VALIDATION: Plate Format (Final check)
        final reg = RegExp(r'^[A-Z]{3}\s\d{3,4}$');
        if (!reg.hasMatch(newPlate)) {
          return false;
        }

        try {
          // 1. If Truck ID changed, handle the handover
          if (newTruckId != currentTruckId) {
            // A. Mark old location entry as OFFLINE
            await _database.ref('truck_locations/$currentTruckId').update({
              'isOnline': false,
              'status': 'OFFLINE',
              'lastSeen': ServerValue.timestamp,
            });

            // B. If there's an active session, migrate it to the new Truck ID
            if (widget.currentSessionId != null) {
              await _database.ref('driver_routes/${widget.currentSessionId}').update({
                'truck_id': newTruckId,
              });
              // Prepare the new location entry with the session ID
              await _database.ref('truck_locations/$newTruckId').update({
                'current_session': widget.currentSessionId,
                'driver_id': _user?.userId,
                'driver_name': _user?.name,
                'plate_number': newPlate,
                'isOnline': true,
                'status': 'ACTIVE',
              });
            }
          }

          // 2. Update/Create the truck document (Metadata) - AUTHORITATIVE
          await _database.ref('trucks/$newTruckId').update({
            'truckId': newTruckId,
            'plateNumber': newPlate,
            'lastUpdatedBy': _user?.userId,
            'updatedAt': ServerValue.timestamp,
          });

          // 3. Update the live location node with the new plate number too
          await _database.ref('truck_locations/$newTruckId').update({
            'plate_number': newPlate,
            'truck_id': newTruckId,
          });

          // 4. Update Firebase user node (Triggers real-time sync across all screens)
          await _database.ref('users/${_user!.userId}').update({
            'preferred_truck': newTruckId,
            'lastUpdated': ServerValue.timestamp,
          });

          debugPrint("[TRUCK_SYNC] Authoritative updates succeeded for $newTruckId");

          // 5. Update SQL backend (Non-blocking sync)
          try {
            final response = await _apiService.updateProfile(
              userId: _user!.userId,
              role: _user!.role,
              name: _user!.name,
              phone: _user!.phone ?? "",
              email: _user!.email,
              preferredTruck: newTruckId,
              address: _user!.completeAddress ?? "",
            );

            if (response.data['success'] == true) {
              final updatedUser = _user!.copyWith(preferredTruck: newTruckId);
              await SessionManager.saveUser(updatedUser.toJson());
            }
          } catch (e) {
            debugPrint("[TRUCK_SYNC] SQL Backend sync error (ignored): $e");
          }
          
          return true; 
        } catch (e) {
          debugPrint("[TRUCK_SYNC] Authoritative update failed: $e");
          rethrow;
        }
      }, description: "View and edit assigned truck identification details.", maxHeightMultiplier: 0.85);
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
      if (data.containsKey('maintenance')) {
        needsInit = false;
      }
    }

    if (needsInit) {
      await ref.update({
        'odometerKm': 0.0,
        'maintenance': {
          'oilChange': {
            'intervalKm': 5000.0,
            'remainingKm': 5000.0,
            'lastServiceAt': null,
            'status': "NORMAL",
            'notified500': false,
            'notified100': false,
            'notifiedDue': false,
          },
          'tireRotation': {
            'intervalKm': 10000.0,
            'remainingKm': 10000.0,
            'lastServiceAt': null,
            'status': "NORMAL",
            'notified500': false,
            'notified100': false,
            'notifiedDue': false,
          },
          'fullInspection': {
            'intervalKm': 20000.0,
            'remainingKm': 20000.0,
            'lastServiceAt': null,
            'status': "NORMAL",
            'notified500': false,
            'notified100': false,
            'notifiedDue': false,
          }
        }
      });
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
        children: [
          const SizedBox(height: 8),
          // Listen to Truck Location for LIVE distance subtraction
          StreamBuilder<DatabaseEvent>(
            stream: _database.ref('truck_locations/$truckId').onValue,
            builder: (context, locSnapshot) {
              double currentTripDist = 0.0;
              if (locSnapshot.hasData && locSnapshot.data!.snapshot.value != null) {
                final loc = locSnapshot.data!.snapshot.value as Map;
                // Only if it's an active session, we show live preview
                if (loc['current_session'] != null) {
                  currentTripDist = (loc['distance'] ?? 0.0).toDouble();
                }
              }

              return StreamBuilder<DatabaseEvent>(
                stream: _database.ref('trucks/$truckId/maintenance').onValue,
                builder: (context, snapshot) {
                  if (snapshot.hasError) return Text("Error: ${snapshot.error}");
                  if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
                    return const Center(child: CircularProgressIndicator(color: AppColors.tealText));
                  }
                  
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

  Widget _buildMaintenanceItem(String title, dynamic item, String key, String truckId, {double currentTripDist = 0.0}) {
    if (item == null) return const SizedBox.shrink();
    
    // LIVE DEDUCTION PREVIEW
    double savedRemaining = (item['remainingKm'] ?? 0.0).toDouble();
    double remaining = savedRemaining - currentTripDist;
    if (remaining < -9999) remaining = -9999; // Cap extreme values
    
    // DYNAMIC STATUS LOGIC
    String status = "NORMAL";
    Color statusColor = Colors.green;

    if (remaining <= 0) {
      status = "SERVICE DUE";
      statusColor = Colors.red;
    } else if (remaining <= 100) {
      status = "URGENT";
      statusColor = Colors.redAccent;
    } else if (remaining <= 500) {
      status = "DUE SOON";
      statusColor = Colors.orange;
    }

    String subText = remaining <= 0 
        ? "Overdue by ${(remaining.abs()).toStringAsFixed(1)} km" 
        : "Remaining: ${remaining.toStringAsFixed(1)} km";

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300, width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF1A1A1A))),
                const SizedBox(height: 4),
                Text(subText, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.w900, fontSize: 10)),
              ),
              const SizedBox(height: 8),
              _HoverZoomLink(
                onTap: (remaining > 500) ? null : () => _handleMarkMaintenanceDone(truckId, key, item['intervalKm'] ?? 5000.0),
                child: Text(
                  "MARK DONE",
                  style: TextStyle(
                    color: (remaining > 500) ? Colors.grey.shade300 : AppColors.tealText,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 0.5
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleMarkMaintenanceDone(String truckId, String key, double interval) async {
    try {
      await _database.ref('trucks/$truckId/maintenance/$key').update({
        'status': 'NORMAL',
        'remainingKm': interval,
        'lastServiceAt': ServerValue.timestamp,
        'notified500': false,
        'notified100': false,
        'notifiedDue': false,
      });
      if (mounted) CustomNotification.showTopNotification(context, "Maintenance task completed!", false);
    } catch (e) {
      if (mounted) CustomNotification.showTopNotification(context, "Failed to update maintenance.");
    }
  }

  void _showReportIssue() async {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);

    try {
      // Pre-check permissions before opening the modal
      await Geolocator.checkPermission();
      
      final descCtrl = TextEditingController();
      final typeCtrl = TextEditingController(text: "Engine");
      final urgencyCtrl = TextEditingController(text: "Medium");
      
      String? descError;

      final typeFocus = FocusNode();
      final urgencyFocus = FocusNode();
      final descFocus = FocusNode();

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
        if (description.isEmpty) {
          return false;
        }

        if (_user == null) {
          CustomNotification.showTopNotification(context, "User session not found. Please log in again.");
          return false;
        }

        try {
          // Attempt to get position with a short timeout to prevent hanging
          Position? pos;
          try {
            pos = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.low,
              timeLimit: const Duration(seconds: 3),
            );
          } catch (e) {
            debugPrint("GPS Timeout during report: $e");
          }

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

          // TRIGGER NOTIFICATION FOR ADMIN
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
        } catch (e) {
          debugPrint("Submit Issue Error: $e");
          return false;
        }
      }, loadingText: "Submitting report...", description: "Log any vehicle problems or mechanical issues for maintenance review.", successMessage: "Successful submit complaint", maxHeightMultiplier: 0.85);
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  void _showSelectionPicker({required String title, required List<String> options, String? selectedValue, required Function(String) onSelect, FocusNode? focusNode}) {
    _showStyledBottomSheet(
      title: title,
      loadingText: "Preparing options...",
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

  void _showIssueHistory() {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);

    final GlobalKey<AnimatedListState> listKey = GlobalKey<AnimatedListState>();
    final ValueNotifier<bool> selectionModeNotifier = ValueNotifier<bool>(false);
    final ValueNotifier<int> selectionCountNotifier = ValueNotifier<int>(0);
    final Set<String> selectedIds = {};
    List<Map> issues = [];
    bool isClearingAll = false;

    try {
      _showStyledBottomSheet(
        title: "Issue History",
        loadingText: "Retrieving issue history...",
        titleWidget: ValueListenableBuilder<bool>(
          valueListenable: selectionModeNotifier,
          builder: (context, isSelection, _) {
            final double screenWidth = MediaQuery.of(context).size.width;
            final double titleFontSize = (screenWidth * 0.055).clamp(18.0, 22.0);
            return Text(
              isSelection ? "Select issues history to delete" : "Issue History",
              style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.w900, color: AppColors.tealText),
            );
          },
        ),
        descriptionWidget: ValueListenableBuilder<int>(
          valueListenable: selectionCountNotifier,
          builder: (context, count, _) {
            final double screenWidth = MediaQuery.of(context).size.width;
            final double descFontSize = (screenWidth * 0.035).clamp(11.0, 13.0);
            return Text(
              selectionModeNotifier.value 
                  ? "$count items selected" 
                  : "Track the status and resolution of your reported vehicle problems.",
              style: TextStyle(fontSize: descFontSize, color: Colors.grey, fontWeight: FontWeight.w500),
            );
          },
        ),
        children: [
          StatefulBuilder(builder: (context, setModalState) {
            void updateSelectionState() {
              selectionModeNotifier.value = selectedIds.isNotEmpty;
              selectionCountNotifier.value = selectedIds.length;
              setModalState(() {});
            }

            void toggleSelection(String id) {
              if (selectedIds.contains(id)) {
                selectedIds.remove(id);
              } else {
                selectedIds.add(id);
              }
              updateSelectionState();
            }

            void cancelSelection() {
              selectedIds.clear();
              updateSelectionState();
            }

            void selectAll() {
              if (selectedIds.length == issues.length) {
                selectedIds.clear();
              } else {
                for (var issue in issues) {
                  selectedIds.add(issue['id']);
                }
              }
              updateSelectionState();
            }

            Future<void> deleteSelected() async {
              if (selectedIds.isEmpty) return;
              bool confirmed = await _showConfirmActionDialog(
                  title: "Delete Selected?",
                  message: "Remove ${selectedIds.length} reports permanently?",
                  isDestructive: true,
                  icon: null);

              if (confirmed) {
                setModalState(() => isClearingAll = true);
                final keysToRemove = List<String>.from(selectedIds);
                
                for (String key in keysToRemove) {
                  int idx = issues.indexWhere((n) => n['id'] == key);
                  if (idx != -1) {
                    final removedItem = issues[idx];
                    issues.removeAt(idx);
                    
                    listKey.currentState?.removeItem(
                      idx,
                      (context, animation) => SlideTransition(
                        position: animation.drive(Tween<Offset>(begin: const Offset(1.5, 0.0), end: Offset.zero)),
                        child: FadeTransition(
                          opacity: animation,
                          child: SizeTransition(sizeFactor: animation, axisAlignment: -1.0, child: _buildIssueItem(removedItem, const AlwaysStoppedAnimation(1.0))),
                        ),
                      ),
                      duration: const Duration(milliseconds: 300),
                    );
                    _database.ref('truck_issues/$key').remove();
                    await Future.delayed(const Duration(milliseconds: 80));
                  }
                }
                
                setModalState(() {
                  selectedIds.clear();
                  updateSelectionState();
                  isClearingAll = false;
                });
                CustomNotification.showTopNotification(context, "Reports deleted successfully.", false);
              }
            }

            return StreamBuilder<DatabaseEvent>(
              stream: _database.ref('truck_issues').onValue,
              builder: (context, snapshot) {
                if (snapshot.hasError) return Text("Error: ${snapshot.error}");
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.tealText));

                if (!snapshot.data!.snapshot.exists || snapshot.data!.snapshot.value == null) {
                  return const Center(child: Padding(padding: EdgeInsets.all(40), child: Text("No previous reports.", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))));
                }

                if (!isClearingAll) {
                  final Map data = snapshot.data!.snapshot.value as Map;
                  List<Map> newList = [];
                  data.forEach((k, v) {
                    final val = v as Map;
                    // Robust filtering: Check both int and string driverId
                    if (val['driverId']?.toString() == _user?.userId.toString()) {
                      newList.add({...val, 'id': k});
                    }
                  });
                  newList.sort((a, b) => (b['createdAt'] ?? 0).compareTo(a['createdAt'] ?? 0));
                  issues = newList;
                }

                if (issues.isEmpty && !isClearingAll) {
                  return const Center(child: Padding(padding: EdgeInsets.all(40), child: Text("No previous reports.", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))));
                }

                final bool isSelectionActive = selectionModeNotifier.value;

                return Column(
                  children: [
                    if (isSelectionActive && issues.isNotEmpty && !isClearingAll)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _HoverZoomLink(
                              onTap: selectAll,
                              child: Text(selectedIds.length == issues.length ? "Deselect All" : "Select All",
                                  style: const TextStyle(color: Color(0xFF00796B), fontWeight: FontWeight.w900, fontSize: 13)),
                            ),
                            Row(
                              children: [
                                _HoverZoomLink(
                                  onTap: cancelSelection,
                                  child: const Text("Cancel", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w900, fontSize: 13)),
                                ),
                                const SizedBox(width: 20),
                                if (selectedIds.isNotEmpty)
                                  _HoverZoomLink(
                                    onTap: deleteSelected,
                                    child: const Text("Delete", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, fontSize: 13)),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      )
                    else if (issues.isNotEmpty && !isClearingAll)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("${issues.length} Reports Found", style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    
                    isClearingAll 
                        ? const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: AppColors.tealText)))
                        : AnimatedList(
                            key: listKey,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            initialItemCount: issues.length,
                            itemBuilder: (context, index, animation) {
                              if (index >= issues.length) return const SizedBox();
                              final issue = issues[index];
                              return _buildDismissibleIssue(
                                issue,
                                isSelectionMode: isSelectionActive,
                                isSelected: selectedIds.contains(issue['id']),
                                onTap: () {
                                  if (isSelectionActive) toggleSelection(issue['id']);
                                },
                                onLongPress: !Responsive.isDesktop(context) ? () => toggleSelection(issue['id']) : null,
                                onDoubleTap: Responsive.isDesktop(context) ? () => toggleSelection(issue['id']) : null,
                              );
                            },
                          ),
                  ],
                );
              },
            );
          }),
        ],
      );
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Widget _buildDismissibleIssue(Map issue, {bool isSelectionMode = false, bool isSelected = false, VoidCallback? onTap, VoidCallback? onLongPress, VoidCallback? onDoubleTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        onDoubleTap: onDoubleTap,
        borderRadius: BorderRadius.circular(24),
        child: isSelectionMode
            ? _buildIssueItem(issue, const AlwaysStoppedAnimation(1.0), isSelected: isSelected, isSelectionMode: isSelectionMode)
            : Dismissible(
                key: Key(issue['id']),
                direction: DismissDirection.horizontal,
                confirmDismiss: (dir) => _showConfirmActionDialog(
                  title: "Delete Report?",
                  message: "Are you sure you want to remove this issue report from your history?",
                  confirmText: "Delete",
                  isDestructive: true,
                  icon: null,
                ),
                onDismissed: (dir) {
                  _database.ref('truck_issues/${issue['id']}').remove();
                  CustomNotification.showTopNotification(context, "Report deleted successfully.", false);
                },
                background: _buildDismissBackground(Alignment.centerLeft),
                secondaryBackground: _buildDismissBackground(Alignment.centerRight),
                child: _buildIssueItem(issue, const AlwaysStoppedAnimation(1.0)),
              ),
      ),
    );
  }

  Widget _buildIssueItem(Map issue, Animation<double> animation, {bool isSelected = false, bool isSelectionMode = false}) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double typeFontSize = (screenWidth * 0.035).clamp(11.0, 13.0);
    final double statusFontSize = (screenWidth * 0.03).clamp(9.0, 10.0);
    final double descFontSize = (screenWidth * 0.04).clamp(14.0, 15.0);
    final double dateFontSize = (screenWidth * 0.03).clamp(10.0, 11.0);
    final double responseLabelFontSize = (screenWidth * 0.03).clamp(9.0, 10.0);
    final double responseTextFontSize = (screenWidth * 0.035).clamp(12.0, 13.0);

    String status = (issue['status'] ?? "PENDING").toString().toUpperCase().replaceAll('_', ' ');
    Color statusColor = Colors.orange;
    if (status == "IN PROGRESS") statusColor = Colors.blue;
    if (status == "RESOLVED") statusColor = Colors.green;
    return FadeTransition(
      opacity: animation,
      child: SizeTransition(
        sizeFactor: animation,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFE0F2F1) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 10, offset: const Offset(0, 4))],
            border: Border.all(color: isSelected ? const Color(0xFF00796B) : Colors.grey.shade300, width: isSelected ? 2.0 : 1.5)
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isSelectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 16, top: 4),
                  child: Icon(
                    isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    color: const Color(0xFF00796B),
                    size: 22,
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          (issue['issueType'] ?? "Issue").toString().toUpperCase(),
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: typeFontSize, color: Colors.grey, letterSpacing: 1.1)
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                          child: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.w900, fontSize: statusFontSize)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      issue['description'] ?? "",
                      style: TextStyle(fontSize: descFontSize, color: const Color(0xFF2C3E50), fontWeight: FontWeight.w700, height: 1.4)
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(Icons.calendar_today_rounded, size: 12, color: Colors.grey.shade400),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('MMM dd, yyyy • hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(issue['createdAt'] ?? 0)),
                          style: TextStyle(fontSize: dateFontSize, color: Colors.grey.shade500, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    if (issue['adminResponse'] != null && issue['adminResponse'].toString().isNotEmpty) ...[
                      const Divider(height: 32, color: Color(0xFFEEEEEE)),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FA),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade100)
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.reply_rounded, size: 12, color: Color(0xFF00796B)),
                                const SizedBox(width: 8),
                                Text("ADMIN RESPONSE", style: TextStyle(fontSize: responseLabelFontSize, fontWeight: FontWeight.w900, color: const Color(0xFF00796B), letterSpacing: 0.5)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              issue['adminResponse'],
                              style: TextStyle(fontSize: responseTextFontSize, color: Colors.black87, fontWeight: FontWeight.w600, height: 1.5)
                            ),
                          ],
                        ),
                      )
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDismissBackground(Alignment alignment) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(24)),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
    );
  }

  Future<void> _handleDeleteAllIssues(List issues) async {
    bool confirmed = await _showConfirmActionDialog(
      title: "Clear History?",
      message: "This will permanently remove all your reported issues.",
      confirmText: "Delete All",
      isDestructive: true
    );
    if (confirmed) {
      for (var issue in issues) {
        await _database.ref('truck_issues/${issue['id']}').remove();
      }
      if (mounted) CustomNotification.showTopNotification(context, "History cleared successfully", false);
    }
  }

  Future<bool> _showConfirmActionDialog({
    required String title, 
    required String message, 
    String confirmText = "Confirm", 
    String cancelText = "Cancel",
    bool isDestructive = false,
    IconData? icon,
    Color? iconColor,
  }) async {
    return await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 32, 32, 40), // Increased bottom padding to 40
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon, 
                    size: 48,
                    color: iconColor ?? (isDestructive ? Colors.red : const Color(0xFF00796B)),
                  ),
                  const SizedBox(height: 24),
                ],
                Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
                const SizedBox(height: 16),
                Text(message, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.5)),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.grey),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(cancelText.toUpperCase(), style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w900, fontSize: 13)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: iconColor ?? (isDestructive ? Colors.red : const Color(0xFF00796B)),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(confirmText.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ) ?? false;
  }

  // --- OTHER MENU MODALS ---


  void _showChangePasswordModal() {
    final oldPass = TextEditingController();
    final newPass = TextEditingController();
    final confirmPass = TextEditingController();
    
    final FocusNode oldFocus = FocusNode();
    final FocusNode newFocus = FocusNode();
    final FocusNode confirmFocus = FocusNode();

    String? oldError;
    String? newError;
    String? confirmError;
    
    bool obscureOld = true;
    bool obscureNew = true;
    bool obscureConfirm = true;

    _showStyledBottomSheet(
      title: "Change Password",
      description: "Update your security credentials to keep your account safe.",
      loadingText: "Initializing security module...",
      bottomPadding: 32,
      children: [
        StatefulBuilder(builder: (context, setModalState) {
          // Inner validation functions
          Future<void> validateOld() async {
            final val = oldPass.text;
            if (val.isEmpty) {
              setModalState(() => oldError = "Current password is required");
              return;
            }
            try {
              final res = await _apiService.login(_user!.email, val);
              if (res.data['success'] != true) {
                setModalState(() => oldError = "Wrong password");
              } else {
                setModalState(() => oldError = null);
              }
            } catch (e) {
              setModalState(() => oldError = "Error verifying password");
            }
          }

          void validateNew() {
            final val = newPass.text;
            if (val.isEmpty) {
              setModalState(() => newError = AppLocalizations.get('err_pass_new'));
              return;
            }
            if (val.length < 6) {
              setModalState(() => newError = AppLocalizations.get('err_pass_len'));
              return;
            }
            bool hasUpper = val.contains(RegExp(r'[A-Z]'));
            bool hasLower = val.contains(RegExp(r'[a-z]'));
            bool hasDigit = val.contains(RegExp(r'[0-9]'));
            bool hasSpecial = val.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));

            if (!hasUpper || !hasLower || !hasDigit || !hasSpecial) {
              setModalState(() => newError = AppLocalizations.get('err_pass_complex'));
            } else {
              setModalState(() => newError = null);
            }
          }

          void validateConfirm() {
            if (confirmPass.text != newPass.text) {
              setModalState(() => confirmError = AppLocalizations.get('err_pass_match'));
            } else {
              setModalState(() => confirmError = null);
            }
          }

          // Real-time error clearing listeners
          if (!oldFocus.hasListeners) {
            oldPass.addListener(() {
              if (oldError != null && oldPass.text.isNotEmpty) {
                setModalState(() => oldError = null);
              }
            });
            newPass.addListener(() {
              if (newError != null) validateNew();
            });
            confirmPass.addListener(() {
              if (confirmError != null) validateConfirm();
            });

            oldFocus.addListener(() { if (mounted) setModalState((){}); if (!oldFocus.hasFocus) validateOld(); });
            newFocus.addListener(() { if (mounted) setModalState((){}); if (!newFocus.hasFocus) validateNew(); });
            confirmFocus.addListener(() { if (mounted) setModalState((){}); if (!confirmFocus.hasFocus) validateConfirm(); });
          }

          return Column(
            children: [
              const SizedBox(height: 8),
              _buildValidatedField(
                label: "Current Password",
                controller: oldPass, 
                focusNode: oldFocus, 
                error: oldError, 
                obscureText: obscureOld,
                prefixIcon: Icons.lock_outline_rounded,
                onToggle: () => setModalState(() => obscureOld = !obscureOld)
              ),
              const SizedBox(height: 10),
              _buildValidatedField(
                label: "New Password",
                controller: newPass, 
                focusNode: newFocus, 
                error: newError, 
                obscureText: obscureNew,
                prefixIcon: Icons.lock_reset_rounded,
                onToggle: () => setModalState(() => obscureNew = !obscureNew)
              ),
              const SizedBox(height: 10),
              _buildValidatedField(
                label: "Confirm New Password",
                controller: confirmPass, 
                focusNode: confirmFocus, 
                error: confirmError, 
                obscureText: obscureConfirm,
                prefixIcon: Icons.check_circle_outline_rounded,
                onToggle: () => setModalState(() => obscureConfirm = !obscureConfirm)
              ),
              const SizedBox(height: 24),
              HoverActionButton(
                text: "Save Changes",
                loadingText: "Saving Changes...",
                isLoading: _isLoading,
                onTap: () async {
                  await validateOld();
                  validateNew();
                  validateConfirm();

                  if (oldError != null || newError != null || confirmError != null) return;

                  bool confirm = await _showConfirmActionDialog(
                    title: "Change Password?",
                    message: "Are you sure you want to update your password? You will need to use your new password the next time you log in.",
                    confirmText: "Change Password"
                  );
                  if (!confirm) return;

                  setModalState(() => _isLoading = true);
                  setState(() => _isLoading = true);
                  
                  try {
                    final res = await _apiService.changePassword(_user!.userId, _user!.role, oldPass.text, newPass.text);
                    if (res.data['success'] == true) {
                      if (mounted) {
                        Navigator.pop(context);
                        CustomSnackBar.show(context, message: "Successful change password", isModal: true);
                      }
                    } else {
                      setModalState(() => oldError = res.data['message'] ?? "Password update failed.");
                      CustomSnackBar.show(context, message: res.data['message'] ?? "Password update failed.", isError: true, isModal: true);
                    }
                  } catch (e) {
                    CustomSnackBar.show(context, message: "Error: $e", isError: true, isModal: true);
                  } finally {
                    setModalState(() => _isLoading = false);
                    if (mounted) setState(() => _isLoading = false);
                  }
                },
              ),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildValidatedField({
    required String label, 
    required TextEditingController controller, 
    required FocusNode focusNode, 
    String? error, 
    Color? errorColor,
    required bool obscureText, 
    required VoidCallback onToggle,
    IconData? prefixIcon,
  }) {
    final bool isDesktop = Responsive.isDesktop(context);
    bool hasFocus = focusNode.hasFocus;
    bool isPassword = label.toLowerCase().contains("password");
    bool isError = error != null && (errorColor == null || errorColor == Colors.redAccent);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
        ),
        const SizedBox(height: 4),
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              if (hasFocus)
                BoxShadow(color: (isError ? Colors.redAccent : AppColors.tealText).withAlpha(30), blurRadius: 12, spreadRadius: 2)
            ],
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            obscureText: obscureText,
            cursorColor: const Color(0xFF424242),
            style: const TextStyle(fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              filled: true,
              fillColor: hasFocus ? Colors.white : const Color(0xFFF3F5F7),
              contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: isDesktop ? 18 : 14),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: isError ? Colors.redAccent : Colors.grey.shade200, width: 1.2)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: isError ? Colors.redAccent : AppColors.tealText, width: 2.0)),
              prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: hasFocus ? (isError ? Colors.redAccent : AppColors.tealText) : Colors.grey.shade400, size: 20) : null,
              suffixIcon: isPassword ? IconButton(icon: Icon(obscureText ? Icons.visibility_off : Icons.visibility, color: hasFocus ? (isError ? Colors.redAccent : AppColors.tealText) : Colors.grey.shade400, size: 20), onPressed: onToggle) : null,
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(error, style: TextStyle(color: errorColor ?? Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }

  void _showNotificationPreferences() {
    // Removed - Replaced with inline toggles in _buildNotificationsSection
  }

  void _showDailyRoutes() async {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);

    try {
      _showStyledBottomSheet(
        title: "Daily Routes",
        description: "View and track your assigned collection paths for the day.",
        loadingText: "Loading collection routes...",
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
                              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
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

  void _showAboutUsModal() {
    _showStyledBottomSheet(
      title: "About",
      loadingText: "Loading application details...",
      children: [
        const Center(child: Icon(Icons.local_shipping_rounded, size: 64, color: AppColors.tealText)),
        const SizedBox(height: 24),
        const Text(
          "Balintawak Waste Tracker is a comprehensive garbage truck tracking and management system designed to improve waste collection efficiency in our community.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF424242), fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 16),
        const Text(
          "Our mission is to provide residents with real-time updates and an easy way to communicate with waste management services, ensuring a cleaner and greener environment for everyone.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF424242), fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 32),
        const Text("Version 1.0.0", style: TextStyle(color: Colors.grey, fontSize: 12)),
        const Text("© 2026 Balintawak Waste Tracker Project Team", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 24),
      ],
    );
  }

  void _showPerformanceStats() {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);

    try {
      final truckId = _user?.preferredTruck ?? "Unknown";
      _showModal("Performance Stats", [
        StreamBuilder<DatabaseEvent>(
          stream: _database.ref('truck_locations/$truckId').onValue,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text("Error: ${snapshot.error}");
            if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
              return const Center(child: CircularProgressIndicator(color: AppColors.tealText));
            }
            final Map data = snapshot.data!.snapshot.value as Map;
            return Column(
              children: [
                _buildInfoRow("Collection Efficiency", "${(data['efficiency'] ?? 0.0).toStringAsFixed(1)}%", valueColor: AppColors.statusGreen),
                const SizedBox(height: 16),
                _buildInfoRow("Average Speed", "${(data['avg_speed'] ?? 0.0).toStringAsFixed(1)} km/h"),
                const SizedBox(height: 16),
                _buildInfoRow("Distance Covered", "${(data['distance'] ?? 0.0).toStringAsFixed(2)} km"),
              ],
            );
          }
        ),
      ], null, null, description: "Monitor your collection efficiency and vehicle performance metrics.", maxHeightMultiplier: 0.85);
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  void _showAlertHistory() {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);

    try {
      _showModal("Alert History", [
        StreamBuilder<DatabaseEvent>(
          stream: _database.ref('notifications').onValue,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text("Error: ${snapshot.error}");
            if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
              return const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Text("No alerts history found.", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))));
            }
            final Map data = snapshot.data!.snapshot.value as Map;
            final List alerts = [];
            data.forEach((k, v) { 
              final val = v as Map;
              final String type = (val['type'] ?? '').toString();
              final String? truckId = val['truck_id']?.toString() ?? val['truckId']?.toString();
              final String? targetUserId = val['targetUserId']?.toString() ?? val['userId']?.toString();
              final String? targetRole = val['targetRole']?.toString().toLowerCase();

              // 1. EXCLUDE Admin-only or Resident-focused types
              if (['REGISTRATION', 'NEW_REGISTRATION', 'RESIDENT_COMPLAINT', 'COLLECTION_ALERT', 'manual_alert', 'auto_arrival', 'auto_approach', 'COMPLAINT_RESOLVED'].contains(type)) {
                return;
              }

              bool isRelevant = false;
              
              // 2. TARGETED: Explicitly for this User ID
              if (targetUserId != null && targetUserId == _user?.userId.toString()) {
                isRelevant = true;
              }

              // 3. ROLE-BASED: Targeted to all drivers or this specific driver role
              if (targetRole == 'driver') {
                if (truckId == null || truckId.isEmpty || truckId == _user?.preferredTruck) {
                  isRelevant = true;
                }
              }

              // 4. TRUCK-BASED: Relevant to the assigned truck (e.g., ISSUE_UPDATE, MAINTENANCE)
              if (truckId != null && truckId.isNotEmpty && truckId == _user?.preferredTruck) {
                 isRelevant = true; 
              }

              if (isRelevant) alerts.add(val);
            });
            
            if (alerts.isEmpty) {
              return const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Text("No alerts history found.", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))));
            }

            alerts.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: alerts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final a = alerts[i];
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a['title'] ?? "Alert", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(a['message'] ?? "", style: const TextStyle(fontSize: 13, color: Colors.grey)),
                    ],
                  ),
                );
              },
            );
          },
        )
      ], null, null, description: "Track the status and resolution of your recently received notifications.");
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  // --- HANDLERS ---

  void _showLanguageModal() {
    _showStyledBottomSheet(
      title: "Language Selection",
      description: "Select your preferred language for the application.",
      loadingText: "Fetching language preferences...",
      children: [
        _buildLanguageItem("English", AppLanguage.en),
        _buildLanguageItem("Filipino", AppLanguage.fil),
        _buildLanguageItem("Bisaya", AppLanguage.bis),
      ],
    );
  }

  Widget _buildLanguageItem(String label, AppLanguage lang) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double fontSize = (screenWidth * 0.04).clamp(14.0, 16.0);

    bool isSelected = AppLocalizations.currentLanguage.value == lang;
    return ListTile(
      title: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: const Color(0xFF1A1A1A), fontSize: fontSize)),
      leading: Icon(Icons.language_rounded, color: isSelected ? AppColors.tealText : Colors.grey),
      trailing: isSelected 
        ? Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(color: Color(0xFF00897B), shape: BoxShape.circle),
            child: const Icon(Icons.check, color: Colors.white, size: 14),
          )
        : null,
      onTap: () async {
        final nav = Navigator.of(context);
        await AppLocalizations.setLanguage(lang);
        if (mounted) setState(() {});
        nav.pop();
      },
    );
  }

  void _showFAQsModal() {
    _showStyledBottomSheet(
      title: "FAQs",
      description: "Find answers to frequently asked questions.",
      loadingText: "Loading help center...",
      maxHeightMultiplier: 0.85,
      children: [
        _buildFAQItem("How do I update my route status?", "Use the controls on your main dashboard: 'START' to begin, 'PAUSE' if you are idle, 'FULL' when the truck is at capacity, and 'DONE' when the route is finished."),
        _buildFAQItem("What if I encounter a vehicle issue?", "Go to the 'Truck Information' section in settings and use 'Report Issue' to notify the admin about vehicle problems."),
        _buildFAQItem("How is my performance calculated?", "The system tracks your route completion time, fuel efficiency (if logged), and feedback from the community."),
        _buildFAQItem("Can I change my assigned truck?", "Truck assignments are managed by the administrator. Contact support if you need to be reassigned to a different vehicle."),
        _buildFAQItem("How do I update my personal data?", "Tap the 'Edit' button in your profile section above to update your name, email, or contact number."),
      ],
    );
  }

  Widget _buildFAQItem(String q, String a) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double qFontSize = (screenWidth * 0.04).clamp(14.0, 15.0);
    final double aFontSize = (screenWidth * 0.035).clamp(13.0, 14.0);

    return ExpansionTile(
      shape: const RoundedRectangleBorder(side: BorderSide.none),
      collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
      title: Text(q, style: TextStyle(fontWeight: FontWeight.w800, fontSize: qFontSize, color: const Color(0xFF1A1A1A))),
      iconColor: AppColors.tealText,
      collapsedIconColor: Colors.grey,
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        Text(a, style: TextStyle(color: Colors.grey.shade700, height: 1.5, fontSize: aFontSize, fontWeight: FontWeight.w500)),
      ],
    );
  }

  void _showContactSupportModal() {
    _showStyledBottomSheet(
      title: "Contact Support",
      description: "Reach out to us if you need help or have any inquiries.",
      loadingText: "Connecting to support services...",
      children: [
        const SizedBox(height: 8),
        _buildContactDetailRow(Icons.phone_rounded, "+63 912 345 6789"),
        const SizedBox(height: 16),
        _buildContactDetailRow(Icons.email_rounded, "support@garbagetracker.com"),
        const SizedBox(height: 16),
        _buildContactDetailRow(Icons.map_rounded, "Barangay Hall, Purok 2, City Center"),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildContactDetailRow(IconData icon, String value) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double fontSize = (screenWidth * 0.04).clamp(14.0, 15.0);

    return Row(
      children: [
        Icon(icon, size: 22, color: Colors.black87),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: Colors.black87),
          ),
        ),
      ],
    );
  }

  void _showDataManagementModal() {
    if (_user == null) return;
    _showStyledBottomSheet(
      title: "Edit Account",
      description: "Update your profile details and account settings here.",
      maxHeightMultiplier: 0.9,
      loadingText: "Preparing account editor...",
      bottomPadding: 32,
      children: [
        DataManagementModal(user: _user!, onSuccess: _loadUser),
      ],
    );
  }

  Future<bool> _handleUpdateProfile({
    required String name,
    required String username,
    required String email,
    required String phone,
    required String truck,
  }) async {
    setState(() => _isNavigating = true);
    try {
      final res = await _apiService.updateProfile(
        userId: _user!.userId,
        role: _user!.role,
        name: name,
        username: username,
        phone: phone,
        email: email,
        preferredTruck: truck,
        address: _user!.completeAddress,
      );

      if (res.data['success'] == true) {
        // Update Firebase user node for real-time sync
        await _database.ref('users/${_user!.userId}').update({
          'name': name,
          'username': username,
          'email': email,
          'phone': phone,
          'preferred_truck': truck,
          'lastUpdated': ServerValue.timestamp,
        });

        final updatedUser = _user!.copyWith(
          name: name,
          username: username,
          phone: phone,
          email: email,
          preferredTruck: truck,
        );
        await SessionManager.saveUser(updatedUser.toJson());
        
        if (mounted) {
          setState(() {
            _user = updatedUser;
          });
          _setupTruckListener(); // Restart truck listener in case it changed
        }
        return true;
      } else {
        CustomNotification.showTopNotification(context, res.data['message'] ?? "Update failed");
        return false;
      }
    } catch (e) {
      CustomNotification.showTopNotification(context, "Error updating profile: $e");
      return false;
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }


  void _showDeleteAccountConfirmation() async {
    bool confirmed = await _showConfirmActionDialog(
      title: "Delete Account?",
      message: "You will lose all access and your account data will be permanently removed.",
      confirmText: "Delete",
      cancelText: "No",
      isDestructive: true,
      icon: Icons.no_accounts_rounded,
    );
    if (confirmed) {
      setState(() => _isNavigating = true);
      try {
        final res = await _apiService.deleteUser(_user!.userId, _user!.role);
        if (res.data['success'] == true) {
           await SessionManager.logout();
           if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
        }
      } catch (e) {
        CustomNotification.showTopNotification(context, "Delete failed: $e");
      } finally {
        if (mounted) setState(() => _isNavigating = false);
      }
    }
  }



  // --- UI UTILS ---

  void _showStyledBottomSheet({
    String title = "", 
    Widget? titleWidget,
    required List<Widget> children, 
    String? description, 
    Widget? descriptionWidget,
    double maxHeightMultiplier = 0.6,
    String loadingText = "Loading details...",
    double bottomPadding = 20.0,
  }) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double titleFontSize = (screenWidth * 0.055).clamp(18.0, 22.0);
    final double descFontSize = (screenWidth * 0.035).clamp(11.0, 13.0);
    bool isModalLoading = true;

    if (Responsive.isDesktop(context) || Responsive.isTablet(context)) {
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
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOutCubic,
                constraints: BoxConstraints(
                  maxWidth: 550, 
                  maxHeight: isModalLoading ? 300 : MediaQuery.of(context).size.height * 0.85
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                              child: titleWidget ?? Text(title,
                                  style: TextStyle(
                                      fontSize: titleFontSize, fontWeight: FontWeight.w900, color: AppColors.tealText))),
                          IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded, color: Colors.grey)),
                        ],
                      ),
                    ),
                    if ((description != null && description.isNotEmpty) || descriptionWidget != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: descriptionWidget ?? Text(description ?? "",
                              textAlign: TextAlign.left,
                              style: TextStyle(fontSize: descFontSize, color: Colors.grey, fontWeight: FontWeight.w500)),
                        ),
                      ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 32, vertical: 8),
                      child: Divider(height: 1, color: Color(0xFFEEEEEE)),
                    ),
                    if (isModalLoading)
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(color: AppColors.tealText, strokeWidth: 3),
                              const SizedBox(height: 16),
                              Text(loadingText, style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(32, 0, 32, bottomPadding),
                          child: Column(mainAxisSize: MainAxisSize.min, children: children),
                        ),
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
            Future.delayed(const Duration(milliseconds: 800), () {
              if (mounted) setModalState(() => isModalLoading = false);
            });
          }

          return AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOutCubic,
            clipBehavior: Clip.antiAlias,
            constraints: BoxConstraints(
              maxHeight: isModalLoading 
                  ? 380 
                  : MediaQuery.of(context).size.height * maxHeightMultiplier
            ),
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
                    children: [
                      Expanded(child: titleWidget ?? Text(title, style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.w900, color: AppColors.tealText))),
                    ],
                  ),
                ),
                if ((description != null && description.isNotEmpty) || descriptionWidget != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: descriptionWidget ?? Text(
                        description ?? "",
                        textAlign: TextAlign.left,
                        style: TextStyle(fontSize: descFontSize, color: Colors.grey, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1, color: Color(0xFFEEEEEE)),
                ),
                if (isModalLoading)
                  Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(color: AppColors.tealText, strokeWidth: 3),
                          const SizedBox(height: 16),
                          Text(loadingText, style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Scrollbar(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: EdgeInsets.only(bottom: bottomPadding),
                          child: Column(mainAxisSize: MainAxisSize.min, children: children),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showModal(String title, List<Widget> body, String? btnText, Future<bool> Function()? onBtnTap, {String loadingText = "Saving changes...", String? description, String? successMessage, double maxHeightMultiplier = 0.6}) async {
    _showStyledBottomSheet(
      title: title,
      description: description,
      maxHeightMultiplier: maxHeightMultiplier,
      loadingText: title.contains("Truck") || title.contains("Performance") ? "Fetching vehicle info..." : (title.contains("Alert") ? "Loading history..." : "Preparing data..."),
      bottomPadding: 20.0,
      children: [
        ...body,
        if (btnText != null) ...[
          const SizedBox(height: 12),
          StatefulBuilder(builder: (modalCtx, setModalState) {
            bool isModalLoading = false;
            return StatefulBuilder(builder: (innerCtx, setInnerState) {
              return HoverActionButton(
                text: btnText,
                loadingText: loadingText,
                isLoading: isModalLoading,
                useZoom: true,
                onTap: isModalLoading ? null : () async {
                  // Capture the navigator before any await
                  final navigator = Navigator.of(innerCtx);
                  
                    bool confirmed = await _showConfirmActionDialog(
                    title: title.contains("Report") ? "Submit Report?" : "Save Changes?",
                    message: title.contains("Report") 
                      ? "Are you sure you want to submit this issue report?" 
                      : "Are you sure you want to proceed with these updates?",
                    confirmText: title.contains("Report") ? "Yes, Submit" : "Yes, Save",
                  );

                  if (confirmed && onBtnTap != null) {
                    setInnerState(() => isModalLoading = true);
                    try {
                      bool success = await onBtnTap();
                      if (mounted) {
                        setInnerState(() => isModalLoading = false);
                        if (success) {
                          // Small delay to ensure previous dialog transitions are settled
                          await Future.delayed(const Duration(milliseconds: 200));
                          if (navigator.canPop()) {
                            navigator.pop();
                          }
                          
                          if (successMessage != null) {
                            CustomNotification.showTopNotification(context, successMessage, false);
                          } else {
                            // NEW: Show top notification instead of modal
                            CustomNotification.showTopNotification(
                              context, 
                              title.contains("Report") 
                                ? "Your truck issue has been successfully reported." 
                                : "Changes have been saved successfully.",
                              false
                            );
                          }
                        } else {
                          // NEW: Show top notification instead of modal
                          CustomNotification.showTopNotification(
                            context, 
                            "The action could not be completed. Please try again.",
                            true
                          );
                        }
                      }
                    } catch (e) {
                      if (mounted) {
                        setInnerState(() => isModalLoading = false);
                        debugPrint("Modal Action Error: $e");
                        
                        CustomNotification.showTopNotification(
                          context, 
                          "Unable to complete action due to a connection error.",
                          true
                        );
                      }
                    }
                  }
                },
              );
            });
          }),
        ],
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

  Widget _buildToggle(String label, bool value, Function(bool) onChanged) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double fontSize = (screenWidth * 0.04).clamp(13.0, 15.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: fontSize)),
          Switch(
            value: value, 
            onChanged: (v) { onChanged(v); setState(() {}); }, 
            activeThumbColor: AppColors.tealText
          ),
        ],
      ),
    );
  }

  void _showResultDialog({required bool success, required String message}) {
    if (!mounted) return;
    final double screenWidth = MediaQuery.of(context).size.width;
    final double titleFontSize = (screenWidth * 0.055).clamp(18.0, 22.0);
    final double messageFontSize = (screenWidth * 0.04).clamp(13.0, 15.0);

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: (success ? AppColors.statusGreen : Colors.redAccent).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  success ? Icons.check_circle_rounded : Icons.error_rounded, 
                  color: success ? AppColors.statusGreen : Colors.redAccent, 
                  size: 48
                ),
              ),
              const SizedBox(height: 24),
              Text(
                success ? "Success!" : "Action Failed", 
                style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.w900, color: const Color(0xFF1A1A1A))
              ),
              const SizedBox(height: 16),
              Text(
                message, 
                textAlign: TextAlign.center, 
                style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500, fontSize: messageFontSize, height: 1.5)
              ),
              const SizedBox(height: 32),
              HoverActionButton(
                text: "DONE",
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) async {
    final bool isDesktop = Responsive.isDesktop(context);
    final Color themeColor = isDesktop ? Colors.red : AppColors.tealText;

    bool confirmed = await _showConfirmActionDialog(
      title: "Logout?",
      message: "Are you sure you want to end your current session?",
      confirmText: "Logout",
      cancelText: "CANCEL",
      isDestructive: false,
      icon: Icons.logout_rounded,
      iconColor: themeColor,
    );
    if (confirmed) {
      if (!mounted) return;
      
      // 1. Show immediate loading feedback
      setState(() => _isNavigating = true);
      final navigator = Navigator.of(context);
      
      try {
        // 2. Resolve User and run Firebase update + logout in PARALLEL
        final user = await SessionManager.getUser();
        final String? truckId = user?.preferredTruck;

        await Future.wait([
          if (truckId != null)
            FirebaseDatabase.instance.ref('truck_locations/$truckId').update({
              'status': 'OFFLINE',
              'isOnline': false,
              'lastSeen': ServerValue.timestamp
            }).timeout(const Duration(seconds: 2), onTimeout: () => debugPrint("Settings logout update timed out")),
          SessionManager.logout(),
        ]);

        if (mounted) {
          CustomNotification.showTopNotification(context, "Logout successful.", false);
          navigator.pushReplacementNamed('/');
        }
      } catch (e) {
        debugPrint("Logout error: $e");
        await SessionManager.logout();
        if (mounted) navigator.pushReplacementNamed('/');
      } finally {
        if (mounted) setState(() => _isNavigating = false);
      }
    }
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
