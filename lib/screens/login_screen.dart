import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../api/api_service.dart';
import '../utils/app_theme.dart';
import '../widgets/legal_agreement_dialog.dart';
import '../utils/login_security_manager.dart';
import '../utils/session_manager.dart';
import '../utils/responsive.dart';
import '../widgets/animated_auth_background.dart';
import '../widgets/hover_action_button.dart';
import '../widgets/fade_slide_entrance.dart';
import '../utils/app_localizations.dart';
import '../utils/custom_notification.dart';
import '../utils/route_persistence_manager.dart';
import '../utils/responsive_text.dart';
import '../widgets/custom_snackbar.dart';
import '../services/notification_service.dart';
import 'forgot_password_screen.dart';
import 'register_choice_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscureText = true;
  IconData _currentLogoIcon = Icons.local_shipping_rounded;

  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  String? _usernameError;
  String? _passwordError;

  SecurityStatus? _securityStatus;
  int _secondsRemaining = 0;
  Timer? _lockoutTimer;
  final Map<String, Timer?> _errorTimers = {};

  @override
  void initState() {
    super.initState();
    RoutePersistenceManager.saveLastRoute('/');
    _checkSecurityStatus();
    AppLocalizations.currentLanguage.addListener(_onLanguageChanged);
    
    // Real-time listeners
    _usernameController.addListener(_onUsernameChanged);
    _passwordController.addListener(_onPasswordChanged);

    _usernameFocus.addListener(() { 
      if (!_usernameFocus.hasFocus) {
        _validateUsername();
        _checkSecurityStatus();
      }
      setState(() {}); 
    });
    _passwordFocus.addListener(() { 
      if (!_passwordFocus.hasFocus) {
        _validatePassword();
      }
      setState(() {}); 
    });
  }

  @override
  void dispose() {
    _errorTimers.forEach((_, timer) => timer?.cancel());
    _usernameController.removeListener(_onUsernameChanged);
    _passwordController.removeListener(_onPasswordChanged);
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _lockoutTimer?.cancel();
    AppLocalizations.currentLanguage.removeListener(_onLanguageChanged);
    super.dispose();
  }

  void _setErrorWithTimer(String field, String? errorKey) {
    setState(() {
      if (field == 'username') _usernameError = errorKey;
      if (field == 'password') _passwordError = errorKey;
    });

    _errorTimers[field]?.cancel();
    if (errorKey != null) {
      _errorTimers[field] = Timer(const Duration(seconds: 15), () {
        if (mounted) {
          setState(() {
            if (field == 'username') _usernameError = null;
            if (field == 'password') _passwordError = null;
          });
        }
      });
    }
  }

  void _clearAllErrors() {
    _errorTimers.forEach((_, timer) => timer?.cancel());
    setState(() {
      _usernameError = null;
      _passwordError = null;
    });
  }

  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  void _onUsernameChanged() {
    if (_usernameError != null) {
      setState(() => _usernameError = null);
    }
    _checkSecurityStatus();
  }

  void _onPasswordChanged() {
    if (_passwordError != null) {
      setState(() => _passwordError = null);
    }
  }

  void _checkSecurityStatus() async {
    final status = await LoginSecurityManager.checkStatus(_usernameController.text.trim());
    if (mounted) {
      setState(() {
        _securityStatus = status;
        if (status.isLocked && status.lockoutUntil != null) {
          final now = DateTime.now();
          final diff = status.lockoutUntil!.difference(now).inSeconds;
          if (diff > 0) {
            _secondsRemaining = diff;
            _startLockoutTimer();
          } else {
            // Lockout expired, reset immediately
            _secondsRemaining = 0;
            _securityStatus = SecurityStatus(attempts: 0, isLocked: false);
          }
        } else {
          _secondsRemaining = 0;
        }
      });
    }
  }

  void _startLockoutTimer() {
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        if (_secondsRemaining > 0) {
          setState(() => _secondsRemaining--);
        } else {
          timer.cancel();
          _checkSecurityStatus();
        }
      } else {
        timer.cancel();
      }
    });
  }

  void _handleLogin() async {
    _validateUsername();
    _validatePassword();

    if (_usernameError != null || _passwordError != null) return;

    final username = _usernameController.text.trim();
    final status = await LoginSecurityManager.checkStatus(username);
    if (status.isLocked) {
      _checkSecurityStatus();
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await ApiService().login(
        username,
        _passwordController.text,
      );

      if (response.data['success'] == true) {
        await LoginSecurityManager.resetAttempts(username);
        if (!mounted) return;
        
        final user = response.data['user'];
        final role = user['role'];
        final name = user['name'] ?? username;

        // Save User to Session
        await SessionManager.saveUser(user);

        // Check for permissions on mobile devices before proceeding
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          bool hasPermissions = await _checkAndRequestPermissions();
          if (!hasPermissions) {
            setState(() => _isLoading = false);
            return;
          }
        }

        // Show Welcome Message
        if (mounted) {
          CustomSnackBar.show(
            context,
            message: AppLocalizations.get('welcome_name').replaceFirst('{name}', name),
          );
        }

        if (role == 'admin') {
          Navigator.pushReplacementNamed(context, '/admin_dashboard');
        } else if (role == 'driver') {
          Navigator.pushReplacementNamed(context, '/driver_dashboard', arguments: user);
        } else if (role == 'resident') {
          Navigator.pushReplacementNamed(context, '/resident_dashboard', arguments: user);
        }
      } else {
        // Check if user exists using separate API calls as requested
        bool userExists = false;
        try {
          final userCheck = await ApiService().checkUsername(username);
          final emailCheck = await ApiService().checkEmail(username);
          if (userCheck.data['success'] == true || emailCheck.data['success'] == true) {
            userExists = true;
          }
        } catch (e) {
          debugPrint("Account existence check error: $e");
          // If check fails, we proceed with generic message
        }

        if (userExists) {
          final newStatus = await LoginSecurityManager.recordFailedAttempt(username);
          _checkSecurityStatus();
          if (!mounted) return;
          
          String msg;
          if (newStatus.isLocked) {
            msg = AppLocalizations.get('err_account_locked_final');
          } else {
            msg = AppLocalizations.get('err_incorrect_password_attempts')
                .replaceFirst('{attempts}', newStatus.remainingAttempts.toString());
          }
          
          CustomSnackBar.show(
            context,
            message: msg,
            isError: true,
          );
        } else {
          if (!mounted) return;
          CustomSnackBar.show(
            context,
            message: AppLocalizations.get('err_auth_failed'),
            isError: true,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: AppLocalizations.get('err_connection'),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _checkAndRequestPermissions() async {
    // 1. Trigger Native Location Prompt
    try {
      PermissionStatus locStatus = await Permission.location.request();
      
      if (!locStatus.isGranted && !locStatus.isLimited) {
        if (locStatus.isPermanentlyDenied) {
          if (mounted) {
            CustomSnackBar.show(context, message: "Location is mandatory. Please enable it in Settings.", isError: true);
            await Future.delayed(const Duration(seconds: 2));
            await openAppSettings();
          }
        } else {
          if (mounted) {
            CustomSnackBar.show(context, message: "Location access is required to use the tracker.", isError: true);
          }
        }
        return false;
      }
    } catch (e) {
      debugPrint("Location permission error: $e");
    }

    // Small delay to ensure OS handles the next prompt correctly
    await Future.delayed(const Duration(milliseconds: 500));

    // 2. Trigger Native Notification Prompt
    try {
      PermissionStatus statusBefore = await Permission.notification.status;
      
      if (statusBefore.isDenied || statusBefore.isProvisional) {
        PermissionStatus statusAfter = await Permission.notification.request();
        
        if (statusAfter.isGranted) {
          await SessionManager.setAppNotificationsEnabled(true);
          await SessionManager.setNotifPermissionRequested(true);
          
          // User clicked ALLOW -> Redirect to App Settings as requested
          if (mounted) {
            CustomSnackBar.show(context, message: "Redirecting to system settings...", isError: false);
            await Future.delayed(const Duration(seconds: 1));
            await openAppSettings();
          }
        } else {
          // User clicked DON'T ALLOW
          await SessionManager.setAppNotificationsEnabled(false);
          await SessionManager.setNotifPermissionRequested(true);
        }
      } else if (statusBefore.isGranted) {
        await SessionManager.setAppNotificationsEnabled(true);
      }
      
    } catch (e) {
      debugPrint("Notification permission error: $e");
    }

    return true;
  }

  // --- REMOVED: _showPermissionDialog helper as requested ---


  void _showLanguageModal() {
    final bool isWide = Responsive.isTablet(context) || Responsive.isDesktop(context);
    
    if (isWide) {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.white,
          elevation: 24,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: _buildLanguageContent(context),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.white,
        elevation: 16,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (context) => _buildLanguageContent(context),
      );
    }
  }

  Widget _buildLanguageContent(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppLocalizations.get('select_language'),
                style: TextStyle(
                  fontSize: ResponsiveText.getFontSize(context, 20),
                  fontWeight: FontWeight.w900,
                  color: AppColors.tealText,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.grey),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.get('language_selection_desc'),
            style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 0),
            child: Divider(height: 32),
          ),
          _buildLanguageItem(context, 'English (UK)', AppLanguage.en),
          _buildLanguageItem(context, 'Filipino', AppLanguage.fil),
          _buildLanguageItem(context, 'Bisaya', AppLanguage.bis),
        ],
      ),
    );
  }

  Widget _buildLanguageItem(BuildContext context, String label, AppLanguage lang) {
    bool isSelected = AppLocalizations.currentLanguage.value == lang;
    return ListTile(
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.inputLabel)),
      leading: Icon(Icons.language_rounded, color: isSelected ? AppColors.tealText : Colors.grey),
      trailing: isSelected ? const Icon(Icons.check_circle, color: AppColors.tealText) : null,
      onTap: () async {
        await AppLocalizations.setLanguage(lang);
        if (context.mounted) {
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

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double screenHeight = MediaQuery.of(context).size.height;
    final double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final bool isMobile = Responsive.isMobile(context);
    
    return AnimatedAuthBackground(
      resizeToAvoidBottomInset: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: Stack(
            children: [
              // Main Scrollable Content
              Positioned.fill(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                    horizontal: screenWidth > 600 ? screenWidth * 0.1 : 24,
                    vertical: screenHeight * 0.02,
                  ),
                  child: Column(
                    children: [
                      SizedBox(height: screenHeight * 0.02),
                      _buildBranding(),
                      SizedBox(height: screenHeight * 0.03),
                      FadeSlideEntrance(
                        key: const ValueKey('login_form_container'),
                        delay: const Duration(milliseconds: 400),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 450),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: screenWidth > 600 ? 32 : 24,
                                vertical: screenHeight * 0.02,
                              ),
                              decoration: AppDecorations.authCardDecoration(),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (_securityStatus?.isLocked == true && _secondsRemaining > 0) _buildLockoutCard(),
                                    _buildRefinedTextField(
                                      label: AppLocalizations.get('username_email'),
                                      hint: AppLocalizations.get('enter_credentials'),
                                      controller: _usernameController,
                                      icon: Icons.person_outline_rounded,
                                      focus: _usernameFocus,
                                      error: _usernameError,
                                    ),
                                    const SizedBox(height: 16),
                                    _buildRefinedTextField(
                                      label: AppLocalizations.get('password'),
                                      hint: AppLocalizations.get('enter_password'),
                                      controller: _passwordController,
                                      isPassword: true,
                                      obscureText: _obscureText,
                                      onTogglePassword: () => setState(() => _obscureText = !_obscureText),
                                      icon: Icons.lock_outline_rounded,
                                      focus: _passwordFocus,
                                      error: _passwordError,
                                    ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: _HoverZoomLink(
                                        onTap: () {
                                          _clearAllErrors();
                                          setState(() => _currentLogoIcon = Icons.lock_reset_rounded);
                                          Future.delayed(const Duration(milliseconds: 150), () {
                                            if (!mounted) return;
                                            Navigator.push(
                                              context,
                                              PageRouteBuilder(
                                                pageBuilder: (context, animation, secondaryAnimation) => const ForgotPasswordScreen(),
                                                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                                  return FadeTransition(
                                                    opacity: CurvedAnimation(parent: animation, curve: Curves.easeIn),
                                                    child: child,
                                                  );
                                                },
                                                transitionDuration: const Duration(milliseconds: 500),
                                              ),
                                            ).then((_) {
                                              if (mounted) setState(() => _currentLogoIcon = Icons.local_shipping_rounded);
                                            });
                                          });
                                        },
                                        child: Text(
                                          AppLocalizations.get('forgot_password'),
                                          style: ResponsiveText.link(context, color: AppColors.tealLink).copyWith(fontSize: ResponsiveText.getFontSize(context, 13)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    HoverActionButton(
                                      text: AppLocalizations.get('sign_in'),
                                      loadingText: AppLocalizations.get('confirming_credentials'),
                                      onTap: _handleLogin,
                                      isLoading: _isLoading,
                                    ),
                                    const SizedBox(height: 16),
                                    Align(
                                      alignment: Alignment.center,
                                      child: Wrap(
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                          children: [
                                            Text(AppLocalizations.get('dont_have_account'), style: ResponsiveText.body(context)),
                                            const SizedBox(width: 8),
                                            _HoverZoomLink(
                                              onTap: () {
                                                _clearAllErrors();
                                                setState(() => _currentLogoIcon = Icons.person_add_rounded);
                                                Future.delayed(const Duration(milliseconds: 150), () {
                                                  if (!mounted) return;
                                                  Navigator.push(
                                                    context,
                                                    PageRouteBuilder(
                                                      pageBuilder: (context, animation, secondaryAnimation) => const RegisterChoiceScreen(),
                                                      transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                                        return FadeTransition(
                                                          opacity: CurvedAnimation(parent: animation, curve: Curves.easeIn),
                                                          child: child,
                                                        );
                                                      },
                                                      transitionDuration: const Duration(milliseconds: 500),
                                                    ),
                                                  ).then((_) {
                                                    if (mounted) setState(() => _currentLogoIcon = Icons.local_shipping_rounded);
                                                  });
                                                });
                                              },
                                              child: Text(AppLocalizations.get('create_account'), style: ResponsiveText.link(context)),
                                            ),
                                          ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Footer inside scroll for Web/Tablet
                      if (!isMobile) ...[
                        const SizedBox(height: 60),
                        _buildFooter(),
                        const SizedBox(height: 20),
                      ],
                      // Spacer for the keyboard - aligns form with keyboard top
                      SizedBox(height: keyboardHeight),
                      // Extra buffer for mobile fixed footer when keyboard is closed
                      if (isMobile && keyboardHeight == 0) const SizedBox(height: 120),
                    ],
                  ),
                ),
              ),
              
              // Fixed Footer for Mobile
              if (isMobile)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 20,
                  child: FadeSlideEntrance(
                    delay: const Duration(milliseconds: 600),
                    child: _buildFooter(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _validateUsername() {
    final val = _usernameController.text.trim();
    _setErrorWithTimer('username', val.isEmpty ? 'err_username_email' : null);
  }

  void _validatePassword() {
    final val = _passwordController.text;
    _setErrorWithTimer('password', val.isEmpty ? 'err_password_req' : null);
  }

  Widget _buildLockoutCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.red.shade200, width: 1.5)),
      child: Column(children: [
        Row(children: [Icon(Icons.lock_clock_rounded, color: Colors.red.shade900, size: 20), const SizedBox(width: 12), Expanded(child: Text(AppLocalizations.get('security_lockout'), style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold)))]),
        const SizedBox(height: 8),
        Text(AppLocalizations.get('err_account_locked_final'), textAlign: TextAlign.center, style: TextStyle(color: Colors.red.shade900, fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Text('${(_secondsRemaining ~/ 60).toString().padLeft(2, '0')}:${(_secondsRemaining % 60).toString().padLeft(2, '0')}', style: TextStyle(color: Colors.red.shade900, fontSize: 22, fontWeight: FontWeight.w900, fontFamily: 'monospace')),
        const SizedBox(height: 12),
        _HoverZoomLink(onTap: () => Navigator.pushNamed(context, '/forgot_password'), child: Text(AppLocalizations.get('reset_password_link'), style: TextStyle(color: Colors.red.shade900, fontSize: 13, fontWeight: FontWeight.bold, decoration: TextDecoration.underline))),
      ]),
    );
  }

  Widget _buildBranding() {
    return Column(
      children: [
        Hero(
          tag: 'app_logo',
          flightShuttleBuilder: (flightContext, animation, flightDirection, fromHeroContext, toHeroContext) {
            final Hero fromHero = fromHeroContext.widget as Hero;
            final Hero toHero = toHeroContext.widget as Hero;
            final Widget fromChild = fromHero.child;
            final Widget toChild = toHero.child;

            return AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                final double scale = 1.0 + (0.1 * (1.0 - (animation.value - 0.5).abs() * 2));
                final double rotation = (flightDirection == HeroFlightDirection.push ? 1 : -1) * 
                                      (1.0 - animation.value) * 0.2;
                
                return Transform.scale(
                  scale: scale,
                  child: Transform.rotate(
                    angle: rotation,
                    child: Material(
                      type: MaterialType.transparency,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Opacity(
                            opacity: (1.0 - animation.value).clamp(0.0, 1.0),
                            child: fromChild,
                          ),
                          Opacity(
                            opacity: animation.value.clamp(0.0, 1.0),
                            child: toChild,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
          child: Container(
            width: ResponsiveText.getIconSize(context, 80),
            height: ResponsiveText.getIconSize(context, 80),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.loginButtonStart, AppColors.loginButtonEnd], begin: Alignment.topLeft, end: Alignment.bottomRight),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: AppColors.loginButtonEnd.withAlpha(60), blurRadius: 20, offset: const Offset(0, 10)),
              ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              ),
              child: Icon(
                _currentLogoIcon, 
                key: ValueKey(_currentLogoIcon),
                size: ResponsiveText.getIconSize(context, 40), 
                color: Colors.white
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Hero(
          tag: 'app_name',
          child: Material(
            color: Colors.transparent,
            child: Text(
              AppLocalizations.get('garbage_tracker'), 
              textAlign: TextAlign.center,
              style: ResponsiveText.brandingTitle(context),
            ),
          ),
        ),
        FadeSlideEntrance(
          delay: const Duration(milliseconds: 200),
          child: Text(
            AppLocalizations.get('welcome_back'), 
            textAlign: TextAlign.center,
            style: ResponsiveText.brandingSubtitle(context),
          ),
        ),
        const SizedBox(height: 20),
        FadeSlideEntrance(
          delay: const Duration(milliseconds: 300),
          child: _HoverZoomLink(
            onTap: _showLanguageModal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppLocalizations.currentLanguage.value == AppLanguage.en ? 'English (UK)' :
                  (AppLocalizations.currentLanguage.value == AppLanguage.fil ? 'Filipino' : 'Bisaya'),
                  style: const TextStyle(color: AppColors.textGray, fontWeight: FontWeight.w700, fontSize: 13, decoration: TextDecoration.underline),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textGray, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Column(children: [
      Wrap(alignment: WrapAlignment.center, spacing: 16, children: [
        _HoverZoomLink(onTap: () => LegalAgreementDialog.show(context, isTerms: true), child: Text(AppLocalizations.get('terms_conditions'), style: ResponsiveText.footer(context, bold: true).copyWith(decoration: TextDecoration.underline))),
        Text('•', style: ResponsiveText.footer(context)),
        _HoverZoomLink(onTap: () => LegalAgreementDialog.show(context, isTerms: false), child: Text(AppLocalizations.get('privacy_policy'), style: ResponsiveText.footer(context, bold: true).copyWith(decoration: TextDecoration.underline))),
      ]),
      const SizedBox(height: 16),
      Text(AppLocalizations.get('brgy_footer'), style: ResponsiveText.footer(context, bold: true)),
      Text(AppLocalizations.get('all_rights_reserved'), style: ResponsiveText.footer(context, size: 10)),
    ]);
  }

  Widget _buildRefinedTextField({required String label, required String hint, required TextEditingController controller, IconData? icon, bool isPassword = false, bool obscureText = false, VoidCallback? onTogglePassword, FocusNode? focus, String? error}) {
    bool hasFocus = focus?.hasFocus ?? false;
    String? localizedError = error != null ? AppLocalizations.get(error) : null;
    
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(left: 4, bottom: 6), child: Text(label, style: ResponsiveText.inputLabel(context))),
      AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            if (hasFocus)
              BoxShadow(
                color: AppColors.tealText.withAlpha(30),
                blurRadius: 12,
                spreadRadius: 2,
              )
          ],
        ),
        child: TextFormField(
          controller: controller, focusNode: focus, obscureText: isPassword ? obscureText : false,
          cursorColor: const Color(0xFF424242),
          style: ResponsiveText.inputText(context),
          textInputAction: isPassword ? TextInputAction.done : TextInputAction.next,
          onFieldSubmitted: (_) { if (isPassword) _handleLogin(); },
          decoration: InputDecoration(
            hintText: hint, hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14, fontWeight: FontWeight.w400),
            prefixIcon: icon != null ? Icon(icon, color: hasFocus ? AppColors.tealText : AppColors.tealText.withAlpha(150), size: 20) : null,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), filled: true, fillColor: hasFocus ? Colors.white : Colors.grey.shade50,
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: localizedError != null ? Colors.redAccent : Colors.grey.shade200, width: 1.2)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: localizedError != null ? Colors.redAccent : AppColors.tealText, width: 2.0)),
            suffixIcon: isPassword ? 
              IconButton(
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Icon(obscureText ? Icons.visibility_off_rounded : Icons.visibility_rounded, key: ValueKey(obscureText), color: hasFocus ? AppColors.tealText : Colors.grey.shade500, size: 20),
                ),
                onPressed: onTogglePassword
              ) : null,
          ),
        ),
      ),
      if (localizedError != null) Padding(padding: const EdgeInsets.only(top: 4, left: 4), child: Text(localizedError, style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w600))),
    ]);
  }
}

class _HoverZoomLink extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _HoverZoomLink({required this.child, required this.onTap});
  @override
  State<_HoverZoomLink> createState() => _HoverZoomLinkState();
}
class _HoverZoomLinkState extends State<_HoverZoomLink> {
  bool _isActive = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isActive = true),
      onExit: (_) => setState(() => _isActive = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isActive = true),
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
