import 'dart:async';
// Splash screen for initial app loading
import 'dart:io' show InternetAddress, Platform;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import '../utils/route_persistence_manager.dart';
import '../widgets/animated_auth_background.dart';
import '../widgets/hover_action_button.dart';
import '../utils/app_theme.dart';
import '../utils/responsive_text.dart';
import '../utils/app_localizations.dart';
import '../utils/session_manager.dart';
import '../utils/responsive.dart';
import '../models/user.dart';
import '../services/notification_service.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<Offset> _slideAnimation;
  
  bool _isChecking = true;
  bool _noInternet = false;
  bool _showLoader = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _scaleAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller, 
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack)
      ),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller, 
        curve: const Interval(0.2, 0.8, curve: Curves.easeIn)
      ),
    );

    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _controller, 
        curve: const Interval(0.4, 1.0, curve: Curves.easeOutCubic)
      ),
    );

    _controller.forward();
    AppLocalizations.currentLanguage.addListener(_onLanguageChanged);
    _checkConnection();
  }

  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _checkConnection() async {
    setState(() {
      _isChecking = true;
      _noInternet = false;
      _showLoader = true;
    });

    // Minimum delay for branding visibility
    await Future.delayed(const Duration(seconds: 2));

    try {
      bool hasConnection = false;

      if (kIsWeb) {
        // Web-safe check using Dio
        try {
          final dio = Dio(BaseOptions(
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
          ));
          // We just need to reach any stable URL. Google might have CORS issues
          // but reaching it even with a CORS error usually means you have internet.
          // Better: reach your own backend if available.
          await dio.get('https://www.google.com');
          hasConnection = true;
        } catch (e) {
          // In Flutter Web, a CORS error still means we reached the server (internet is up)
          // Only a network failure (no connection) will throw a specific DioException
          if (e is DioException) {
            if (e.type == DioExceptionType.connectionTimeout || 
                e.type == DioExceptionType.sendTimeout ||
                e.type == DioExceptionType.receiveTimeout) {
              hasConnection = false;
            } else {
              // Most other errors (like CORS) imply we reached the internet
              hasConnection = true;
            }
          } else {
            hasConnection = false;
          }
        }
      } else {
        // Mobile check using InternetAddress
        final result = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 5));
        hasConnection = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      }

      if (hasConnection) {
        if (mounted) {
          // 1. Hide loader first for a clean transition
          setState(() => _showLoader = false);
          
          // 2. Very brief delay to let the loader fade out
          await Future.delayed(const Duration(milliseconds: 300));

          if (!mounted) return;

          // 3. Check for existing session
          final bool loggedIn = await SessionManager.isLoggedIn();
          final UserData? user = await SessionManager.getUser();

          if (loggedIn && user != null) {
            String role = user.role.toLowerCase();
            String route = '/';
            
            // Check persistence first
            final String? lastRoute = await RoutePersistenceManager.getLastRoute();
            
            if (lastRoute != null && lastRoute != '/' && lastRoute != '/splash') {
              route = lastRoute;
            } else {
              if (role == 'admin') {
                route = '/admin_dashboard';
              } else if (role == 'resident') {
                route = '/resident_dashboard';
              } else if (role == 'driver') {
                route = '/driver_dashboard';
              }
            }

            // --- TRIGGER NATIVE PERMISSION PROMPTS ---
            if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
              bool hasMandatory = await _checkMandatoryPermissions();
              if (!hasMandatory) {
                // If location is denied, stop splash and show local error UI
                if (mounted) {
                  setState(() {
                    _isChecking = false;
                    _showLoader = false;
                  });
                }
                return;
              }
            }

            if (mounted) {
              Navigator.pushReplacementNamed(context, route, arguments: user);
            }
          } else {
            // Check if we were in the middle of a Forgot Password flow even if not logged in
            final String? lastRoute = await RoutePersistenceManager.getLastRoute();
            if (lastRoute == '/forgot_password' && mounted) {
               Navigator.pushReplacementNamed(context, '/forgot_password');
            } else if (mounted) {
              // 4. No session, go to Login
              Navigator.pushReplacement(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) => const LoginScreen(),
                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                    return FadeTransition(
                      opacity: CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeIn,
                      ),
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 1.05, end: 1.0).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                        child: child,
                      ),
                    );
                  },
                  transitionDuration: const Duration(milliseconds: 600),
                ),
              );
            }
          }
        }
      } else {
        _showError();
      }
    } catch (_) {
      _showError();
    }
  }

  Future<bool> _checkMandatoryPermissions() async {
    // 1. Trigger Native Location Prompt
    try {
      PermissionStatus locStatus = await Permission.location.request();
      if (!locStatus.isGranted && !locStatus.isLimited) {
        return false; // ENFORCE: Block app entry if location is denied
      }
    } catch (_) {
      return false;
    }

    // Small delay for OS stability
    await Future.delayed(const Duration(milliseconds: 500));

    // 2. Trigger Native Notification Prompt via specialized Service
    try {
      PermissionStatus statusBefore = await Permission.notification.status;
      if (statusBefore.isDenied || statusBefore.isProvisional) {
        PermissionStatus statusAfter = await Permission.notification.request();
        if (statusAfter.isGranted) {
          await SessionManager.setAppNotificationsEnabled(true);
          await SessionManager.setNotifPermissionRequested(true);
          // Redirect to system settings for channel verification as requested
          await openAppSettings();
        } else {
          await SessionManager.setAppNotificationsEnabled(false);
          await SessionManager.setNotifPermissionRequested(true);
        }
      }
    } catch (_) {}

    return true; // Allow entry as long as location is granted
  }

  void _showError() {
    if (mounted) {
      setState(() {
        _isChecking = false;
        _noInternet = true;
        _showLoader = false;
      });
    }
  }

  @override
  void dispose() {
    AppLocalizations.currentLanguage.removeListener(_onLanguageChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = Responsive.isDesktop(context);
    final bool isTablet = Responsive.isTablet(context);
    
    // Responsive sizes scaled based on screen
    final double logoContainerSize = ResponsiveText.getIconSize(context, 120);
    final double iconSize = ResponsiveText.getIconSize(context, 64);
    final double loaderSize = ResponsiveText.getIconSize(context, 140);
    final double brandingSize = ResponsiveText.getFontSize(context, 36);

    String loadingMessage = kIsWeb 
        ? AppLocalizations.get('splash_loading_portal')
        : AppLocalizations.get('please_wait_opening');

    return AnimatedAuthBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 500),
                        opacity: _showLoader ? 1.0 : 0.0,
                        child: SizedBox(
                          width: loaderSize,
                          height: loaderSize,
                          child: CircularProgressIndicator(
                            strokeWidth: isDesktop ? 4 : 3,
                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.tealText.withOpacity(0.5)),
                          ),
                        ),
                      ),
                      Hero(
                        tag: 'app_logo',
                        child: ScaleTransition(
                          scale: _scaleAnimation,
                          child: FadeTransition(
                            opacity: _opacityAnimation,
                            child: Container(
                              width: logoContainerSize,
                              height: logoContainerSize,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [AppColors.loginButtonStart, AppColors.loginButtonEnd],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.loginButtonEnd.withAlpha(60),
                                    blurRadius: isDesktop ? 50 : 30,
                                    offset: Offset(0, isDesktop ? 20 : 15),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.local_shipping_rounded, 
                                size: iconSize, 
                                color: Colors.white
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  FadeTransition(
                    opacity: _opacityAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: Column(
                        children: [
                          Hero(
                            tag: 'app_name',
                            child: Material(
                              color: Colors.transparent,
                              child: Text(
                                AppLocalizations.get('garbage_tracker'),
                                textAlign: TextAlign.center,
                                style: ResponsiveText.brandingTitle(context).copyWith(
                                  fontSize: brandingSize,
                                  letterSpacing: -1.5,
                                ),
                              ),
                            ),
                          ),
                          if (_isChecking) ...[
                            const SizedBox(height: 12),
                            Text(
                              loadingMessage,
                              textAlign: TextAlign.center,
                              style: ResponsiveText.body(context, 
                                color: AppColors.textGray.withAlpha(200)
                              ).copyWith(
                                fontSize: ResponsiveText.getFontSize(context, 14),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (!_isChecking && _noInternet) ...[
                    const SizedBox(height: 56),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(240),
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withAlpha(15), blurRadius: 20, offset: const Offset(0, 10))
                        ],
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.wifi_off_rounded, 
                            color: Colors.redAccent, 
                            size: 40
                          ),
                          const SizedBox(height: 16),
                          Text(
                            AppLocalizations.get('err_connection'),
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF1A1A1A)),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            "Please check your network settings and try again.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500, height: 1.5),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: HoverActionButton(
                              text: AppLocalizations.get('retry_connection'),
                              onTap: _checkConnection,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
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

