import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/session_manager.dart';
import '../api/api_service.dart';
import '../api/api_client.dart';
import '../utils/custom_notification.dart';
import '../utils/system_logger.dart';
import '../services/admin_settings_service.dart';
import '../services/notification_service.dart';
import '../utils/app_localizations.dart';
import '../utils/app_theme.dart';
import '../utils/responsive.dart';
import '../models/user.dart';
import '../widgets/hover_action_button.dart';
import '../widgets/fade_slide_entrance.dart';
import '../widgets/legal_agreement_dialog.dart';
import '../widgets/data_management_modal.dart';
import '../widgets/custom_snackbar.dart';

class AdminSettingsScreen extends StatefulWidget {
  final bool isEmbedded;
  final VoidCallback? onBack;
  const AdminSettingsScreen({super.key, this.isEmbedded = false, this.onBack});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> with TickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  final AdminSettingsService _adminSettingsService = AdminSettingsService();
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final ScrollController _scrollController = ScrollController();
  UserData? _user;

  bool _emailNotifications = true;
  bool _appNotifications = true;
  bool _autoBackup = true;
  
  String _adminName = "Administrator";
  String _adminEmail = "Loading...";

  bool _isRefreshing = false;
  bool _showRefreshSpinner = false;
  bool _isLoading = false;
  double _manualPullDepth = 0.0;
  late AnimationController _refreshRotationController;

  bool _isPasswordLoading = false;
  bool _isCurrentPasswordVisible = false;
  bool _isNewPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  bool _showHeaderShadow = true;

  @override
  void dispose() {
    _scrollController.dispose();
    _refreshRotationController.dispose();
    super.dispose();
  }

  final FocusNode usernameFocus = FocusNode();
  final FocusNode nameFocus = FocusNode();
  final FocusNode emailFocus = FocusNode();
  final FocusNode phoneFocus = FocusNode();

  @override
  void initState() {
    super.initState();

    // Add listeners for focus color changes
    usernameFocus.addListener(() { if (mounted) setState(() {}); });
    nameFocus.addListener(() { if (mounted) setState(() {}); });
    emailFocus.addListener(() { if (mounted) setState(() {}); });
    phoneFocus.addListener(() { if (mounted) setState(() {}); });

    // Add listeners for focus color changes
    usernameFocus.addListener(() { if (mounted) setState(() {}); });
    nameFocus.addListener(() { if (mounted) setState(() {}); });
    emailFocus.addListener(() { if (mounted) setState(() {}); });
    phoneFocus.addListener(() { if (mounted) setState(() {}); });

    _refreshRotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _adminSettingsService.startListening();
    _setupGlobalSettingsListeners();
    _loadUser();
    _loadSettings();
    _scrollController.addListener(() {
      if (_scrollController.offset <= 0 && !_showHeaderShadow) {
        setState(() => _showHeaderShadow = true);
      } else if (_scrollController.offset > 0 && _showHeaderShadow) {
        setState(() => _showHeaderShadow = false);
      }
    });
  }

  void _loadUser() async {
    _user = await SessionManager.getUser();
    if (_user != null) {
      if (mounted) {
        setState(() {
          _adminName = _user!.name.isNotEmpty ? _user!.name : "System Admin";
          _adminEmail = _user!.email.isNotEmpty ? _user!.email : "No Email Provided";
        });
      }
      _setupUserListener();
    }
  }

