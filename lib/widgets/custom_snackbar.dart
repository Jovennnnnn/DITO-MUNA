import 'package:flutter/material.dart';

class CustomSnackBar {
  static void show(
    BuildContext context, {
    required String message,
    bool isError = false,
    bool isModal = false,
  }) {
    // Hide current snackbar to avoid overlaps
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    
    final double screenWidth = MediaQuery.of(context).size.width;
    final double screenHeight = MediaQuery.of(context).size.height;
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    final double bottomViewInsets = MediaQuery.of(context).viewInsets.bottom;
    
    // Adaptive width logic: "sakto lang" (centered and not too wide)
    final double targetWidth = screenWidth > 600 ? 400.0 : (screenWidth * 0.7).clamp(200.0, 300.0);
    final double horizontalMarginFinal = (screenWidth - targetWidth) / 2;
    
    // Adaptive font size: 12-14 depending on width
    final double fontSize = (screenWidth * 0.035).clamp(12.0, 14.0);

    // CRITICAL: Precise top positioning logic
    final double snackBarHeight = 60.0; // Approximate height including padding
    final double topMargin = statusBarHeight + 10.0; // 10px spacing from status bar
    final double bottomMargin = screenHeight - topMargin - snackBarHeight;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: fontSize,
          ),
          textAlign: TextAlign.center,
        ),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF00897B),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: bottomMargin.clamp(0.0, screenHeight - 100),
          left: horizontalMarginFinal,
          right: horizontalMarginFinal,
        ),
        elevation: 6,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
