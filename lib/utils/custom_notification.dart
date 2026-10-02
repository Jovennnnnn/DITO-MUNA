import 'package:flutter/material.dart';

class CustomNotification {
  static void showTopNotification(BuildContext context, String message, [bool isError = true]) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double screenWidth = MediaQuery.of(context).size.width;
    final double topPadding = MediaQuery.of(context).padding.top;
    
    // Adaptive font size
    final double fontSize = (screenWidth * 0.04).clamp(12.0, 15.0);

    // Responsive positioning: Just under status bar on mobile, bit lower on desktop
    final bool isDesktop = screenWidth >= 900;
    final double topGap = isDesktop ? 32.0 : 10.0;
    final double topMargin = topPadding + topGap;
    
    // Estimate snackbar height for top positioning
    const double estimatedHeight = 52.0; 
    final double bottomMargin = screenHeight - topMargin - estimatedHeight;

    // Adaptive horizontal margin for width control: 
    // Desktop gets 420 max width, Tablet gets 380 max width, Mobile gets a compact centered width
    final double maxNotificationWidth = screenWidth >= 900 
        ? 420.0 
        : (screenWidth >= 600 ? 380.0 : (screenWidth * 0.85).clamp(280.0, 350.0));
    final double horizontalMargin = (screenWidth - maxNotificationWidth) / 2;

    ScaffoldMessenger.of(context).clearSnackBars(); 
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message, 
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w800, 
            fontSize: fontSize,
            color: Colors.white,
            letterSpacing: 0.1,
          )
        ),
        backgroundColor: isError ? Colors.redAccent.shade400 : const Color(0xFF00796B),
        behavior: SnackBarBehavior.floating,
        dismissDirection: DismissDirection.up,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), // Further reduced vertical padding to 6 to make it very thin
        margin: EdgeInsets.only(
          bottom: (screenHeight - topMargin - 40).clamp(0.0, screenHeight - 80), // Adjusted for thinner snackbar height
          left: horizontalMargin,
          right: horizontalMargin,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), // Slightly tighter radius for thinner look
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