  void _setupUserListener() {
    if (_user == null) return;
    _database.ref('users/${_user!.userId}').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map data = event.snapshot.value as Map;
        if (mounted) {
          setState(() {
            final Map<String, dynamic> currentData = _user!.toJson();
            data.forEach((k, v) => currentData[k] = v);
            _user = UserData.fromJson(currentData);
            _adminName = _user!.name;
            _adminEmail = _user!.email;
          });
        }
      }
    });
  }

  void _setupGlobalSettingsListeners() {
    _adminSettingsService.emailNotificationsEnabled.addListener(() {
      if (mounted) setState(() => _emailNotifications = _adminSettingsService.emailNotificationsEnabled.value);
    });
    _adminSettingsService.appNotificationsEnabled.addListener(() {
      if (mounted) {
        setState(() => _appNotifications = _adminSettingsService.appNotificationsEnabled.value);
        SessionManager.setAppNotificationsEnabled(_appNotifications);
      }
    });
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
      _loadSettings(),
      Future.delayed(const Duration(milliseconds: 1500)),
    ]);

    if (manual) {
      await Future.delayed(const Duration(seconds: 2));
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
      }
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
                        "Settings synchronized",
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
  }

  Future<void> _loadSettings() async {
    try {
      final user = await SessionManager.getUser();
      if (user != null) {
        // SYNC: Ensure we respect the system-level permission choice
        final bool systemEnabled = await SessionManager.isAppNotificationsEnabled();

        final response = await _apiService.getUserSettings(user.userId, user.role);
        final resData = response.data;
        if (resData is Map && resData['success'] == true) {
          final data = resData['data'];
          if (mounted) {
            setState(() {
              _emailNotifications = data['email_notifications'] ?? true;
              _appNotifications = systemEnabled && (data['app_notifications'] ?? true);
              _autoBackup = data['auto_backup'] ?? true;
            });
            SessionManager.setAppNotificationsEnabled(_appNotifications);
          }
        }
      }
    } catch (e) {
      debugPrint("Error loading admin settings: $e");
    }
  }

  Future<void> _toggleSetting(String key, bool value) async {
    if (key == 'email') {
      await _adminSettingsService.updateEmailNotifications(value);
    } else if (key == 'app') {
      await _adminSettingsService.updateAppNotifications(value);
    } else if (key == 'backup') {
      await _database.ref('admin_settings/auto_backup').set(value);
    }

    setState(() {
      if (key == 'email') _emailNotifications = value;
      if (key == 'app') {
        _appNotifications = value;
        SessionManager.setAppNotificationsEnabled(value);
      }
      if (key == 'backup') _autoBackup = value;
    });

    try {
      final user = await SessionManager.getUser();
      if (user != null) {
        final response = await _apiService.updateUserSettings(
          userId: user.userId,
          role: user.role,
          emailNotifications: key == 'email' ? value : null,
          appNotifications: key == 'app' ? value : null,
          autoBackup: key == 'backup' ? value : null,
        );
        
        final data = response.data;
        if (data is Map && data['success'] == true) {
          if (mounted) {
            if (key == 'app' && !kIsWeb) {
               PermissionStatus status = await Permission.notification.status;
               if (!value && status.isGranted) {
                  CustomNotification.showTopNotification(context, "Redirecting to system settings to disable permissions...", false);
                  await Future.delayed(const Duration(seconds: 1));
                  await openAppSettings();
               } else if (value && !status.isGranted) {
                  CustomNotification.showTopNotification(context, "Permissions are required to enable alerts.", true);
                  await Future.delayed(const Duration(seconds: 1));
                  await openAppSettings();
               } else {
                  CustomNotification.showTopNotification(context, "App Notifications ${value ? 'Enabled' : 'Disabled'}", false);
               }
            } else {
               final String status = value ? "Enabled" : "Disabled";
               final String settingName = key == 'email' ? "Email Notifications" : (key == 'app' ? "App Notifications" : "Auto Backup");
               CustomNotification.showTopNotification(context, "$settingName $status", false);
            }
          }
        } else {
          if (mounted) {
            setState(() {
              if (key == 'email') _emailNotifications = !value;
              if (key == 'app') _appNotifications = !value;
              if (key == 'backup') _autoBackup = !value;
            });
            String msg = (data is Map) ? (data['message'] ?? "Failed to update setting") : "Server error";
            CustomNotification.showTopNotification(context, msg);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (key == 'email') _emailNotifications = !value;
          if (key == 'app') _appNotifications = !value;
        });
        CustomNotification.showTopNotification(context, "Error updating setting: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: FadeSlideEntrance(
        child: SafeArea(
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

                                      _buildSectionHeader(Icons.notifications_rounded, "System Notifications"),
                                      _buildNotificationSection(),
                                      const SizedBox(height: 24),

                                      _buildSectionHeader(Icons.storage_rounded, "Data Management"),
                                      _buildDataManagementSection(),
                                      const SizedBox(height: 24),

                                      _buildSectionHeader(Icons.security_rounded, "Security"),
                                      _buildSecuritySection(),
                                      const SizedBox(height: 24),

                                      _buildSectionHeader(Icons.help_outline_rounded, "Support & Legal"),
                                      _buildSupportLegalSection(),
                                      const SizedBox(height: 24),

                                      _buildSectionHeader(Icons.info_outline_rounded, "App Information"),
                                      _buildAppInformation(),
                                      const SizedBox(height: 32),
                                      
                                      _buildLogoutButton(),
                                      const SizedBox(height: 12),
                                      _buildDeleteAccountButton(),
                                      const SizedBox(height: 40),
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
        ),
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
              child: const Icon(Icons.settings_suggest_rounded, color: Color(0xFF00796B), size: 28),
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
                Text("Manage system settings and administrator preferences.",
                    style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
              ],
            ),
            const Spacer(),
          ],
        ),
      );
    }

    final double titleFontSize = (screenWidth * 0.055).clamp(18.0, 22.0);
    final double subtitleFontSize = (screenWidth * 0.03).clamp(10.0, 12.0);
    final double iconContainerSize = (screenWidth * 0.12).clamp(40.0, 48.0);
    final double iconSize = (screenWidth * 0.06).clamp(20.0, 24.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
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
          _buildCircularBackButton(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Account Settings", style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.w900, color: const Color(0xFF1A1A1A), letterSpacing: -0.5)),
                Text("Admin preferences", style: TextStyle(fontSize: subtitleFontSize, color: const Color(0xFF757575), fontWeight: FontWeight.w600)),
              ],

            ),
          ),
          Container(
            width: iconContainerSize,
            height: iconContainerSize,
            decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.settings_suggest_rounded, color: Color(0xFF00796B), size: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildCircularBackButton() {
    final bool isMobile = MediaQuery.of(context).size.width < 900;
    return GestureDetector(
      onTap: () {
        if (isMobile) {
          Scaffold.of(context).openDrawer();
        } else if (widget.onBack != null) {
          widget.onBack!();
        } else {
          Navigator.pop(context);
        }
      },
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Icon(
          isMobile ? Icons.menu_rounded : Icons.arrow_back_ios_new_rounded,
          color: const Color(0xFF1A1A1A),
          size: isMobile ? 22 : 18,
        ),
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title, {Widget? trailing}) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double headerFontSize = (screenWidth * 0.035).clamp(11.0, 13.0);
    final double iconSize = (screenWidth * 0.045).clamp(16.0, 18.0);

    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: iconSize, color: const Color(0xFF00796B)),
          const SizedBox(width: 8),
          Expanded(
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
          if (trailing != null) trailing,
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
        _buildSectionContainer(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          children: [
            _buildProfileRow("Admin Name", _adminName, labelFontSize: labelFontSize, valueFontSize: valueFontSize),
            const Divider(height: 32, thickness: 0.5),
            _buildProfileRow("Email Address", _adminEmail, labelFontSize: labelFontSize, valueFontSize: valueFontSize),
            const Divider(height: 32, thickness: 0.5),
            _buildProfileRow("Account Role", "System Administrator", labelFontSize: labelFontSize, valueFontSize: valueFontSize),
          ],
        ),
        Positioned(
          top: 16,
          right: 16,
          child: _HoverZoomLink(
            onTap: () => _showDataManagementModal(),
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
    final String displayName = _adminName;
    final String? profileUrl = _user?.profilePicture;
    final double screenWidth = MediaQuery.of(context).size.width;
    final double picSize = (screenWidth * 0.2).clamp(64.0, 80.0);

    return _buildSectionContainer(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
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
                              displayName.isNotEmpty ? displayName[0].toUpperCase() : "A",
                              style: TextStyle(fontSize: picSize * 0.4, fontWeight: FontWeight.bold, color: const Color(0xFF00695C)),
                            ),
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
                  Text("Profile Photo", style: TextStyle(fontSize: (screenWidth * 0.04).clamp(14.0, 16.0), fontWeight: FontWeight.w800, color: const Color(0xFF2C3E50))),
                  const SizedBox(height: 4),
                  Text(
                    "Update your administrator photo",
                    style: TextStyle(fontSize: (screenWidth * 0.03).clamp(10.0, 12.0), color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildCompactActionBtn(
                        label: "Upload",
                        icon: Icons.camera_alt_rounded,
                        onTap: _showUploadOptions,
                        color: const Color(0xFF00796B),
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
      ],
    );
  }

  Widget _buildCompactActionBtn({required String label, required IconData icon, required VoidCallback onTap, required Color color}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
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
                    tag: 'admin_settings_pic',
                    child: Container(
                      width: 300, height: 300,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                        image: profileUrl.isNotEmpty ? DecorationImage(image: NetworkImage(profileUrl), fit: BoxFit.cover) : null,
                      ),
                      child: profileUrl.isEmpty
                          ? Center(child: Text(_adminName.isNotEmpty ? _adminName[0].toUpperCase() : "A", style: const TextStyle(fontSize: 80, fontWeight: FontWeight.bold, color: Colors.white)))
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

  void _showUploadOptions() {
    _showStyledBottomSheet(
      title: "Upload Photo",
      description: "Choose how you want to upload your profile picture.",
      children: [
        _buildUploadOptionItem(icon: Icons.photo_library_rounded, label: "Choose from Gallery", onTap: () { Navigator.pop(context); _handleImageSelection(ImageSource.gallery); }),
        const SizedBox(height: 12),
        _buildUploadOptionItem(icon: Icons.camera_enhance_rounded, label: "Take a Photo", onTap: () { Navigator.pop(context); _handleImageSelection(ImageSource.camera); }),
      ],
    );
  }

  Widget _buildUploadOptionItem({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade100)),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF00796B)),
            const SizedBox(width: 16),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Future<void> _handleImageSelection(ImageSource source) async {
    if (_user == null) return;
    final picker = ImagePicker();
    final image = await picker.pickImage(source: source);
    if (image == null) return;
    setState(() => _isLoading = true);
    try {
      final bytes = await image.readAsBytes();
      final res = await _apiService.uploadProfilePicture(userId: _user!.userId, role: _user!.role, fileName: image.name, imageBytes: bytes.toList());
      if (res.data['success'] == true) {
        final String profileUrl = res.data['url'];
        await _database.ref('users/${_user!.userId}').update({'profile_picture': profileUrl});
        final updatedUser = {..._user!.toJson(), 'profile_picture': profileUrl};
        await SessionManager.saveUser(updatedUser);
        _loadUser();
        if (mounted) CustomNotification.showTopNotification(context, "Profile picture updated.", false);
      }
    } catch (e) {
      if (mounted) CustomNotification.showTopNotification(context, "Upload failed: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _confirmDeletePicture() async {
    bool confirmed = await _showConfirmActionDialog(title: "Delete Photo?", message: "Remove your profile picture?", confirmText: "Delete", isDestructive: true);
    if (confirmed) {
      setState(() => _isLoading = true);
      try {
        await _database.ref('users/${_user!.userId}').update({'profile_picture': null});
        await _apiService.updateProfile(userId: _user!.userId, role: _user!.role, name: _user!.name, phone: _user!.phone ?? "", email: _user!.email, address: _user!.completeAddress ?? "", profilePicture: "");
        final updatedUser = {..._user!.toJson()};
        updatedUser.remove('profile_picture');
        await SessionManager.saveUser(updatedUser);
        _loadUser();
        if (mounted) CustomNotification.showTopNotification(context, "Profile photo removed.", false);
      } catch (e) {
        if (mounted) CustomNotification.showTopNotification(context, "Failed to delete: $e");
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildProfileRow(String label, String value, {double? labelFontSize, double? valueFontSize}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: labelFontSize ?? 11, color: Colors.grey.shade600, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: valueFontSize ?? 16, color: const Color(0xFF2C3E50))),
      ],
    );
  }

  Widget _buildNotificationSection() {
    return _buildSectionContainer(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildToggleRow("Email Notifications", "Receive system alerts via email", _emailNotifications, (v) => _toggleSetting('email', v)),
        _buildDivider(),
        _buildToggleRow("App Notifications", "Direct push notifications", _appNotifications, (v) => _toggleSetting('app', v)),
      ],
    );
  }

  Widget _buildToggleRow(String label, String subtitle, bool value, Function(bool) onChanged) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double fontSize = (screenWidth * 0.04).clamp(14.0, 16.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: fontSize, color: const Color(0xFF2C3E50))),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          Transform.scale(
            scale: 0.9,
            child: Switch(
              value: value, 
              onChanged: onChanged, 
              activeColor: const Color(0xFF00796B),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataManagementSection() {
    return _buildSectionContainer(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildToggleRow("Automatic Backup", "Daily system maintenance snapshots", _autoBackup, (v) => _toggleSetting('backup', v)),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          child: Column(
            children: [
              _buildDataActionTile(
                title: "Backup System Now",
                subtitle: "Create a manual database snapshot",
                icon: Icons.backup_rounded,
                color: const Color(0xFF1E88E5),
                onTap: () async {
                  bool confirm = await _showConfirmActionDialog(
                    title: "Trigger Backup?",
                    message: "This will create a full snapshot of the system database. Continue?",
                    confirmText: "BACKUP NOW"
                  );
                  if (confirm) _handleManualBackup();
                },
                trailing: _HoverZoomLink(
                  onTap: () => _showBackupHistoryDialog(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
                    ),
                    child: const Text("HISTORY", style: TextStyle(color: Color(0xFF1E88E5), fontWeight: FontWeight.w900, fontSize: 9, letterSpacing: 0.5)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildDataActionTile(
                title: "Export System Data",
                subtitle: "Download all reports in Excel format",
                icon: Icons.ios_share_rounded,
                color: const Color(0xFF9C27B0),
                onTap: () async {
                  bool confirm = await _showConfirmActionDialog(
                    title: "Export Data?",
                    message: "Generate and download the latest system performance reports?",
                    confirmText: "GENERATE"
                  );
                  if (confirm) _handleExportData();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDataActionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.12), width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: color.withOpacity(0.85))),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            if (trailing != null) trailing else Icon(Icons.arrow_forward_ios_rounded, size: 12, color: color.withOpacity(0.3)),
          ],
        ),
      ),
    );
  }

  Widget _buildSecuritySection() {
    return _buildSectionContainer(
      children: [
        _buildMenuAction(Icons.password_rounded, "Change Password", () => _showChangePasswordDialog(context)),
        _buildDivider(),
        _buildMenuAction(Icons.verified_user_rounded, "Two-Factor Auth", () => _show2FADialog(context)),
        _buildDivider(),
        _buildMenuAction(Icons.list_alt_rounded, "Access Logs", () => _showAccessLogsDialog(context)),
        _buildDivider(),
        _buildMenuAction(Icons.admin_panel_settings_rounded, "Permissions", () => _showPermissionsDialog(context)),
      ],
    );
  }

  Widget _buildSupportLegalSection() {
    return _buildSectionContainer(
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
        _buildMenuAction(Icons.info_rounded, "About Us", () => _showAboutModal()),
      ],
    );
  }

  void _showLanguageModal() {
    bool isModalLoading = true;
    _showStyledBottomSheet(
      title: "Language Selection",
      description: "Select your preferred language for the application.",
      children: [
        StatefulBuilder(builder: (ctx, setModalState) {
          if (isModalLoading) {
            Future.delayed(const Duration(milliseconds: 800), () {
              if (mounted) setModalState(() => isModalLoading = false);
            });
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(60),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: AppColors.tealText),
                    const SizedBox(height: 16),
                    Text("Loading language settings...", style: TextStyle(color: Colors.grey.shade600, fontSize: 14, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            );
          }
          return Column(
            children: [
              _buildLanguageItem("English", AppLanguage.en),
              _buildLanguageItem("Filipino", AppLanguage.fil),
              _buildLanguageItem("Bisaya", AppLanguage.bis),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildLanguageItem(String label, AppLanguage lang) {
    bool isSelected = AppLocalizations.currentLanguage.value == lang;
    return ListTile(
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      leading: Icon(Icons.language_rounded, color: isSelected ? const Color(0xFF00796B) : Colors.grey),
      trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: Color(0xFF00796B)) : null,
      onTap: () async { 
        await AppLocalizations.setLanguage(lang); 
        if (mounted) {
          Navigator.pop(context); 
          CustomNotification.showTopNotification(
            context, 
            "Successfully changed language to $label.", 
            false
          );
        }
      },
    );
  }

  void _showFAQsModal() {
    bool isModalLoading = true;
    _showStyledBottomSheet(
      title: "Admin FAQs",
      description: "Find answers to frequently asked administrative questions.",
      maxHeightMultiplier: 0.85,
      children: [
        StatefulBuilder(builder: (ctx, setModalState) {
          if (isModalLoading) {
            Future.delayed(const Duration(milliseconds: 800), () {
              if (mounted) setModalState(() => isModalLoading = false);
            });
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(60),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: AppColors.tealText),
                    const SizedBox(height: 16),
                    Text("Loading common questions...", style: TextStyle(color: Colors.grey.shade600, fontSize: 14, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            );
          }
          return Column(
            children: [
              _buildFAQItem("How do I trigger a manual backup?", "Go to the 'Data Management' section and tap 'Backup System Now'. This creates an immediate snapshot of the entire database."),
              _buildFAQItem("How do I manage administrative permissions?", "In the 'Security' section, select 'Permissions'. You can toggle access for database management and analytics viewing."),
              _buildFAQItem("How can I export system reports?", "Tap 'Export System Data' in the 'Data Management' section. This will bundle all relevant system reports into an Excel document for download."),
              _buildFAQItem("What is the purpose of Two-Factor Auth?", "Two-Factor Authentication adds an extra layer of security. When enabled, you will need to provide a secondary verification code during login."),
              _buildFAQItem("How do I update my profile information?", "Tap the circular Pencil icon in the upper right corner of your 'Profile Information' card to update your name and email."),
            ],
          );
        }),
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
      iconColor: const Color(0xFF00796B),
      collapsedIconColor: Colors.grey,
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        Text(a, style: TextStyle(color: Colors.grey.shade700, height: 1.5, fontSize: aFontSize, fontWeight: FontWeight.w500)),
      ],
    );
  }

  void _showContactSupportModal() {
    bool isModalLoading = true;
    _showStyledBottomSheet(
      title: "Contact Support",
      description: "Reach out to Lipa IT Support if you need help or have inquiries.",
      children: [
        StatefulBuilder(builder: (ctx, setModalState) {
          if (isModalLoading) {
            Future.delayed(const Duration(milliseconds: 800), () {
              if (mounted) setModalState(() => isModalLoading = false);
            });
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(60),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: AppColors.tealText),
                    const SizedBox(height: 16),
                    Text("Loading support details...", style: TextStyle(color: Colors.grey.shade600, fontSize: 14, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            );
          }
          return Column(
            children: [
              const SizedBox(height: 0),
              _buildContactDetailRow(Icons.phone_rounded, "+63 43 756 0000"),
              const SizedBox(height: 16),
              _buildContactDetailRow(Icons.email_rounded, "it@lipa.gov.ph"),
              const SizedBox(height: 16),
              _buildContactDetailRow(Icons.map_rounded, "City Hall Complex, Marawoy, Lipa City"),
              const SizedBox(height: 24),
            ],
          );
        }),
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

  void _showAboutModal() {
    bool isModalLoading = true;
    _showStyledBottomSheet(
      title: "About",
      children: [
        StatefulBuilder(builder: (ctx, setModalState) {
          if (isModalLoading) {
            Future.delayed(const Duration(milliseconds: 800), () {
              if (mounted) setModalState(() => isModalLoading = false);
            });
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(60),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: AppColors.tealText),
                    const SizedBox(height: 16),
                    Text("Loading system info...", style: TextStyle(color: Colors.grey.shade600, fontSize: 14, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            );
          }
          return Column(
            children: [
              const Center(child: Icon(Icons.local_shipping_rounded, size: 64, color: Color(0xFF00796B))),
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
        }),
      ],
    );
  }

  Widget _buildAppInformation() {
    return _buildSectionContainer(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      children: [
        _buildInfoRow("System Version", "1.2.4"),
        const SizedBox(height: 12),
        _buildInfoRow("Database Sync", "Active", valueColor: Colors.green),
        const SizedBox(height: 12),
        _buildInfoRow("Environment", "Production"),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600, fontSize: 13)), Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: valueColor ?? const Color(0xFF2C3E50)))]);
  }

  Widget _buildSectionContainer({required List<Widget> children, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: AppTheme.balancedPulidongShadow),
      padding: padding ?? const EdgeInsets.all(0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildMenuAction(IconData icon, String title, VoidCallback onTap, {Widget? trailing}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        child: Row(
          children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF00796B).withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, size: 18, color: const Color(0xFF00796B))),
            const SizedBox(width: 16),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF2C3E50)))),
            trailing ?? Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey.shade300),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(height: 1, color: Colors.grey.shade100, indent: 24, endIndent: 24);
  }

  Widget _buildLogoutButton() {
    return HoverActionButton(text: "Logout", onTap: () => _showLogoutDialog(context));
  }

  Widget _buildDeleteAccountButton() {
    return HoverActionButton(text: "Deactivate Admin Access", isDestructive: true, onTap: () => _confirmDeleteAdmin());
  }

  void _confirmDeleteAdmin() async {
    final bool confirmed = await _showConfirmActionDialog(
      title: "Deactivate Account?", 
      message: "You will lose administrative access to the system.", 
      confirmText: "Deactivate", 
      isDestructive: true,
      icon: Icons.no_accounts_rounded,
      iconColor: Colors.red,
    );
    if (confirmed) {
      CustomNotification.showTopNotification(context, "Contact System SuperAdmin for deactivation.");
    }
  }

  Future<void> _downloadFile(String? url) async {
    if (url == null || url.isEmpty) return;
    
    // logic: If URL is relative (doesn't start with http), prepend the base URL
    String fullUrl = url;
    if (!url.startsWith('http')) {
      fullUrl = "${ApiClient.baseUrl}$url";
    }

    final Uri uri = Uri.parse(fullUrl);
    debugPrint("[DOWNLOAD] Triggering download for: $fullUrl");

    try {
      // Use LaunchMode.externalApplication for direct file downloads to trigger browser/download manager
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      
      if (mounted) {
        CustomNotification.showTopNotification(context, "Download request sent to system.", false);
      }
    } catch (e) {
      debugPrint("[DOWNLOAD] Error: $e");
      if (mounted) {
        CustomNotification.showTopNotification(context, "Download Error: $e", true);
      }
    }
  }

  Future<void> _handleManualBackup() async {
    CustomNotification.showTopNotification(context, "Initializing manual backup...", false);
    try {
      final response = await _apiService.triggerBackup();
      final data = response.data;
      if (data is Map && data['success'] == true) {
        final downloadUrl = data['url'];
        if (downloadUrl != null) {
          await _downloadFile(downloadUrl);
        } else {
          if (mounted) CustomNotification.showTopNotification(context, "Backup completed successfully!", false);
        }
      } else {
        if (mounted) {
          String msg = (data is Map) ? (data['message'] ?? "Backup failed") : "Invalid server response";
          CustomNotification.showTopNotification(context, msg);
        }
      }
    } catch (e) {
      if (mounted) CustomNotification.showTopNotification(context, "Error during backup: $e");
    }
  }

  Future<void> _handleExportData() async {
    final String exportUrl = "${ApiClient.baseUrl}export_report.php?format=xls";
    await _downloadFile(exportUrl);
  }

  void _showBackupHistoryDialog() {
    List<dynamic> history = [];
    bool isLoadingHistory = true;
    _showStyledBottomSheet(
      title: "Backup History",
      description: "View and manage previous system snapshots.",
      children: [
        StatefulBuilder(builder: (ctx, setDialogState) {
          if (isLoadingHistory) {
            _apiService.getBackupHistory().then((res) {
              final data = res.data;
              if (data is Map && data['success'] == true) {
                if (mounted) setDialogState(() { history = data['backups'] ?? []; isLoadingHistory = false; });
              } else {
                if (mounted) setDialogState(() => isLoadingHistory = false);
              }
            }).catchError((e) { if (mounted) setDialogState(() => isLoadingHistory = false); });
          }
          return isLoadingHistory 
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: AppColors.tealText),
                      const SizedBox(height: 16),
                      Text("Loading backup history...", style: TextStyle(color: Colors.grey.shade600, fontSize: 14, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ) 
            : (history.isEmpty ? const Center(child: Padding(padding: EdgeInsets.all(40), child: Text("No backup history found"))) : ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: history.length,
            separatorBuilder: (context, i) => const SizedBox(height: 12), // Adds space between items
            itemBuilder: (context, i) {
              final item = history[i];
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200, width: 1.2),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFFE3F2FD), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.storage_rounded, color: Color(0xFF1E88E5), size: 20)),
                  title: Text(item['filename'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  subtitle: Text(item['created_at'] ?? item['date'] ?? "", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.download_rounded, color: Color(0xFF1E88E5), size: 20), 
                        onPressed: () async { 
                          final url = item['url']; 
                          if (url != null) {
                            bool confirm = await _showConfirmActionDialog(
                              title: "Download Snapshot?",
                              message: "Are you sure you want to download ${item['filename']}?",
                              confirmText: "DOWNLOAD",
                              confirmColor: Colors.blue.shade700,
                            );
                            if (confirm) {
                              await _downloadFile(url);
                            }
                          }
                        }
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                        onPressed: () async {
                          bool confirm = await _showConfirmActionDialog(
                            title: "Delete Backup?",
                            message: "Are you sure you want to permanently delete this system backup?",
                            confirmText: "DELETE",
                            isDestructive: true,
                            confirmColor: Colors.red,
                          );
                          if (confirm) {
                            final res = await _apiService.deleteBackup(item['filename']);
                            if (res.data['success']) {
                              setDialogState(() { history.removeAt(i); });
                              if (mounted) CustomNotification.showTopNotification(context, "Backup deleted", false);
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ));
        }),
      ]
    );
  }

  void _showDataManagementModal() {
    if (_user == null) return;
    bool isModalLoading = true;
    _showStyledBottomSheet(
      title: "Edit Account",
      description: "Update your administrative contact details and credentials.",
      maxHeightMultiplier: 0.9,
      children: [
        StatefulBuilder(builder: (ctx, setModalState) {
          if (isModalLoading) {
            Future.delayed(const Duration(milliseconds: 800), () {
              if (mounted) setModalState(() => isModalLoading = false);
            });
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(60),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: AppColors.tealText),
                    const SizedBox(height: 16),
                    Text("Loading account data...", style: TextStyle(color: Colors.grey.shade600, fontSize: 14, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            );
          }
          return DataManagementModal(
            user: _user!, 
            onSuccess: _loadUser,
            usernameFocus: usernameFocus,
            nameFocus: nameFocus,
            emailFocus: emailFocus,
            phoneFocus: phoneFocus,
          );
        }),
      ],
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
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
    bool isLocalLoading = true;

    _showStyledBottomSheet(
      title: "Change Password",
      description: "Update your security credentials to keep your account safe.",
      children: [
        StatefulBuilder(builder: (context, setModalState) {
          if (isLocalLoading) {
            Future.delayed(const Duration(milliseconds: 800), () {
              if (mounted) setModalState(() => isLocalLoading = false);
            });
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(60),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: AppColors.tealText),
                    const SizedBox(height: 16),
                    Text("Preparing security tools...", style: TextStyle(color: Colors.grey.shade600, fontSize: 14, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            );
          }

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

            oldFocus.addListener(() { if (mounted) setState(() {}); if (!oldFocus.hasFocus) validateOld(); });
            newFocus.addListener(() { if (mounted) setState(() {}); if (!newFocus.hasFocus) validateNew(); });
            confirmFocus.addListener(() { if (mounted) setState(() {}); if (!confirmFocus.hasFocus) validateConfirm(); });
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
              const SizedBox(height: 12),
              _buildValidatedField(
                label: "New Password",
                controller: newPass, 
                focusNode: newFocus, 
                error: newError, 
                obscureText: obscureNew,
                prefixIcon: Icons.lock_reset_rounded,
                onToggle: () => setModalState(() => obscureNew = !obscureNew)
              ),
              const SizedBox(height: 12),
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
                isLoading: _isPasswordLoading,
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

                  setModalState(() => _isPasswordLoading = true);
                  setState(() => _isPasswordLoading = true);
                  
                  try {
                    final res = await _apiService.changePassword(_user!.userId, _user!.role, oldPass.text, newPass.text);
                    if (res.data['success'] == true) {
                      if (mounted) {
                        Navigator.pop(context);
                        CustomNotification.showTopNotification(context, "Successful change password", false);
                      }
                    } else {
                      setModalState(() => oldError = res.data['message'] ?? "Password update failed.");
                      CustomNotification.showTopNotification(context, res.data['message'] ?? "Password update failed.", true);
                    }
                  } catch (e) {
                    CustomNotification.showTopNotification(context, "Error: $e", true);
                  } finally {
                    setModalState(() => _isPasswordLoading = false);
                    if (mounted) setState(() => _isPasswordLoading = false);
                  }
                },
              ),
            ],
          );
        }),
      ]
    );
  }

  void _show2FADialog(BuildContext context) {
    bool is2FAEnabled = false; bool is2FALoading = true;
    _showStyledBottomSheet(
      title: "Two-Factor Authentication",
      description: "Enhance your administrator account security with 2FA.",
      children: [
        StatefulBuilder(builder: (context, setModalState) {
          if (is2FALoading) {
            SessionManager.getUser().then((user) {
              if (user != null) {
                _apiService.getAdminPermissions(user.userId).then((res) {
                  final data = res.data;
                  if (data is Map && data['success']) { if (mounted) setModalState(() { is2FAEnabled = data['data']['two_factor_enabled'] == 1; is2FALoading = false; }); }
                });
              }
            });
          }
          return is2FALoading 
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: AppColors.tealText),
                      const SizedBox(height: 16),
                      Text("Checking security status...", style: TextStyle(color: Colors.grey.shade600, fontSize: 14, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              )
            : Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey.shade200, width: 1.5),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (is2FAEnabled ? Colors.green : Colors.grey).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        is2FAEnabled ? Icons.shield_rounded : Icons.shield_outlined,
                        color: is2FAEnabled ? Colors.green : Colors.grey,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("2FA Status", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF1A1A1A))),
                          const SizedBox(height: 2),
                          Text(
                            is2FAEnabled ? "Active & Protected" : "Inactive • Enable for safety",
                            style: TextStyle(fontSize: 12, color: is2FAEnabled ? Colors.green.shade700 : Colors.grey.shade600, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: is2FAEnabled,
                      activeColor: const Color(0xFF00796B),
                      onChanged: (v) async {
                        final user = await SessionManager.getUser();
                        if (user != null) {
                          final res = await _apiService.toggle2FA(user.userId, v);
                          if (res.data['success']) {
                            await SystemLogger.logEvent("UPDATE", "${v ? 'Enabled' : 'Disabled'} 2FA");
                            if (mounted) setModalState(() => is2FAEnabled = v);
                            CustomNotification.showTopNotification(context, res.data['message'], false);
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "When enabled, you'll need to provide an extra verification step during login for maximum protection.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.5, fontWeight: FontWeight.w500),
              ),
            ],
          );
        }),
      ]
    );
  }

  void _showAccessLogsDialog(BuildContext context) {
    List<dynamic> logs = []; bool isLogsLoading = true;
    _showStyledBottomSheet(
      title: "System Access Logs",
      description: "Review recent security activity and administrative login history.",
      children: [
        StatefulBuilder(builder: (context, setModalState) {
          if (isLogsLoading) {
            _apiService.getAccessLogs().then((res) {
              final data = res.data;
              if (data is Map && data['success']) { if (mounted) setModalState(() { logs = data['logs']; isLogsLoading = false; }); }
            });
          }
          return isLogsLoading 
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: AppColors.tealText),
                      const SizedBox(height: 16),
                      Text("Fetching access logs...", style: TextStyle(color: Colors.grey.shade600, fontSize: 14, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              )
            : Column(
            children: [
              if (logs.isEmpty)
                const Center(child: Padding(padding: EdgeInsets.all(40), child: Text("No security logs recorded.")))
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: logs.length,
                  separatorBuilder: (context, i) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final log = logs[i];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200, width: 1.2),
                      ),
                      child: _logItem(
                        "${log['action']} from ${log['ip_address']}", 
                        log['timestamp'].toString(), 
                        log['action'].toString().contains("Successful")
                      ),
                    );
                  },
                ),
              const SizedBox(height: 32),
              HoverActionButton(
                text: "DONE",
                onTap: () => Navigator.pop(context),
              ),
            ],
          );
        }),
      ]
    );
  }

  void _showPermissionsDialog(BuildContext context) {
    bool canManageDb = false; bool canViewAnalytics = false; bool isPermsLoading = true;
    _showStyledBottomSheet(
      title: "Administrative Permissions",
      description: "Define control levels for this administrator account.",
      children: [
        StatefulBuilder(builder: (context, setModalState) {
          if (isPermsLoading) {
            SessionManager.getUser().then((user) {
              if (user != null) {
                _apiService.getAdminPermissions(user.userId).then((res) {
                  final data = res.data;
                  if (data is Map && data['success']) { if (mounted) setModalState(() { canManageDb = data['data']['can_manage_db'] == 1; canViewAnalytics = data['data']['can_view_analytics'] == 1; isPermsLoading = false; }); }
                });
              }
            });
          }
          return isPermsLoading 
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: AppColors.tealText),
                      const SizedBox(height: 16),
                      Text("Loading permission levels...", style: TextStyle(color: Colors.grey.shade600, fontSize: 14, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              )
            : Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200, width: 1.2),
                ),
                child: _permissionRow("Database Access", "Allow management of residents & trucks", canManageDb, (v) { setModalState(() => canManageDb = v!); }),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200, width: 1.2),
                ),
                child: _permissionRow("Analytics Access", "Allow viewing system reports", canViewAnalytics, (v) { setModalState(() => canViewAnalytics = v!); }),
              ),
              const SizedBox(height: 32),
              HoverActionButton(
                text: "APPLY CHANGES",
                onTap: () async {
                  bool confirm = await _showConfirmActionDialog(
                    title: "Update Permissions?",
                    message: "Are you sure you want to update the administrative access levels for this account?",
                    confirmText: "UPDATE"
                  );
                  if (confirm) {
                    final user = await SessionManager.getUser();
                    if (user != null) {
                      final res = await _apiService.updatePermissions(user.userId, canManageDb, canViewAnalytics);
                      if (res.data['success']) { 
                        await SystemLogger.logEvent("UPDATE", "Updated administrative permissions"); 
                        if (mounted) {
                          Navigator.pop(context); 
                          CustomNotification.showTopNotification(context, res.data['message'], false); 
                        }
                      }
                    }
                  }
                },
              )
            ],
          );
        }),
      ]
    );
  }

  Widget _buildValidatedField({
    required String label, 
    required TextEditingController controller, 
    required FocusNode focusNode, 
    String? error, 
    Color? errorColor,
    required bool obscureText, 
    VoidCallback? onToggle,
    IconData? prefixIcon,
  }) {
    final bool isDesktop = Responsive.isDesktop(context);
    bool hasFocus = focusNode.hasFocus;
    bool isPassword = label.toLowerCase().contains("password");
    bool isError = error != null && (errorColor == null || errorColor == Colors.redAccent);
    Color iconColor = hasFocus ? (isError ? Colors.redAccent : AppColors.tealText) : Colors.grey.shade400;
    
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
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            decoration: InputDecoration(
              filled: true,
              fillColor: hasFocus ? Colors.white : const Color(0xFFF3F5F7),
              contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: isDesktop ? 18 : 14),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: isError ? Colors.redAccent : Colors.grey.shade200, width: 1.2)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: isError ? Colors.redAccent : AppColors.tealText, width: 2.0)),
              prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: iconColor, size: 20) : null,
              suffixIcon: isPassword && onToggle != null ? IconButton(icon: Icon(obscureText ? Icons.visibility_off : Icons.visibility, color: iconColor, size: 20), onPressed: onToggle) : null,
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(error, style: TextStyle(color: errorColor ?? Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }

  Widget _logItem(String msg, String time, bool isSuccess) {
    return Row(children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: isSuccess ? Colors.green : Colors.red, shape: BoxShape.circle)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(msg, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF1A1A1A))), Text(time, style: const TextStyle(fontSize: 11, color: Colors.grey))])),
    ]);
  }

  Widget _permissionRow(String title, String subtitle, bool value, Function(bool?) onChanged) {
    return Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF1A1A1A))), Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF757575), fontWeight: FontWeight.w500))])),
      Checkbox(value: value, onChanged: onChanged, activeColor: const Color(0xFF00796B)),
    ]);
  }

  void _showLogoutDialog(BuildContext context) {
    _showConfirmActionDialog(
      title: "Logout?", 
      message: "Are you sure you want to end your current session?", 
      confirmText: "LOGOUT", 
      isDestructive: false,
      icon: Icons.logout_rounded,
      iconColor: const Color(0xFF00796B),
    ).then((confirmed) async {
      if (confirmed == true) {
        await SystemLogger.logEvent("LOGOUT", "Admin session ended");
        NotificationService.stopListening();
        await SessionManager.logout();
        if (mounted) {
          CustomNotification.showTopNotification(context, "Logout successful", false);
          Navigator.pushReplacementNamed(context, '/');
        }
      }
    });
  }

  Future<bool> _showConfirmActionDialog({
    required String title, 
    required String message, 
    String confirmText = "Confirm", 
    bool isDestructive = false,
    IconData? icon,
    Color? iconColor,
    Color? confirmColor,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 48, color: iconColor ?? (isDestructive ? Colors.red : const Color(0xFF00796B))),
                  const SizedBox(height: 24),
                ],
                Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
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
                          backgroundColor: confirmColor ?? (isDestructive ? Colors.red : const Color(0xFF00796B)),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(confirmText.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return result ?? false;
  }

  void _showStyledBottomSheet({required String title, required List<Widget> children, String? description, double maxHeightMultiplier = 0.6}) {
    if (Responsive.isDesktop(context)) {
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
