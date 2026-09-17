import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/app_theme.dart';
import '../utils/session_manager.dart';
import '../models/user.dart';
import '../api/api_service.dart';
import '../utils/custom_notification.dart';
import '../utils/app_localizations.dart';
import '../widgets/hover_action_button.dart';
import '../widgets/fade_slide_entrance.dart';
import '../widgets/legal_agreement_dialog.dart';
import '../widgets/data_management_modal.dart';
import '../utils/responsive.dart';
import '../widgets/custom_snackbar.dart';

class ResidentSettingsScreen extends StatefulWidget {
  final bool isEmbedded;
  final bool showDataManagementOnLoad;
  final VoidCallback? onBack;
  final VoidCallback? onProfileUpdate;
  const ResidentSettingsScreen({
    super.key, 
    this.isEmbedded = false, 
    this.showDataManagementOnLoad = false,
    this.onBack, 
    this.onProfileUpdate
  });

  @override
  State<ResidentSettingsScreen> createState() => _ResidentSettingsScreenState();
}

class _ResidentSettingsScreenState extends State<ResidentSettingsScreen> with TickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  UserData? _user;
  bool _pushNotifications = true;
  bool _isLoading = false;
  bool _isLoggingOut = false;
  StreamSubscription? _userSubscription;
  final String _appVersion = "1.0.0";
  final ScrollController _scrollController = ScrollController();
  bool _showHeaderShadow = true;

  bool _isRefreshing = false;
  bool _showRefreshSpinner = false;
  double _manualPullDepth = 0.0;
  late AnimationController _refreshRotationController;

  final List<String> _puroks = [
    "Purok 1", "Purok 2", "Purok 3", "Purok 4", "Dos Riles", "Sentro",
    "San Isidro", "Paraiso", "Riverside", "Kalaw Street",
    "Home Subdivision", "Tanco Road / Ayala Highway", "Brixton Area"
  ];

  final FocusNode usernameFocus = FocusNode();
  final FocusNode nameFocus = FocusNode();
  final FocusNode emailFocus = FocusNode();
  final FocusNode phoneFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    AppLocalizations.currentLanguage.addListener(_onLanguageChanged);
    _loadUser();

    // Add listeners for focus color changes
    usernameFocus.addListener(() { if (mounted) setState(() {}); });
    nameFocus.addListener(() { if (mounted) setState(() {}); });
    emailFocus.addListener(() { if (mounted) setState(() {}); });
    phoneFocus.addListener(() { if (mounted) setState(() {}); });
    
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

    if (widget.showDataManagementOnLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showDataManagementModal();
      });
    }
  }

  void _onLanguageChanged() {
    if (mounted) setState(() {});
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
    final sessionUser = await SessionManager.getUser();
    if (sessionUser != null) {
      setState(() {
        _user = sessionUser;
      });
      _loadSettings();
      _setupRealtimeListener();
    }
  }

  @override
  void didUpdateWidget(ResidentSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showDataManagementOnLoad && !oldWidget.showDataManagementOnLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showDataManagementModal();
      });
    }
  }

  void _setupRealtimeListener() {
    _userSubscription?.cancel();
    if (_user != null) {
      _userSubscription = _database.ref('residents/${_user!.userId}').onValue.listen((event) {
        if (event.snapshot.exists) {
          final Map data = event.snapshot.value as Map;
          if (mounted) {
            final String? newName = data['name']?.toString();
            final String? newEmail = data['email']?.toString();
            final String? newPhone = data['phone']?.toString();
            final String? newPurok = data['purok']?.toString();
            
            if (newName != null && newEmail != null && newPhone != null && newPurok != null) {
              final updated = _user!.copyWith(
                name: newName,
                email: newEmail,
                phone: newPhone,
                purok: newPurok,
              );
              if (updated.toJson().toString() != _user!.toJson().toString()) {
                setState(() => _user = updated);
                SessionManager.saveUser(updated.toJson());
              }
            }
          }
        }
      });
    }
  }

  void _loadSettings() async {
    if (_user == null) return;
    
    // SYNC: Ensure we respect the system-level permission choice
    final bool systemEnabled = await SessionManager.isAppNotificationsEnabled();
    
    final ref = _database.ref('residents/${_user!.userId}/settings');
    final snapshot = await ref.get();
    if (snapshot.exists) {
      final data = snapshot.value as Map;
      setState(() {
        _pushNotifications = systemEnabled && (data['pushNotifications'] ?? true);
      });
    } else {
      // Default to system state
      await ref.set({'pushNotifications': systemEnabled});
      setState(() {
        _pushNotifications = systemEnabled;
      });
    }
  }

  Future<void> _updateSettings(String key, bool value) async {
    if (_user == null) return;
    
    String label = "Push Notifications";

    try {
      await _database.ref('residents/${_user!.userId}/settings').update({
        key: value,
      });
      if (mounted) {
        setState(() {
          if (key == 'pushNotifications') {
            _pushNotifications = value;
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
             CustomNotification.showTopNotification(context, "Permissions are required to enable alerts.", true);
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
        CustomNotification.showTopNotification(context, "Failed to update settings.");
      }
    }
  }

  @override
  void dispose() {
    AppLocalizations.currentLanguage.removeListener(_onLanguageChanged);
    _userSubscription?.cancel();
    _scrollController.dispose();
    _refreshRotationController.dispose();
    super.dispose();
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
                                      _buildSectionHeader(Icons.notifications_rounded, "Preferences"),
                                      _buildNotificationsSection(),
                                      const SizedBox(height: 24),
                                      _buildSectionHeader(Icons.security_rounded, "Security & Privacy"),
                                      _buildSecuritySection(),
                                      const SizedBox(height: 24),
                                      _buildSectionHeader(Icons.help_outline_rounded, "Support & Legal"),
                                      _buildSupportSection(),
                                      const SizedBox(height: 24),
                                      _buildSectionHeader(Icons.info_outline_rounded, "App Information"),
                                      _buildAppInformation(),
                                      const SizedBox(height: 32),
                                      _buildLogoutButton(),
                                      const SizedBox(height: 16),
                                      _buildDeleteAccountButton(),
                                      SizedBox(height: Responsive.isDesktop(context) ? 40 : 100),
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

    // Adaptive font sizes for mobile/tablet
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
                Text("Manage your preferences", style: TextStyle(fontSize: subtitleFontSize, color: const Color(0xFF757575), fontWeight: FontWeight.w600)),
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

  Widget _buildProfilePictureSection() {
    final String displayName = _user?.name ?? "Resident";
    final String? profileUrl = _user?.profilePicture;
    final double screenWidth = MediaQuery.of(context).size.width;
    final double picSize = (screenWidth * 0.2).clamp(64.0, 80.0);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: AppTheme.balancedPulidongShadow),
      child: Row(
        children: [
          GestureDetector(
            onTap: _viewProfilePictureLarge,
            child: Stack(
              children: [
                Container(
                  width: picSize, height: picSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.tealText, width: 2),
                    image: profileUrl != null && profileUrl.isNotEmpty ? DecorationImage(image: NetworkImage(profileUrl), fit: BoxFit.cover) : null,
                  ),
                  child: profileUrl == null || profileUrl.isEmpty ? Center(child: Text(displayName[0].toUpperCase(), style: TextStyle(fontSize: picSize * 0.4, fontWeight: FontWeight.bold, color: AppColors.tealText))) : null,
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
                Text("Resident", style: TextStyle(fontSize: (screenWidth * 0.03).clamp(10.0, 12.0), color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(displayName, style: TextStyle(fontSize: (screenWidth * 0.04).clamp(14.0, 16.0), fontWeight: FontWeight.w800, color: const Color(0xFF2C3E50))),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildCompactActionBtn(label: "Upload", icon: Icons.camera_alt_rounded, onTap: _showUploadOptions, color: AppColors.tealText),
                    if (profileUrl != null && profileUrl.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      _buildCompactActionBtn(label: "Delete", icon: Icons.delete_outline_rounded, onTap: _confirmDeletePicture, color: Colors.redAccent),
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
                                (_user?.name != null && _user!.name.isNotEmpty) ? _user!.name[0].toUpperCase() : "R",
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
    _showStyledBottomSheet(
      title: "Upload Photo",
      description: "Choose how you want to upload your profile picture.",
      children: [
        _buildUploadOptionItem(icon: Icons.photo_library_rounded, label: "Choose from Gallery", onTap: () { Navigator.pop(context); _handleImageSelection(ImageSource.gallery); }),
        const SizedBox(height: 12),
        _buildUploadOptionItem(icon: Icons.camera_enhance_rounded, label: "Take a Selfie", onTap: () { Navigator.pop(context); _handleImageSelection(ImageSource.camera); }),
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
            Icon(icon, color: AppColors.tealText),
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
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: source, preferredCameraDevice: CameraDevice.front);
    if (image == null) return;
    setState(() => _isLoading = true);
    try {
      final bytes = await image.readAsBytes();
      final response = await _apiService.uploadProfilePicture(userId: _user!.userId, role: _user!.role, fileName: image.name, imageBytes: bytes.toList());
      if (response.data['success'] == true) {
        final String profileUrl = response.data['url'];
        await _database.ref('residents/${_user!.userId}').update({'profile_picture': profileUrl});
        final updatedUser = {..._user!.toJson(), 'profile_picture': profileUrl};
        await SessionManager.saveUser(updatedUser);
        _loadUser();
        CustomNotification.showTopNotification(context, "Profile picture updated successfully.", false);
      }
    } catch (e) {
      CustomNotification.showTopNotification(context, "Failed to upload image.");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _confirmDeletePicture() async {
    final confirmed = await _showConfirmActionDialog(
      title: "Delete Photo?", 
      message: "Are you sure you want to remove your profile picture? This will revert to your initials.", 
      confirmText: "Delete Photo", 
      isDestructive: true
    );
    if (confirmed) {
      setState(() => _isLoading = true);
      try {
        await _database.ref('residents/${_user!.userId}').update({'profile_picture': null});
        await _apiService.updateProfile(userId: _user!.userId, role: _user!.role, name: _user!.name, email: _user!.email, phone: _user!.phone ?? "", address: _user!.completeAddress ?? "", profilePicture: "");
        final updatedUser = {..._user!.toJson()};
        updatedUser.remove('profile_picture');
        await SessionManager.saveUser(updatedUser);
        _loadUser();
        CustomNotification.showTopNotification(context, "Profile picture removed.", false);
      } catch (e) {
        CustomNotification.showTopNotification(context, "Error deleting photo.");
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildCompactActionBtn({required String label, required IconData icon, required VoidCallback onTap, required Color color}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.2))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: color), const SizedBox(width: 6), Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color))]),
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
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: AppTheme.balancedPulidongShadow),
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
              _buildProfileRow("Resident Area", _user?.purok ?? "Not set", labelFontSize: labelFontSize, valueFontSize: valueFontSize),
            ],
          ),
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
              child: const Icon(Icons.edit_rounded, color: Color(0xFF00796B), size: 16),
            ),
          ),
        ),
      ],
    );
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

  Widget _buildNotificationsSection() {
    return _buildSectionCard(
      children: [
        _buildToggleRow("Push Notifications", _pushNotifications, (v) => _updateSettings('pushNotifications', v), icon: Icons.notifications_active_rounded),
      ],
    );
  }

  Widget _buildToggleRow(String label, bool value, Function(bool) onChanged, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: AppColors.tealText, size: 20),
            const SizedBox(width: 16),
          ],
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
          Switch(value: value, onChanged: onChanged, activeColor: AppColors.tealText),
        ],
      ),
    );
  }

  Widget _buildSecuritySection() {
    return _buildSectionCard(
      children: [
        _buildMenuAction(Icons.lock_rounded, "Change Password", _showChangePasswordModal),
      ],
    );
  }

  Widget _buildSupportSection() {
    return _buildSectionCard(
      children: [
        _buildMenuAction(Icons.language_rounded, "Language", _showLanguageModal),
        _buildDivider(),
        _buildMenuAction(Icons.gavel_rounded, "Terms & Conditions", () => LegalAgreementDialog.show(context, isTerms: true)),
        _buildDivider(),
        _buildMenuAction(Icons.privacy_tip_rounded, "Privacy Policy", () => LegalAgreementDialog.show(context, isTerms: false)),
        _buildDivider(),
        _buildMenuAction(Icons.quiz_rounded, "FAQs", _showFAQsModal),
        _buildDivider(),
        _buildMenuAction(Icons.contact_support_rounded, "Contact Support", _showContactSupportModal),
        _buildDivider(),
        _buildMenuAction(Icons.info_rounded, "About Us", _showAboutModal),
      ],
    );
  }

  Widget _buildSectionCard({required List<Widget> children, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: AppTheme.balancedPulidongShadow),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(0),
        child: Column(children: children),
      ),
    );
  }

  Widget _buildAppInformation() {
    return _buildSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      children: [
        _buildInfoRow("Version", _appVersion),
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

  Widget _buildMenuAction(IconData icon, String title, VoidCallback onTap, {bool showIcon = true, EdgeInsets? padding, Color? textColor}) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double titleFontSize = (screenWidth * 0.04).clamp(14.0, 16.0);
    final double iconSize = (screenWidth * 0.045).clamp(16.0, 18.0);
    final double iconPadding = (screenWidth * 0.02).clamp(6.0, 8.0);

    return InkWell(
      onTap: onTap,
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
                color: (textColor ?? AppColors.tealText).withOpacity(0.1),
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

  Widget _buildDivider() => const Divider(height: 1, indent: 24, endIndent: 24);

  Widget _buildLogoutButton() {
    return HoverActionButton(
      text: "Logout",
      loadingText: "Logging out...",
      isLoading: _isLoggingOut,
      onTap: () => _showLogoutDialog(context),
    );
  }

  Widget _buildDeleteAccountButton() {
    return HoverActionButton(
      text: "Delete Account",
      loadingText: "Deleting Account...",
      isLoading: _isLoading,
      isDestructive: true,
      onTap: () => _showDeleteAccountConfirmation(),
    );
  }

  void _showLanguageModal() {
    _showStyledBottomSheet(
      title: "Language Selection",
      description: "Select your preferred language for the application.",
      needsLoading: true,
      loadingText: "Preparing languages...",
      children: [
        _buildLanguageItem("English", AppLanguage.en),
        _buildLanguageItem("Filipino", AppLanguage.fil),
        _buildLanguageItem("Bisaya", AppLanguage.bis),
      ],
    );
  }

  Widget _buildLanguageItem(String label, AppLanguage lang) {
    bool isSelected = AppLocalizations.currentLanguage.value == lang;
    return ListTile(
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      leading: Icon(Icons.language_rounded, color: isSelected ? AppColors.tealText : Colors.grey),
      trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: AppColors.tealText) : null,
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
    _showStyledBottomSheet(
      title: "FAQs",
      description: "Find answers to frequently asked questions.",
      maxHeightMultiplier: 0.85,
      needsLoading: true,
      loadingText: "Fetching FAQs...",
      children: [
        _buildFAQItem("How do I track a truck?", "Go to the Track tab to see real-time locations of garbage trucks in your area."),
        _buildFAQItem("How is ETA calculated?", "The ETA is estimated based on the truck's current GPS position, road distance, and historical speed data."),
        _buildFAQItem("Can I report a missed collection?", "Yes, you can file a report in the 'Report' tab. Provide details about your area and the specific collection issue."),
        _buildFAQItem("How do I update my location?", "You can update your Purok/Area by tapping the 'Edit' button in your profile section above."),
        _buildFAQItem("What are proximity alerts?", "These are notifications sent to your device when a garbage truck is within 10 minutes of your registered Purok, allowing you to prepare your trash in advance."),
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
      needsLoading: true,
      loadingText: "Loading contact info...",
      children: [
        const SizedBox(height: 0),
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

  void _showAboutModal() {
    _showStyledBottomSheet(
      title: "About",
      needsLoading: true,
      loadingText: "Preparing about info...",
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

  void _showDataManagementModal() {
    if (_user == null) return;
    _showStyledBottomSheet(
      title: "Edit Account",
      description: "Update your profile details and account settings here.",
      maxHeightMultiplier: 0.9,
      needsLoading: true,
      loadingText: "Loading account details...",
      children: [
        DataManagementModal(
          user: _user!, 
          onSuccess: _loadUser,
          usernameFocus: usernameFocus,
          nameFocus: nameFocus,
          emailFocus: emailFocus,
          phoneFocus: phoneFocus,
        ),
      ],
    );
  }

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
      maxHeightMultiplier: 0.8,
      needsLoading: true,
      loadingText: "Preparing password form...",
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

            oldFocus.addListener(() { if (mounted) setState(() {}); if (!oldFocus.hasFocus) validateOld(); });
            newFocus.addListener(() { if (mounted) setState(() {}); if (!newFocus.hasFocus) validateNew(); });
            confirmFocus.addListener(() { if (mounted) setState(() {}); if (!confirmFocus.hasFocus) validateConfirm(); });
          }

          return Column(
            children: [
              const SizedBox(height: 8),
              _buildPasswordField(
                label: "Current Password",
                controller: oldPass,
                focusNode: oldFocus,
                error: oldError,
                obscure: obscureOld,
                prefixIcon: Icons.lock_outline_rounded,
                onToggle: () => setModalState(() => obscureOld = !obscureOld),
                onSubmitted: (_) => validateOld(),
              ),
              const SizedBox(height: 12),
              _buildPasswordField(
                label: "New Password",
                controller: newPass,
                focusNode: newFocus,
                error: newError,
                obscure: obscureNew,
                prefixIcon: Icons.lock_reset_rounded,
                onToggle: () => setModalState(() => obscureNew = !obscureNew),
                onSubmitted: (_) => validateNew(),
              ),
              const SizedBox(height: 12),
              _buildPasswordField(
                label: "Confirm New Password",
                controller: confirmPass,
                focusNode: confirmFocus,
                error: confirmError,
                obscure: obscureConfirm,
                prefixIcon: Icons.check_circle_outline_rounded,
                onToggle: () => setModalState(() => obscureConfirm = !obscureConfirm),
                onSubmitted: (_) => validateConfirm(),
              ),
              const SizedBox(height: 24),
              HoverActionButton(
                text: "Update Password",
                onTap: () async {
                  await validateOld();
                  validateNew();
                  validateConfirm();
                  if (oldError == null && newError == null && confirmError == null) {
                    try {
                      final res = await _apiService.changePassword(
                        _user!.userId,
                        _user!.role,
                        oldPass.text,
                        newPass.text
                      );
                      if (res.data['success'] == true) {
                        if (mounted) {
                          Navigator.pop(context);
                          CustomNotification.showTopNotification(context, "Password updated successfully!", false);
                        }
                      } else {
                        setModalState(() => oldError = res.data['message']);
                      }
                    } catch (e) {
                      CustomNotification.showTopNotification(context, "Error updating password.");
                    }
                  }
                }
              ),
              const SizedBox(height: 24),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildPasswordField({
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
    String? error,
    required bool obscure,
    required VoidCallback onToggle,
    required Function(String) onSubmitted,
    IconData? prefixIcon,
  }) {
    bool hasFocus = focusNode.hasFocus;
    bool isError = error != null;
    Color iconColor = hasFocus ? (isError ? Colors.redAccent : AppColors.tealText) : Colors.grey.shade400;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.grey)),
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
            obscureText: obscure,
            onSubmitted: onSubmitted,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            decoration: InputDecoration(
              hintText: "Enter your password",
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
              filled: true,
              fillColor: hasFocus ? Colors.white : const Color(0xFFF3F5F7),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: iconColor, size: 20) : null,
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: isError ? Colors.redAccent : Colors.grey.shade200, width: 1.2)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: isError ? Colors.redAccent : AppColors.tealText, width: 2.0)),
              suffixIcon: IconButton(
                icon: Icon(obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: iconColor, size: 20),
                onPressed: onToggle,
              ),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(error, style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }

  Future<bool> _showConfirmActionDialog({
    required String title,
    required String message,
    required String confirmText,
    bool isDestructive = false,
    IconData? icon,
    Color? iconColor,
  }) async {
    return await showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 40, 32, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: (iconColor ?? Colors.red).withOpacity(0.1), shape: BoxShape.circle),
                    child: Icon(icon, color: iconColor ?? Colors.red, size: 32),
                  ),
                  const SizedBox(height: 24),
                ],
                Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500, height: 1.5)),
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
                        text: confirmText,
                        isDestructive: isDestructive,
                        onTap: () => Navigator.pop(context, true)
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

  void _showDeleteAccountConfirmation() async {
    bool confirmed = await _showConfirmActionDialog(
      title: "Delete Account?",
      message: "You will lose all access and your account data will be permanently removed.",
      confirmText: "Delete",
      isDestructive: true,
      icon: Icons.no_accounts_rounded,
    );
    if (confirmed) {
      setState(() => _isLoading = true);
      try {
        final res = await _apiService.deleteUser(_user!.userId, _user!.role);
        if (res.data['success'] == true) {
           await SessionManager.logout();
           if (mounted) {
             CustomNotification.showTopNotification(context, "Account deleted successfully.", false);
             Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
           }
        }
      } catch (e) {
        CustomNotification.showTopNotification(context, "Delete failed. Please try again.");
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _showStyledBottomSheet({required String title, required List<Widget> children, String? description, double maxHeightMultiplier = 0.6, bool needsLoading = false, String loadingText = "Loading..."}) {
    bool isModalLoading = needsLoading;

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

            return Center(
              child: Material(
                color: Colors.transparent,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOutCubic,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 30, offset: const Offset(0, 10))
                    ],
                  ),
                  constraints: BoxConstraints(
                    maxWidth: 550, 
                    maxHeight: isModalLoading ? 250 : 600
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
                            Expanded(child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.tealText))),
                            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.grey)),
                          ],
                        ),
                      ),
                      if (description != null && description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
                          child: Text(description, style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
                        ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 32),
                        child: Divider(height: 32),
                      ),
                      if (isModalLoading)
                        Expanded(
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(color: AppColors.tealText, strokeWidth: 3),
                                const SizedBox(height: 16),
                                Text(loadingText, 
                                    style: TextStyle(fontSize: 14, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        )
                      else
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                            child: Column(mainAxisSize: MainAxisSize.min, children: children)
                          )
                        ),
                    ],
                  ),
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

          return Container(
            clipBehavior: Clip.antiAlias,
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOutCubic,
              constraints: BoxConstraints(
                maxHeight: isModalLoading ? 250 : MediaQuery.of(context).size.height * maxHeightMultiplier
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
                  if (isModalLoading)
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(color: AppColors.tealText, strokeWidth: 3),
                            SizedBox(height: 16),
                            Text(loadingText, 
                                style: TextStyle(fontSize: 14, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    )
                  else
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
      ),
    ).whenComplete(() {
      _loadUser(); // Refresh on close just in case
    });
  }

  void _showLogoutDialog(BuildContext context) async {
    bool confirmed = await _showConfirmActionDialog(
      title: "Logout?", 
      message: "Are you sure you want to end your current session?", 
      confirmText: "Logout",
      isDestructive: false, // Changed to false to use primary color (Green/Teal)
      icon: Icons.logout_rounded,
      iconColor: AppColors.tealText,
    );
    if (confirmed) {
      setState(() => _isLoggingOut = true);
      await SessionManager.logout();
      if (mounted) {
        CustomNotification.showTopNotification(context, "Logout successful.", false);
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
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
  bool _isHovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 200),
          scale: _isHovered ? 1.05 : 1.0,
          child: widget.child,
        ),
      ),
    );
  }
}
