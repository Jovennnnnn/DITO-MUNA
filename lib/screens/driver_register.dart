import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../api/api_service.dart';
import '../utils/app_theme.dart';
import '../widgets/legal_agreement_dialog.dart';
import '../widgets/animated_auth_background.dart';
import '../widgets/hover_action_button.dart';
import '../widgets/fade_slide_entrance.dart';
import '../utils/app_localizations.dart';
import '../utils/responsive_text.dart';
import '../utils/responsive.dart';
import '../widgets/custom_snackbar.dart';

class DriverRegisterScreen extends StatefulWidget {
  const DriverRegisterScreen({super.key});

  @override
  State<DriverRegisterScreen> createState() => _DriverRegisterScreenState();
}

class _DriverRegisterScreenState extends State<DriverRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _licenseController = TextEditingController();
  final _phoneController = TextEditingController();
  final _truckController = TextEditingController();

  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmPasswordFocus = FocusNode();
  final FocusNode _fullNameFocus = FocusNode();
  final FocusNode _licenseFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();

  String? _usernameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;
  String? _fullNameError;
  String? _licenseError;
  String? _phoneError;

  bool _isLoading = false;
  bool _obs1 = true;
  bool _obs2 = true;
  bool _termsAccepted = false;
  final Map<String, Timer?> _errorTimers = {};
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    AppLocalizations.currentLanguage.addListener(_onLanguageChanged);
    
    // Real-time listeners
    _usernameController.addListener(_onUsernameChanged);
    _emailController.addListener(_onEmailChanged);
    _passwordController.addListener(_onPasswordChanged);
    _confirmPasswordController.addListener(_onConfirmPasswordChanged);
    _fullNameController.addListener(_onFullNameChanged);
    _phoneController.addListener(_onPhoneChanged);
    _licenseController.addListener(_onLicenseChanged);

    _usernameFocus.addListener(() { if (!_usernameFocus.hasFocus) _validateUsername(); setState(() {}); });
    _emailFocus.addListener(() { if (!_emailFocus.hasFocus) _validateEmail(); setState(() {}); });
    _passwordFocus.addListener(() { if (!_passwordFocus.hasFocus) _validatePassword(); setState(() {}); });
    _confirmPasswordFocus.addListener(() { if (!_confirmPasswordFocus.hasFocus) _validateConfirmPassword(); setState(() {}); });
    _fullNameFocus.addListener(() { if (!_fullNameFocus.hasFocus) _validateFullName(); setState(() {}); });
    _licenseFocus.addListener(() { if (!_licenseFocus.hasFocus) _validateLicense(); setState(() {}); });
    _phoneFocus.addListener(() { if (!_phoneFocus.hasFocus) _validatePhone(); setState(() {}); });
  }

  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  void _onEmailChanged() {
    if (_emailError != null) {
      setState(() => _emailError = null);
    }
  }

  void _onUsernameChanged() {
    if (_usernameError != null) {
      setState(() => _usernameError = null);
    }
  }

  void _onFullNameChanged() {
    if (_fullNameError != null) {
      setState(() => _fullNameError = null);
    }
  }

  void _onLicenseChanged() {
    if (_licenseError != null) {
      setState(() => _licenseError = null);
    }
  }

  void _onPhoneChanged() {
    if (_phoneError != null) {
      setState(() => _phoneError = null);
    }
  }

  void _onPasswordChanged() {
    if (_passwordError != null) {
      final val = _passwordController.text;
      if (val.length >= 6) {
        bool hasUpper = val.contains(RegExp(r'[A-Z]'));
        bool hasLower = val.contains(RegExp(r'[a-z]'));
        bool hasDigit = val.contains(RegExp(r'[0-9]'));
        bool hasSpecial = val.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
        if (hasUpper && hasLower && hasDigit && hasSpecial) {
          setState(() => _passwordError = null);
        }
      }
    }
  }

  void _onConfirmPasswordChanged() {
    if (_confirmPasswordError != null && _confirmPasswordController.text == _passwordController.text) {
      setState(() => _confirmPasswordError = null);
    }
  }

  @override
  void dispose() {
    _errorTimers.forEach((_, timer) => timer?.cancel());
    _usernameController.removeListener(_onUsernameChanged);
    _emailController.removeListener(_onEmailChanged);
    _passwordController.removeListener(_onPasswordChanged);
    _confirmPasswordController.removeListener(_onConfirmPasswordChanged);
    _fullNameController.removeListener(_onFullNameChanged);
    _phoneController.removeListener(_onPhoneChanged);
    _licenseController.removeListener(_onLicenseChanged);

    _usernameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    _fullNameFocus.dispose();
    _licenseFocus.dispose();
    _phoneFocus.dispose();
    AppLocalizations.currentLanguage.removeListener(_onLanguageChanged);
    super.dispose();
  }

  void _setErrorWithTimer(String field, String? errorKey) {
    setState(() {
      if (field == 'username') _usernameError = errorKey;
      if (field == 'email') _emailError = errorKey;
      if (field == 'password') _passwordError = errorKey;
      if (field == 'confirmPassword') _confirmPasswordError = errorKey;
      if (field == 'fullName') _fullNameError = errorKey;
      if (field == 'license') _licenseError = errorKey;
      if (field == 'phone') _phoneError = errorKey;
    });

    _errorTimers[field]?.cancel();
    if (errorKey != null) {
      _errorTimers[field] = Timer(const Duration(seconds: 15), () {
        if (mounted) {
          setState(() {
            if (field == 'username') _usernameError = null;
            if (field == 'email') _emailError = null;
            if (field == 'password') _passwordError = null;
            if (field == 'confirmPassword') _confirmPasswordError = null;
            if (field == 'fullName') _fullNameError = null;
            if (field == 'license') _licenseError = null;
            if (field == 'phone') _phoneError = null;
          });
        }
      });
    }
  }

  void _clearAllErrors() {
    _errorTimers.forEach((_, timer) => timer?.cancel());
    setState(() {
      _usernameError = null;
      _emailError = null;
      _passwordError = null;
      _confirmPasswordError = null;
      _fullNameError = null;
      _licenseError = null;
      _phoneError = null;
    });
  }

  Future<void> _validateUsername() async {
    final val = _usernameController.text.trim();
    if (val.isEmpty) {
      _setErrorWithTimer('username', 'err_username_reg');
      return;
    }
    try {
      final res = await _apiService.checkUsername(val);
      if (res.data['success'] == true) {
        _setErrorWithTimer('username', 'err_username_taken');
      } else {
        _setErrorWithTimer('username', null);
      }
    } catch (e) {
      debugPrint("Check username error: $e");
    }
  }

  Future<void> _validateEmail() async {
    final val = _emailController.text.trim();
    if (val.isEmpty) {
      _setErrorWithTimer('email', 'err_email_req_reg');
      return;
    }
    if (!RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(val)) {
      _setErrorWithTimer('email', 'err_email_format');
      return;
    }
    try {
      final res = await _apiService.checkEmail(val);
      if (res.data['success'] == true) {
        _setErrorWithTimer('email', 'err_email_taken');
      } else {
        _setErrorWithTimer('email', null);
      }
    } catch (e) {
      debugPrint("Check email error: $e");
    }
  }

  void _validatePassword() {
    final val = _passwordController.text;
    if (val.isEmpty) {
      _setErrorWithTimer('password', 'err_password_reg');
      return;
    }
    if (val.length < 6) {
      _setErrorWithTimer('password', 'err_pass_len');
      return;
    }
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

  void _validateConfirmPassword() {
    if (_confirmPasswordController.text != _passwordController.text) {
      _setErrorWithTimer('confirmPassword', 'err_pass_match');
    } else {
      _setErrorWithTimer('confirmPassword', null);
    }
  }

  void _validateFullName() {
    final val = _fullNameController.text.trim();
    if (val.isEmpty) {
      _setErrorWithTimer('fullName', 'err_name_req');
      return;
    }
    if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(val)) {
      _setErrorWithTimer('fullName', 'err_name_format');
    } else {
      _setErrorWithTimer('fullName', null);
    }
  }

  void _validateLicense() {
    final val = _licenseController.text.trim();
    if (val.isEmpty) {
      _setErrorWithTimer('license', 'err_license_req');
      return;
    }
    if (!RegExp(r'^[a-zA-Z0-9!@#$%^&*(),.?":{}|<> -]+$').hasMatch(val)) {
      _setErrorWithTimer('license', 'err_license_format');
    } else {
      _setErrorWithTimer('license', null);
    }
  }

  Future<void> _validatePhone() async {
    final val = _phoneController.text.trim();
    if (val.isEmpty) {
      _setErrorWithTimer('phone', 'err_phone_req');
      return;
    }
    if (!RegExp(r'^(09|63)\d{9}$').hasMatch(val)) {
      _setErrorWithTimer('phone', 'err_phone_format');
      return;
    }
    try {
      final res = await _apiService.checkPhone(val);
      if (res.data['success'] == true) {
        _setErrorWithTimer('phone', 'err_phone_taken');
      } else {
        _setErrorWithTimer('phone', null);
      }
    } catch (e) {
      debugPrint("Check phone error: $e");
    }
  }

  void _submitRequest() async {
    setState(() => _isLoading = true);
    
    await _validateUsername();
    await _validateEmail();
    _validatePassword();
    _validateConfirmPassword();
    _validateFullName();
    _validateLicense();
    await _validatePhone();

    if (_usernameError != null || _emailError != null || _passwordError != null ||
        _confirmPasswordError != null || _fullNameError != null || _licenseError != null ||
        _phoneError != null || !_termsAccepted) {
      
      String msg = 'complete_form_correctly';

      if (mounted) {
        CustomSnackBar.show(context, message: AppLocalizations.get(msg), isError: true);
      }
      setState(() => _isLoading = false);
      return;
    }

    try {
      final registerData = {
        'username': _usernameController.text.trim(),
        'name': _fullNameController.text.trim(),
        'email': _emailController.text.trim(),
        'password': _passwordController.text,
        'role': 'driver',
        'phone': _phoneController.text.trim(),
        'license_number': _licenseController.text.trim(),
        'preferred_truck': _truckController.text.trim(),
        'termsAccepted': 1,
        'privacyPolicyAccepted': 1,
        'termsVersion': '1.0',
        'privacyPolicyVersion': '1.0',
        'consentTimestamp': DateTime.now().toIso8601String(),
      };

      final response = await _apiService.register(registerData);

      if (response.data['success'] == true) {
        try {
          await FirebaseDatabase.instance.ref('notifications').push().set({
            "type": "REGISTRATION",
            "title": AppLocalizations.get('new_driver_reg_title'),
            "message": AppLocalizations.get('new_driver_reg_notif').replaceFirst('{name}', _fullNameController.text.trim()),
            "timestamp": ServerValue.timestamp,
            "isRead": false,
            "relatedId": _usernameController.text.trim(),
          });
        } catch (e) {
          debugPrint("Firebase Notification Error: $e");
        }

        if (!mounted) return;
        CustomSnackBar.show(
          context,
          message: response.data['message'] ?? AppLocalizations.get('reg_success'),
        );
        
        // Bumalik sa simula (Welcome/Login Screen) para hindi mag-login nang hindi pa approved
        Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
      } else {
        if (!mounted) return;
        CustomSnackBar.show(
          context,
          message: response.data['message'] ?? AppLocalizations.get('reg_failed'),
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: AppLocalizations.get('err_network'),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double screenWidth = MediaQuery.of(context).size.width;
    final double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final bool isMobile = Responsive.isMobile(context);
    
    return AnimatedAuthBackground(
      resizeToAvoidBottomInset: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          top: false,
          child: Stack(
            children: [
              // Main Scrollable Content
              Positioned.fill(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                    horizontal: screenWidth > 600 ? 40 : 24, 
                    vertical: screenHeight * 0.02,
                  ),
                  child: Column(
                    children: [
                      // Space for fixed header elements (Increased for new fixed layout)
                      const SizedBox(height: 140),

                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 500),
                          child: Column(
                            children: [
                              FadeSlideEntrance(
                                key: const ValueKey('driver_reg_form_container'),
                                delay: const Duration(milliseconds: 300),
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: screenWidth > 600 ? 40 : 32, 
                                    vertical: screenHeight * 0.04,
                                  ),
                                  decoration: AppDecorations.authCardDecoration(), // Applied High-Depth Shadow
                                  child: Form(
                                    key: _formKey,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildSectionHeader(Icons.lock_outline_rounded, AppLocalizations.get('credentials')),
                                        const SizedBox(height: 8),
                                        _buildInput(_usernameController, AppLocalizations.get('username'), AppLocalizations.get('username'), icon: Icons.person_outline_rounded, focus: _usernameFocus, error: _usernameError),
                                        _buildInput(_emailController, AppLocalizations.get('email'), AppLocalizations.get('email'), icon: Icons.email_outlined, focus: _emailFocus, error: _emailError),
                                        _buildInput(_passwordController, AppLocalizations.get('password'), AppLocalizations.get('password'), isPass: true, obs: _obs1, onToggle: () => setState(() => _obs1 = !_obs1), icon: Icons.lock_outline_rounded, focus: _passwordFocus, error: _passwordError),
                                        _buildInput(_confirmPasswordController, AppLocalizations.get('confirm_password'), AppLocalizations.get('confirm_password'), isPass: true, obs: _obs2, onToggle: () => setState(() => _obs2 = !_obs2), icon: Icons.lock_clock_outlined, focus: _confirmPasswordFocus, error: _confirmPasswordError),

                                        const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Divider(height: 1, color: Color(0x1F000000))),

                                        _buildSectionHeader(Icons.local_shipping_outlined, AppLocalizations.get('work_info')),
                                        const SizedBox(height: 8),
                                        _buildInput(_fullNameController, AppLocalizations.get('full_name'), AppLocalizations.get('full_name'), icon: Icons.face_outlined, focus: _fullNameFocus, error: _fullNameError),
                                        _buildInput(_licenseController, AppLocalizations.get('license_number'), AppLocalizations.get('license_number'), icon: Icons.badge_outlined, focus: _licenseFocus, error: _licenseError),
                                        _buildInput(_phoneController, AppLocalizations.get('contact_number'), AppLocalizations.get('contact_number'), icon: Icons.phone_android_outlined, focus: _phoneFocus, error: _phoneError),
                                        _buildInput(_truckController, AppLocalizations.get('preferred_truck'), AppLocalizations.get('preferred_truck'), action: TextInputAction.done, icon: Icons.local_shipping_outlined, error: null),

                                        const SizedBox(height: 32),
                                        _buildTermsCheckbox(),
                                        const SizedBox(height: 32),
                                        HoverActionButton(
                                          text: AppLocalizations.get('register_as_driver'),
                                          loadingText: AppLocalizations.get('processing_registration'),
                                          onTap: _submitRequest,
                                          isLoading: _isLoading,
                                        ),

                                        const SizedBox(height: 16),
                                        Center(
                                          child: _HoverZoomLink(
                                            onTap: () {
                                              _clearAllErrors();
                                              Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
                                            },
                                            child: Text(AppLocalizations.get('back_to_login'), style: const TextStyle(color: AppColors.textGray, fontWeight: FontWeight.bold, fontSize: 15)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Footer (Scrollable on all platforms)
                      const SizedBox(height: 60),
                      FadeSlideEntrance(
                        key: const ValueKey('driver_reg_footer'),
                        delay: const Duration(milliseconds: 500),
                        child: _buildFooter(),
                      ),
                      const SizedBox(height: 20),
                      // Keyboard Spacer
                      SizedBox(height: keyboardHeight),
                    ],
                  ),
                ),
              ),

              // Fixed Back Button & Header (All Platforms)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 120),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFFE0F2F1).withOpacity(0.95),
                        const Color(0xFFE0F2F1).withOpacity(0.9),
                        const Color(0xFFE0F2F1).withOpacity(0.0),
                      ],
                      stops: const [0.0, 0.25, 0.75],
                    ),
                  ),
                  child: SafeArea(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildBackButton(),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildHeaderContent(),
                        ),
                      ],
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

  Widget _buildFooter() {
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
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
        const SizedBox(height: 12),
        Text(AppLocalizations.get('brgy_footer'), style: ResponsiveText.footer(context, bold: true)),
        Text(AppLocalizations.get('all_rights_reserved'), style: ResponsiveText.footer(context, size: 10)),
      ],
    );
  }

  Widget _buildTermsCheckbox() {
    return Row(
      children: [
        SizedBox(
          height: 24, width: 24,
          child: Checkbox(
            value: _termsAccepted,
            onChanged: (v) => setState(() => _termsAccepted = v ?? false),
            activeColor: AppColors.tealText,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            children: [
              Text(AppLocalizations.get('agree_terms'), style: ResponsiveText.body(context)),
              const SizedBox(width: 4),
              _HoverZoomLink(
                onTap: () {
                  _clearAllErrors();
                  LegalAgreementDialog.show(context, isTerms: true);
                },
                child: Text(AppLocalizations.get('terms_conditions'), style: ResponsiveText.link(context).copyWith(decoration: TextDecoration.underline)),
              ),
              const SizedBox(width: 4),
              Text(AppLocalizations.get('and'), style: ResponsiveText.body(context)),
              const SizedBox(width: 4),
              _HoverZoomLink(
                onTap: () {
                  _clearAllErrors();
                  LegalAgreementDialog.show(context, isTerms: false);
                },
                child: Text(AppLocalizations.get('privacy_policy'), style: ResponsiveText.link(context).copyWith(decoration: TextDecoration.underline)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBackButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(150),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF00796B), size: 20),
        onPressed: () {
          _clearAllErrors();
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          } else {
            Navigator.pushNamedAndRemoveUntil(context, '/register', (route) => false);
          }
        },
      ),
    );
  }

  Widget _buildHeaderContent() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(AppLocalizations.get('driver'), style: ResponsiveText.screenHeader(context)),
              Text(
                AppLocalizations.get('driver_desc'), 
                style: TextStyle(
                  color: AppColors.textGray, 
                  fontSize: ResponsiveText.getFontSize(context, 13), 
                  fontWeight: FontWeight.w500
                ),
              ),
            ],
          ),
        ),
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
            width: ResponsiveText.getIconSize(context, 48),
            height: ResponsiveText.getIconSize(context, 48),
            decoration: BoxDecoration(color: AppColors.tealText.withAlpha(30), shape: BoxShape.circle),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Icon(
                Icons.local_shipping_rounded, 
                key: const ValueKey(Icons.local_shipping_rounded),
                color: AppColors.tealText, 
                size: ResponsiveText.getIconSize(context, 24)
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: AppColors.tealText, size: 22),
        const SizedBox(width: 12),
        Text(title, style: ResponsiveText.screenHeader(context).copyWith(fontSize: ResponsiveText.getFontSize(context, 18), letterSpacing: -0.5)),
      ],
    );
  }

  Widget _buildInput(TextEditingController ctrl, String label, String hint, {IconData? icon, bool isPass = false, bool obs = false, VoidCallback? onToggle, TextInputAction action = TextInputAction.next, FocusNode? focus, String? error}) {
    bool hasFocus = focus?.hasFocus ?? false;
    String? localizedError = error != null ? AppLocalizations.get(error) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 24, left: 4, bottom: 8), child: Text(label, style: ResponsiveText.inputLabel(context))),
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
            controller: ctrl, focusNode: focus, obscureText: obs, textInputAction: action,
            cursorColor: const Color(0xFF424242),
            inputFormatters: label.contains(AppLocalizations.get('contact_number')) ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)] : null,
            style: ResponsiveText.inputText(context),
            onFieldSubmitted: (_) { if(action == TextInputAction.done) _submitRequest(); },
            decoration: InputDecoration(
              hintText: hint, hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 15, fontWeight: FontWeight.w400),
              prefixIcon: icon != null ? Icon(icon, color: hasFocus ? AppColors.tealText : AppColors.tealText.withAlpha(150), size: 20) : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18), filled: true, fillColor: hasFocus ? Colors.white : Colors.grey.shade50,
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: localizedError != null ? Colors.redAccent : Colors.grey.shade200, width: 1.5)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: localizedError != null ? Colors.redAccent : AppColors.tealText, width: 2)),
              suffixIcon: isPass ? IconButton(icon: Icon(obs ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Colors.grey.shade500, size: 20), onPressed: onToggle) : null,
            ),
          ),
        ),
        if (localizedError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 8),
            child: Text(localizedError, style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
      ],
    );
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
