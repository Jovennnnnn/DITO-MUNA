import 'package:flutter/material.dart';

class AppColors {
  static const Color tealText = Color(0xFF00796B);
  static const Color tealLink = Color(0xFF00796B);
  static const Color textGray = Color(0xFF757575);
  static const Color inputLabel = Color(0xFF1A1A1A);
  
  // Login Button Gradient
  static const Color loginButtonStart = Color(0xFF00796B);
  static const Color loginButtonEnd = Color(0xFF004D40);

  // Dashboard Colors
  static const Color dashboardBg = Color(0xFFF8F9FA);
  static const Color statActiveBg = Color(0xFFE0F2F1);
  static const Color statEtaBg = Color(0xFFFFF9C4);

  // Status Colors
  static const Color statusGreen = Color(0xFF4CAF50);
}

extension ColorExtension on Color {
  Color darken([double amount = .1]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(this);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return hslDark.toColor();
  }
}

class AppDecorations {
  // ORIGINAL AUTH GRADIENT (Green and White "Palabo na Palinaw")
  static BoxDecoration get authBackground => const BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFFE0F2F1), // Very light teal/white
        Colors.white,       // Pure white center
        Color(0xFFB2DFDB), // Soft teal bottom (palabo effect)
      ],
    ),
  );

  static BoxDecoration get loginBackground => authBackground;

  // Enhanced "Angat" Card Decoration for Auth Screens
  static BoxDecoration authCardDecoration({Color color = Colors.white, double radius = 40.0}) => BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: Colors.white, width: 2), // Clean white border to define edges
    boxShadow: AppTheme.authDeepShadow, // Using the new deeper shadow
  );

  static BoxDecoration cardDecoration({Color color = Colors.white, double radius = 24.0}) => BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: AppTheme.pulidongShadow,
  );
}

class AppTheme {
  // Standard Polished Shadow
  static const List<BoxShadow> pulidongShadow = [
    BoxShadow(
      color: Color(0x1A000000), // 10% black
      blurRadius: 20,
      offset: Offset(0, 10),
      spreadRadius: -2,
    ),
    BoxShadow(
      color: Color(0x0D000000), // 5% black
      blurRadius: 10,
      offset: Offset(0, 4),
      spreadRadius: -1,
    ),
  ];

  // Deep Highlighted Shadow for Auth Containers ("Angat" effect)
  static const List<BoxShadow> authDeepShadow = [
    BoxShadow(
      color: Color(0x26000000), // 15% black - Deeper base
      blurRadius: 50,
      offset: Offset(0, 25),
      spreadRadius: -10,
    ),
    BoxShadow(
      color: Color(0x14000000), // 8% black - Secondary definition
      blurRadius: 20,
      offset: Offset(0, 10),
      spreadRadius: -5,
    ),
    BoxShadow(
      color: Color(0x0A000000), // 4% black - Large atmospheric glow
      blurRadius: 80,
      offset: Offset(0, 40),
      spreadRadius: -20,
    ),
  ];

  // Extra Deep Shadow for Dashboard Highlight
  static const List<BoxShadow> deepPulidongShadow = [
    BoxShadow(
      color: Color(0x26000000), // 15% black
      blurRadius: 30,
      offset: Offset(0, 15),
      spreadRadius: -5,
    ),
    BoxShadow(
      color: Color(0x0D000000), // 5% black
      blurRadius: 10,
      offset: Offset(0, 5),
    ),
  ];

  // Balanced Shadows (Visible on all sides: Top, Bottom, Left, Right)
  static const List<BoxShadow> balancedPulidongShadow = [
    BoxShadow(
      color: Color(0x14000000), // 8% black
      blurRadius: 20,
      offset: Offset(0, 0), // ZERO OFFSET for balance
      spreadRadius: 2,
    ),
    BoxShadow(
      color: Color(0x0A000000), // 4% black
      blurRadius: 10,
      offset: Offset(0, 0),
      spreadRadius: 1,
    ),
  ];

  static const List<BoxShadow> balancedDeepShadow = [
    BoxShadow(
      color: Color(0x1F000000), // 12% black
      blurRadius: 30,
      offset: Offset(0, 0),
      spreadRadius: 4,
    ),
    BoxShadow(
      color: Color(0x0D000000), // 5% black
      blurRadius: 15,
      offset: Offset(0, 0),
      spreadRadius: 2,
    ),
  ];

  // NEW: Ultra Highlighted Balanced Shadow for maximum pop
  static const List<BoxShadow> highIntensityBalancedShadow = [
    BoxShadow(
      color: Color(0x26000000), // 15% black
      blurRadius: 40,
      offset: Offset(0, 0),
      spreadRadius: 5,
    ),
    BoxShadow(
      color: Color(0x14000000), // 8% black
      blurRadius: 20,
      offset: Offset(0, 0),
      spreadRadius: 2,
    ),
  ];
}
