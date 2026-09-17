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

class ResidentRegisterScreen extends StatefulWidget {
  const ResidentRegisterScreen({super.key});

  @override
  State<ResidentRegisterScreen> createState() => _ResidentRegisterScreenState();
}

class _ResidentRegisterScreenState extends State<ResidentRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();

  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmPasswordFocus = FocusNode();
  final FocusNode _fullNameFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();

  String? _usernameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;
  String? _fullNameError;
  String? _phoneError;
  String? _addressError;

  String? _selectedPurok;
  bool _isLoading = false;
  bool _obs1 = true;
  bool _obs2 = true;
  bool _termsAccepted = false;
  final Map<String, Timer?> _errorTimers = {};

  final List<String> _puroks = ["Purok 2", "Purok 3", "Purok 4", "Dos Riles", "Sentro", "San Isidro", "Paraiso", "Riverside", "Kalaw Street", "Home Subdivision", "Tanco Road / Ayala Highway", "Brixton Area"];
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
    _addressController.addListener(_onAddressChanged);

    _usernameFocus.addListener(() { if (!_usernameFocus.hasFocus) _validateUsername(); setState(() {}); });
    _emailFocus.addListener(() { if (!_emailFocus.hasFocus) _validateEmail(); setState(() {}); });
    _passwordFocus.addListener(() { if (!_passwordFocus.hasFocus) _validatePassword(); setState(() {}); });
    _confirmPasswordFocus.addListener(() { if (!_confirmPasswordFocus.hasFocus) _validateConfirmPassword(); setState(() {}); });
    _fullNameFocus.addListener(() { if (!_fullNameFocus.hasFocus) _validateFullName(); setState(() {}); });
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

  void _onPhoneChanged() {
    if (_phoneError != null) {
      setState(() => _phoneError = null);
    }
  }

  void _onAddressChanged() {
    if (_addressError != null) {
      setState(() => _addressError = null);
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
    _addressController.removeListener(_onAddressChanged);

    _usernameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    _fullNameFocus.dispose();
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
      if (field == 'phone') _phoneError = errorKey;
      if (field == 'address') _addressError = errorKey;
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
            if (field == 'phone') _phoneError = null;
            if (field == 'address') _addressError = null;
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
      _phoneError = null;
      _addressError = null;
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

  void _handleRegister() async {
    setState(() => _isLoading = true);

    await _validateUsername();
    await _validateEmail();
    _validatePassword();
    _validateConfirmPassword();
    _validateFullName();
    await _validatePhone();

    // Address Validation
    if (_addressController.text.trim().isEmpty) {
      _setErrorWithTimer('address', 'complete_address');
    } else {
      _setErrorWithTimer('address', null);
    }

    if (_usernameError != null || _emailError != null || _passwordError != null ||
        _confirmPasswordError != null || _fullNameError != null || _phoneError != null ||
        _addressError != null || _selectedPurok == null || !_termsAccepted) {

      String msg = 'err_general';
      if (_selectedPurok == null) msg = 'err_purok_req';
      if (!_termsAccepted) msg = 'err_terms_req';
      
      // Override with "Please complete form" if most fields are missing or have errors
      msg = 'complete_form_correctly';

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
        'role': 'resident',
        'phone': _phoneController.text.trim(),
        'purok': _selectedPurok,
        'complete_address': _addressController.text.trim(),
        'termsAccepted': 1,
        'privacyPolicyAccepted': 1,
        'termsVersion': '1.0',
        'privacyPolicyVersion': '1.0',
        'consentTimestamp': DateTime.now().toIso8601String(),
      };

      final response = await _apiService.register(registerData);

      if (response.data['success'] == true) {
        final userId = response.data['user_id'];
        try {
          // Add to residents node for real-time dashboard updates
          if (userId != null) {
            await FirebaseDatabase.instance.ref('residents/$userId').set({
              'name': _fullNameController.text.trim(),
              'email': _emailController.text.trim(),
              'phone': _phoneController.text.trim(),
              'purok': _selectedPurok,
              'complete_address': _addressController.text.trim(),
              'role': 'resident',
              'created_at': ServerValue.timestamp,
            });
          }

          await FirebaseDatabase.instance.ref('notifications').push().set({
            'type': 'REGISTRATION',
            'title': AppLocalizations.get('new_reg_title'),
            'message': AppLocalizations.get('new_reg_notif').replaceFirst('{name}', _fullNameController.text.trim()),
            'timestamp': ServerValue.timestamp,
            'isRead': false,
            'relatedId': _usernameController.text
          });
        } catch (e) {
          debugPrint("Firebase Notification Error: $e");
        }

        if (!mounted) return;
        CustomSnackBar.show(
          context,
          message: response.data['message'] ?? AppLocalizations.get('reg_success'),
        );
        // Bumalik sa simula (Welcome/Login Screen)
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

  void _showPurokModal() {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isWide = screenWidth > 600;
    
    if (isWide) {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: _buildPurokContent(context),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (context) => _buildPurokContent(context),
      );
    }
  }

  Widget _buildPurokContent(BuildContext context) {
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
                AppLocalizations.get('select_purok'),
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
            AppLocalizations.get('purok_selection_desc'),
            style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 0),
            child: Divider(height: 32),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _puroks.length,
              itemBuilder: (context, index) {
                final p = _puroks[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(p, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.inputLabel)),
                  leading: Icon(Icons.location_on_outlined, color: _selectedPurok == p ? AppColors.tealText : Colors.grey),
                  trailing: _selectedPurok == p ? const Icon(Icons.check_circle, color: AppColors.tealText) : null,
                  onTap: () {
                    setState(() => _selectedPurok = p);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
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
                                key: const ValueKey('resident_reg_form_container'),
                                delay: const Duration(milliseconds: 300),
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: screenWidth > 600 ? 40 : 32, 
                                    vertical: screenHeight * 0.04,
                                  ),
                                  decoration: AppDecorations.authCardDecoration(),
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

                                        _buildSectionHeader(Icons.badge_outlined, AppLocalizations.get('personal_details')),
                                        const SizedBox(height: 8),
                                        _buildInput(_fullNameController, AppLocalizations.get('full_name'), AppLocalizations.get('full_name'), icon: Icons.face_outlined, focus: _fullNameFocus, error: _fullNameError),
                                        _buildInput(_phoneController, AppLocalizations.get('contact_number'), AppLocalizations.get('contact_number'), icon: Icons.phone_android_outlined, focus: _phoneFocus, error: _phoneError),
                                        _buildPurokSelector(),
                                        _buildInput(_addressController, AppLocalizations.get('complete_address'), AppLocalizations.get('complete_address'), maxLines: 3, action: TextInputAction.done, icon: Icons.home_outlined, error: _addressError),

                                        const SizedBox(height: 32),
                                        _buildTermsCheckbox(),
                                        const SizedBox(height: 32),
                                        HoverActionButton(
                                          text: AppLocalizations.get('submit_registration'),
                                          loadingText: AppLocalizations.get('processing_registration'),
                                          onTap: _handleRegister,
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
                        key: const ValueKey('resident_reg_footer'),
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
              Text(AppLocalizations.get('resident'), style: ResponsiveText.screenHeader(context)),
              Text(
                AppLocalizations.get('resident_desc'), 
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
                Icons.home_rounded, 
                key: const ValueKey(Icons.home_rounded),
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

  Widget _buildInput(TextEditingController ctrl, String label, String hint, {IconData? icon, bool isPass = false, bool obs = false, VoidCallback? onToggle, int maxLines = 1, TextInputAction action = TextInputAction.next, FocusNode? focus, String? error}) {
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
            controller: ctrl, focusNode: focus, obscureText: obs, maxLines: maxLines, textInputAction: action,
            cursorColor: const Color(0xFF424242),
            inputFormatters: label.contains(AppLocalizations.get('contact_number')) ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)] : null,
            style: ResponsiveText.inputText(context),
            onFieldSubmitted: (_) { if(action == TextInputAction.done) _handleRegister(); },
            decoration: InputDecoration(
              hintText: hint, hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14, fontWeight: FontWeight.w400),
              prefixIcon: icon != null ? Icon(icon, color: hasFocus ? AppColors.tealText : AppColors.tealText.withAlpha(150), size: 20) : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18), filled: true, fillColor: hasFocus ? Colors.white : Colors.grey.shade50,
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: localizedError != null ? Colors.redAccent : Colors.grey.shade200, width: 1.2)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: localizedError != null ? Colors.redAccent : AppColors.tealText, width: 2.0)),
              suffixIcon: isPass ? 
                IconButton(
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Icon(obs ? Icons.visibility_off_rounded : Icons.visibility_rounded, key: ValueKey(obs), color: hasFocus ? AppColors.tealText : Colors.grey.shade500, size: 20),
                  ),
                  onPressed: onToggle
                ) : null,
            ),
          ),
        ),
        if (localizedError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(localizedError, style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }

  Widget _buildPurokSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 24, left: 4, bottom: 8), child: Text(AppLocalizations.get('purok'), style: ResponsiveText.inputLabel(context))),
        InkWell(
          onTap: _showPurokModal,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200, width: 1.2)),
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined, color: Color(0xB400796B), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedPurok ?? AppLocalizations.get('select_location'),
                    style: ResponsiveText.inputText(context).copyWith(color: _selectedPurok == null ? Colors.grey.shade400 : AppColors.inputLabel, fontWeight: _selectedPurok == null ? FontWeight.w400 : FontWeight.w600, fontSize: 14),
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.tealText, size: 24),
              ],
            ),
          ),
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
