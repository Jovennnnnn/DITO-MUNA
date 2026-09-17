import 'package:flutter/material.dart';
import '../api/api_service.dart';
import '../utils/session_manager.dart';
import '../utils/app_theme.dart';
import '../utils/custom_notification.dart';
import '../utils/app_localizations.dart';
import 'dart:async';

class Verify2FAScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  const Verify2FAScreen({super.key, required this.userData});

  @override
  State<Verify2FAScreen> createState() => _Verify2FAScreenState();
}

class _Verify2FAScreenState extends State<Verify2FAScreen> {
  final TextEditingController _otpController = TextEditingController();
  bool _isLoading = false;
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    AppLocalizations.currentLanguage.addListener(_onLanguageChanged);
  }

  @override
  void dispose() {
    AppLocalizations.currentLanguage.removeListener(_onLanguageChanged);
    _otpController.dispose();
    super.dispose();
  }

  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  void _handleVerify() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      CustomNotification.showTopNotification(context, AppLocalizations.get('enter_otp_code'));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final email = widget.userData['email'];
      debugPrint("Verifying OTP for: $email with code: $otp");
      
      final response = await _apiService.verifyOTP(email, otp);
      final data = response.data;
      
      debugPrint("Verify Response: $data");

      if (data is Map && data['success'] == true) {
        debugPrint("Verification success! Saving session and navigating...");
        try {
          await SessionManager.saveUser(widget.userData);
          debugPrint("Session saved successfully.");
        } catch (sessionError) {
          debugPrint("Session Save Error: $sessionError");
          if (!mounted) return;
          CustomNotification.showTopNotification(context, AppLocalizations.get('err_general'));
          setState(() => _isLoading = false);
          return;
        }
        
        if (!mounted) return;
        CustomNotification.showTopNotification(context, AppLocalizations.get('verification_successful'), false);

        Timer(const Duration(milliseconds: 800), () {
          if (!mounted) return;
          String role = widget.userData['role'].toString().toLowerCase();
          debugPrint("Navigating to dashboard for role: $role");
          
          if (role == 'admin') {
            Navigator.pushNamedAndRemoveUntil(context, '/admin_dashboard', (route) => false);
          } else if (role == 'resident') {
            Navigator.pushNamedAndRemoveUntil(context, '/resident_dashboard', (route) => false);
          } else if (role == 'driver') {
            Navigator.pushNamedAndRemoveUntil(context, '/driver_dashboard', (route) => false);
          } else {
            debugPrint("Unknown role: $role. Redirecting to home.");
            Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
          }
        });
      } else {
        if (!mounted) return;
        String msg = AppLocalizations.get('err_otp_invalid');
        if (data is Map && data['message'] != null) msg = data['message'];
        
        CustomNotification.showTopNotification(context, msg);
      }
    } catch (e) {
      debugPrint("Verify Error: $e");
      if (!mounted) return;
      CustomNotification.showTopNotification(context, AppLocalizations.get('err_network'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleResend() async {
    try {
      CustomNotification.showTopNotification(context, AppLocalizations.get('sending_code'), false);
      await _apiService.forgotPassword(widget.userData['email']);
    } catch (e) {
      if (!mounted) return;
      CustomNotification.showTopNotification(context, AppLocalizations.get('err_resend_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: AppDecorations.loginBackground,
        child: Center(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 450),
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(245),
                borderRadius: BorderRadius.circular(40),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(20),
                    blurRadius: 30,
                    offset: const Offset(0, 15),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF1F8E9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.security_rounded, size: 40, color: Color(0xFF4CAF50)),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    AppLocalizations.get('two_step_verification'),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1A1A1A),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    AppLocalizations.get('otp_email_msg').replaceFirst('{email}', widget.userData['email']),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF757575),
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 40),
                  TextField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 12,
                      color: Color(0xFF1A1A1A),
                    ),
                    decoration: InputDecoration(
                      counterText: "",
                      hintText: "000000",
                      hintStyle: TextStyle(color: Colors.grey.shade300, letterSpacing: 12),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      contentPadding: const EdgeInsets.symmetric(vertical: 20),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: Colors.grey.shade200, width: 2),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: Color(0xFF00BFA5), width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleVerify,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00BFA5),
                      minimumSize: const Size(double.infinity, 64),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            AppLocalizations.get('verify_login'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                  ),
                  const SizedBox(height: 24),
                  if (MediaQuery.of(context).viewInsets.bottom == 0) ...[
                    TextButton(
                      onPressed: _isLoading ? null : _handleResend,
                      child: Text(
                        AppLocalizations.get('resend_code'),
                        style: const TextStyle(
                          color: Color(0xFF00BFA5),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        AppLocalizations.get('back_to_login'),
                        style: const TextStyle(
                          color: Color(0xFF757575),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
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
