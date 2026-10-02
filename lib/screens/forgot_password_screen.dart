import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../api/api_service.dart';
import '../widgets/legal_agreement_dialog.dart';
import '../widgets/animated_auth_background.dart';
import '../widgets/hover_action_button.dart';
import '../widgets/fade_slide_entrance.dart';
import '../utils/app_localizations.dart';
import '../utils/route_persistence_manager.dart';
import '../utils/responsive_text.dart';
import '../utils/responsive.dart';
import '../widgets/custom_snackbar.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  final FocusNode _emailFocus = FocusNode();
  final FocusNode _otpFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmPasswordFocus = FocusNode();

  String? _emailError;
  String? _otpError;
  String? _passwordError;
  String? _confirmPasswordError;

  final _formKey = GlobalKey<FormState>();
  final ApiService _apiService = ApiService();

  int _currentStep = 1; // 1: Email, 2: OTP, 3: New Password
  bool _isLoading = false;
  bool _isResending = false;
  bool _obscurePassword = true;

  // OTP Timer Logic
  Timer? _otpTimer;
  int _timerSecondsRemaining = 180; // 3 minutes
  bool _canResend = false;
  final Map<String, Timer?> _errorTimers = {};

  @override
  void initState() {
    super.initState();
    RoutePersistenceManager.saveLastRoute('/forgot_password');
    _loadState();
    AppLocalizations.currentLanguage.addListener(_onLanguageChanged);
    
    // Real-time listeners
    _emailController.addListener(_onEmailChanged);
    _otpController.addListener(_onOtpChanged);
    _passwordController.addListener(_onPasswordChanged);
    _confirmPasswordController.addListener(_onConfirmPasswordChanged);

    _emailFocus.addListener(() => setState(() {}));
    _otpFocus.addListener(() => setState(() {}));
    _passwordFocus.addListener(() { 
      if (!_passwordFocus.hasFocus) _validatePassword();
      setState(() {});
    });
    _confirmPasswordFocus.addListener(() { 
      if (!_confirmPasswordFocus.hasFocus) _validateConfirmPassword();
      setState(() {});
    });
  }

  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  void _onEmailChanged() {
    if (_emailError != null) {
      setState(() => _emailError = null);
    }
  }

  void _onOtpChanged() {
    if (_otpError != null) {
      setState(() => _otpError = null);
    }
  }

  void _onPasswordChanged() {
    if (_passwordError != null) {
      setState(() => _passwordError = null);
    }
  }

  void _onConfirmPasswordChanged() {
    if (_confirmPasswordError != null) {
      setState(() => _confirmPasswordError = null);
    }
  }

  @override
  void dispose() {
    _errorTimers.forEach((_, timer) => timer?.cancel());
    _emailController.removeListener(_onEmailChanged);
    _otpController.removeListener(_onOtpChanged);
    _passwordController.removeListener(_onPasswordChanged);
    _confirmPasswordController.removeListener(_onConfirmPasswordChanged);

    _emailFocus.dispose();
    _otpFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    _otpTimer?.cancel();
    AppLocalizations.currentLanguage.removeListener(_onLanguageChanged);
    super.dispose();
  }

  Future<void> _loadState() async {
    final state = await RoutePersistenceManager.getForgotPasswordState();
    if (state != null && mounted) {
      setState(() {
        _currentStep = state['step'];
        _emailController.text = state['email'];
      });
      if (_currentStep == 2) _startOtpTimer();
    }
  }

  void _saveState() {
    RoutePersistenceManager.saveForgotPasswordState(_currentStep, _emailController.text.trim());
  }

  void _setErrorWithTimer(String field, String? errorKey) {
    setState(() {
      if (field == 'email') _emailError = errorKey;
      if (field == 'otp') _otpError = errorKey;
      if (field == 'password') _passwordError = errorKey;
      if (field == 'confirmPassword') _confirmPasswordError = errorKey;
    });

    _errorTimers[field]?.cancel();
    if (errorKey != null) {
      _errorTimers[field] = Timer(const Duration(seconds: 15), () {
        if (mounted) {
          setState(() {
            if (field == 'email') _emailError = null;
            if (field == 'otp') _otpError = null;
            if (field == 'password') _passwordError = null;
            if (field == 'confirmPassword') _confirmPasswordError = null;
          });
        }
      });
    }
  }

  void _clearAllErrors() {
    _errorTimers.forEach((_, timer) => timer?.cancel());
    setState(() {
      _emailError = null;
      _otpError = null;
      _passwordError = null;
      _confirmPasswordError = null;
    });
  }

  void _startOtpTimer() {
    _otpTimer?.cancel();
    setState(() {
      _timerSecondsRemaining = 180;
      _canResend = false;
    });
    _otpTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        if (_timerSecondsRemaining > 0) {
          setState(() => _timerSecondsRemaining--);
        } else {
          timer.cancel();
          setState(() {
            _canResend = true;
            _otpError = AppLocalizations.get('err_otp_expired');
          });
        }
      } else {
        timer.cancel();
      }
    });
  }

  String _formatTimer(int seconds) {
    final int m = seconds ~/ 60;
    final int s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _validateEmail() {
    final val = _emailController.text.trim();
    if (val.isEmpty) {
      _setErrorWithTimer('email', 'err_email_reg');
    } else if (!RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(val)) {
      _setErrorWithTimer('email', 'err_email_format');
    } else {
      _setErrorWithTimer('email', null);
    }
  }

  void _validateOtp() {
    final val = _otpController.text;
    if (val.isEmpty) {
      _setErrorWithTimer('otp', 'err_otp_req');
    } else if (val.length < 6) {
      _setErrorWithTimer('otp', 'err_otp_len');
    } else if (_timerSecondsRemaining <= 0) {
      _setErrorWithTimer('otp', 'err_otp_expired');
    } else {
      _setErrorWithTimer('otp', null);
    }
  }

  void _validatePassword() {
    final val = _passwordController.text;
    if (val.isEmpty) {
      _setErrorWithTimer('password', 'err_password_reg');
    } else if (val.length < 6) {
      _setErrorWithTimer('password', 'err_pass_len');
    } else {
      bool hasUpper = val.contains(RegExp(r'[A-Z]'));
      bool hasLower = val.contains(RegExp(r'[a-z]'));
      bool hasDigit = val.contains(RegExp(r'[0-9]'));
      bool hasSpecial = val.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));

      if (!hasUpper || !hasLower || !hasDigit || !hasSpecial) {
        _setErrorWithTimer('password', 'err_pass_complex');
      } else {
        _setErrorWithTimer('password', null);
      }
    }
  }

  void _validateConfirmPassword() {
    if (_confirmPasswordController.text != _passwordController.text) {
      _setErrorWithTimer('confirmPassword', 'err_pass_match');
    } else {
      _setErrorWithTimer('confirmPassword', null);
    }
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
                    horizontal: 24,
                    vertical: screenHeight * 0.02,
                  ),
                  child: Column(
                    children: [
                      // Header inside scroll (fixed top space)
                      _buildHeader(),
                      
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: screenWidth > 600 ? screenWidth * 0.08 : 0,
                        ),
                        child: Column(
                          children: [
                            SizedBox(height: screenHeight * 0.08),
                            _buildBranding(),
                            SizedBox(height: screenHeight * 0.03),

                            FadeSlideEntrance(
                              key: const ValueKey('forgot_password_main_card'),
                              delay: const Duration(milliseconds: 200),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 450),
                                  child: _buildMainCard(screenWidth, screenHeight),
                                ),
                              ),
                            ),

                            // Footer inside scroll for Web/Tablet
                            if (!isMobile) ...[
                              const SizedBox(height: 60),
                              _buildFooter(),
                              const SizedBox(height: 20),
                            ],
                          ],
                        ),
                      ),

                      // Spacer for the keyboard
                      SizedBox(height: keyboardHeight),

                      // Extra buffer for mobile fixed footer
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
                    delay: const Duration(milliseconds: 700),
                    child: _buildFooter(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final bool isWide = Responsive.isTablet(context) || Responsive.isDesktop(context);
    return Padding(
      padding: EdgeInsets.only(
        top: 10, 
        bottom: 0,
        left: isWide ? 0 : 0, // Using the parent's padding of 24
        right: isWide ? 0 : 0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(200),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 4, offset: const Offset(0, 2))
                  ]
                ),
                child: IconButton(
                  icon: Icon(Icons.arrow_back_ios_new_rounded, color: const Color(0xFF00796B), size: ResponsiveText.getIconSize(context, 20)),
                  onPressed: () {
                    if (_currentStep > 1) {
                      _clearAllErrors();
                      setState(() {
                        _currentStep--;
                        if (_currentStep == 1) _otpTimer?.cancel();
                      });
                      _saveState();
                    } else {
                      _clearAllErrors();
                      RoutePersistenceManager.clearForgotPasswordState();
                      RoutePersistenceManager.clearLastRoute();
                      Navigator.pop(context);
                    }
                  },
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text(
                    _currentStep == 1 ? AppLocalizations.get('verification') : (_currentStep == 2 ? AppLocalizations.get('enter_token') : AppLocalizations.get('new_password')),
                    style: ResponsiveText.screenHeader(context),
                  ),
                  Text(
                    AppLocalizations.get('account_recovery'),
                    style: TextStyle(
                      color: AppColors.textGray, 
                      fontSize: ResponsiveText.getFontSize(context, 13), 
                      fontWeight: FontWeight.w500
                    ),
                  ),
                ],
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppColors.tealText.withAlpha(30), shape: BoxShape.circle),
            child: Icon(Icons.security_rounded, color: AppColors.tealText, size: ResponsiveText.getIconSize(context, 28)),
          ),
        ],
      ),
    );
  }

  Widget _buildBranding() {
    IconData icon = Icons.lock_reset_rounded;
    String brandingText = "Identity Verification";
    if (_currentStep == 2) {
      icon = Icons.vibration_rounded;
      brandingText = "Security Authentication";
    }
    if (_currentStep == 3) {
      icon = Icons.security_rounded;
      brandingText = "Password Restoration";
    }

    final double containerSize = ResponsiveText.getIconSize(context, 80);
    final double iconSize = ResponsiveText.getIconSize(context, 40);

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
            width: containerSize,
            height: containerSize,
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
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              ),
              child: Icon(
                icon, 
                key: ValueKey(icon),
                size: iconSize, 
                color: Colors.white
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          brandingText,
          textAlign: TextAlign.center,
          style: ResponsiveText.brandingTitle(context),
        ),
        Text(
          _currentStep == 1 ? AppLocalizations.get('step_1_verify') : (_currentStep == 2 ? AppLocalizations.get('step_2_token') : AppLocalizations.get('step_3_secure')),
          textAlign: TextAlign.center,
          style: ResponsiveText.brandingSubtitle(context),
        ),
      ],
    );
  }

  Widget _buildMainCard(double screenWidth, double screenHeight) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth > 600 ? 32 : 24, 
        vertical: screenHeight * 0.03,
      ),
      decoration: AppDecorations.authCardDecoration(),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_currentStep == 1) _buildStep1Fields(),
            if (_currentStep == 2) _buildStep2Fields(),
            if (_currentStep == 3) _buildStep3Fields(),
            const SizedBox(height: 32),
            HoverActionButton(
              text: _currentStep == 1 ? AppLocalizations.get('send_verification') : (_currentStep == 2 ? AppLocalizations.get('verification_token') : AppLocalizations.get('reset_password')),
              loadingText: _currentStep == 1 ? AppLocalizations.get('verifying_email') : (_currentStep == 2 ? AppLocalizations.get('checking_token') : AppLocalizations.get('updating_password')),
              onTap: (_currentStep == 2 && _timerSecondsRemaining <= 0) ? null : _handleAction,
              isLoading: _isLoading,
            ),
            if (_currentStep == 2 && _timerSecondsRemaining <= 0) _buildResendSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildResendSection() {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Center(
        child: Column(
          children: [
            Text(
              AppLocalizations.get('didnt_receive_token'),
              style: const TextStyle(color: AppColors.textGray, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _isResending 
              ? const SizedBox(
                  height: 20, width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.tealText),
                )
              : _HoverZoomLink(
                  onTap: _canResend ? _resendToken : null,
                  child: Text(
                    AppLocalizations.get('resend_token'),
                    style: TextStyle(
                      color: _canResend ? AppColors.tealLink : Colors.grey.shade400,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep1Fields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRefinedTextField(
          label: AppLocalizations.get('email_address'),
          controller: _emailController,
          focus: _emailFocus,
          hint: AppLocalizations.get('enter_reg_email'),
          icon: Icons.email_outlined,
          error: _emailError,
          keyboardType: TextInputType.emailAddress,
        ),
      ],
    );
  }

  Widget _buildStep2Fields() {
    bool isUrgent = _timerSecondsRemaining <= 30;
    bool isCritical = _timerSecondsRemaining <= 10;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                AppLocalizations.get('verification_token'),
                style: ResponsiveText.inputLabel(context),
              ),
            ),
            if (_timerSecondsRemaining > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8, right: 4),
                child: Text(
                  '${AppLocalizations.get('expires_in')}: ${_formatTimer(_timerSecondsRemaining)}',
                  style: ResponsiveText.body(context, color: isCritical ? Colors.redAccent : (isUrgent ? Colors.orange.shade800 : AppColors.textGray)).copyWith(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
          ],
        ),
        _buildRefinedTextField(
          label: "", // Already handled in Row
          controller: _otpController,
          focus: _otpFocus,
          hint: '000000',
          icon: Icons.vpn_key_outlined,
          error: _otpError,
          keyboardType: TextInputType.number,
          maxLength: 6,
          isOtp: true,
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            "${AppLocalizations.get('code_sent_to')}: ${_emailController.text}",
            style: const TextStyle(fontSize: 12, color: AppColors.textGray, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildStep3Fields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRefinedTextField(
          label: AppLocalizations.get('new_password'),
          controller: _passwordController,
          focus: _passwordFocus,
          hint: AppLocalizations.get('enter_password'),
          icon: Icons.lock_outline_rounded,
          error: _passwordError,
          isPassword: true,
          obscureText: _obscurePassword,
          onTogglePassword: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
        const SizedBox(height: 24),
        _buildRefinedTextField(
          label: AppLocalizations.get('confirm_password'),
          controller: _confirmPasswordController,
          focus: _confirmPasswordFocus,
          hint: AppLocalizations.get('confirm_your_password'),
          icon: Icons.lock_clock_outlined,
          error: _confirmPasswordError,
          isPassword: true,
          obscureText: _obscurePassword,
        ),
      ],
    );
  }

  Widget _buildRefinedTextField({required String label, required TextEditingController controller, required FocusNode focus, required String hint, required IconData icon, String? error, bool isPassword = false, bool obscureText = false, VoidCallback? onTogglePassword, TextInputType? keyboardType, int? maxLength, bool isOtp = false}) {
    bool hasFocus = focus.hasFocus;
    String? localizedError = error != null ? AppLocalizations.get(error) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty)
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
            controller: controller,
            focusNode: focus,
            obscureText: isPassword ? obscureText : false,
            keyboardType: keyboardType,
            maxLength: maxLength,
            cursorColor: const Color(0xFF424242),
            textAlign: isOtp ? TextAlign.center : TextAlign.start,
            style: TextStyle(
              fontSize: isOtp ? 24 : 15,
              fontWeight: isOtp ? FontWeight.w900 : FontWeight.w600,
              color: isOtp ? AppColors.tealText : AppColors.inputLabel,
              letterSpacing: isOtp ? 8 : null,
            ),
            decoration: InputDecoration(
              counterText: "",
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14, fontWeight: FontWeight.w400, letterSpacing: isOtp ? 0 : null),
              prefixIcon: Icon(icon, color: hasFocus ? AppColors.tealText : AppColors.tealText.withAlpha(150), size: ResponsiveText.getIconSize(context, 20)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              filled: true,
              fillColor: hasFocus ? Colors.white : Colors.grey.shade50,
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: localizedError != null ? Colors.redAccent : Colors.grey.shade200, width: 1.2)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: localizedError != null ? Colors.redAccent : AppColors.tealText, width: 2.0)),
              suffixIcon: isPassword ? IconButton(
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Icon(obscureText ? Icons.visibility_off_rounded : Icons.visibility_rounded, key: ValueKey(obscureText), color: hasFocus ? AppColors.tealText : Colors.grey.shade500, size: 20),
                ),
                onPressed: onTogglePassword
              ) : null,
            ),
          ),
        ),
        if (localizedError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(localizedError, style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }

  void _handleAction() {
    if (_currentStep == 1) {
      _validateEmail();
      if (_emailError == null) _sendEmail();
    } else if (_currentStep == 2) {
      _validateOtp();
      if (_otpError == null) _verifyOTP();
    } else if (_currentStep == 3) {
      _validatePassword();
      _validateConfirmPassword();
      if (_passwordError == null && _confirmPasswordError == null) _resetPassword();
    }
  }

  void _sendEmail() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiService.forgotPassword(_emailController.text.trim());
      if (response.data['success'] == true) {
        _showSuccess(response.data['message'] ?? AppLocalizations.get('verifying_email'));
        setState(() => _currentStep = 2);
        _saveState();
        _startOtpTimer();
      } else {
        setState(() => _emailError = response.data['message'] ?? AppLocalizations.get('email_not_found'));
      }
    } catch (e) {
      _showConnectionError();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _resendToken() async {
    setState(() => _isResending = true);
    try {
      final response = await _apiService.forgotPassword(_emailController.text.trim());
      if (response.data['success'] == true) {
        _showSuccess(AppLocalizations.get('processing'));
        setState(() {
          _otpError = null;
          _otpController.clear();
        });
        _startOtpTimer();
      } else {
        _showError(AppLocalizations.get('err_general'));
      }
    } catch (e) {
      _showConnectionError();
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  void _verifyOTP() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiService.verifyOTP(_emailController.text.trim(), _otpController.text.trim());
      if (response.data['success'] == true) {
        _showSuccess(AppLocalizations.get('checking_token'));
        setState(() => _currentStep = 3);
        _saveState();
        _otpTimer?.cancel();
      } else {
        setState(() => _otpError = AppLocalizations.get('err_otp_req'));
      }
    } catch (e) {
      _showConnectionError();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _resetPassword() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiService.resetPassword(
        _emailController.text.trim(),
        _otpController.text.trim(),
        _passwordController.text,
      );
      if (response.data['success'] == true) {
        _showSuccess(AppLocalizations.get('updating_password'));
        RoutePersistenceManager.clearForgotPasswordState();
        RoutePersistenceManager.clearLastRoute();
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.pop(context);
        });
      } else {
        _showError(response.data['message'] ?? AppLocalizations.get('err_general'));
      }
    } catch (e) {
      _showConnectionError();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    CustomSnackBar.show(context, message: msg);
  }

  void _showError(String msg) {
    if (!mounted) return;
    CustomSnackBar.show(context, message: msg, isError: true);
  }

  void _showConnectionError() {
    if (!mounted) return;
    CustomSnackBar.show(
      context,
      message: AppLocalizations.get('err_network'),
      isError: true,
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          children: [
            _HoverZoomLink(
              onTap: () {
                _clearAllErrors();
                LegalAgreementDialog.show(context, isTerms: true);
              },
              child: Text(AppLocalizations.get('terms_conditions'), style: ResponsiveText.footer(context, bold: true).copyWith(decoration: TextDecoration.underline)),
            ),
            Text('•', style: ResponsiveText.footer(context)),
            _HoverZoomLink(
              onTap: () {
                _clearAllErrors();
                LegalAgreementDialog.show(context, isTerms: false);
              },
              child: Text(AppLocalizations.get('privacy_policy'), style: ResponsiveText.footer(context, bold: true).copyWith(decoration: TextDecoration.underline)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(AppLocalizations.get('brgy_footer'), style: ResponsiveText.footer(context, bold: true)),
        Text(AppLocalizations.get('all_rights_reserved'), style: ResponsiveText.footer(context, size: 10)),
      ],
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
