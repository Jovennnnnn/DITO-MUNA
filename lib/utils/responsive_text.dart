import 'package:flutter/material.dart';
import 'responsive.dart';
import 'app_theme.dart';

class ResponsiveText {
  static double getScaleFactor(BuildContext context) {
    if (Responsive.isDesktop(context)) {
      return 1.2; // Scaled for Web/Desktop
    } else if (Responsive.isTablet(context)) {
      return 1.1; // Scaled for Tablet
    }
    return 1.0; // Standard for Mobile
  }

  static double getFontSize(BuildContext context, double mobileSize) {
    return mobileSize * getScaleFactor(context);
  }

  static double getIconSize(BuildContext context, double mobileSize) {
    return mobileSize * getScaleFactor(context);
  }

  // Branding Title (e.g., "Garbage Tracker")
  static TextStyle brandingTitle(BuildContext context) => TextStyle(
    fontSize: getFontSize(context, 30),
    fontWeight: FontWeight.w900,
    color: AppColors.tealText,
    letterSpacing: -1.2,
  );

  // Subtitle / Welcome Text
  static TextStyle brandingSubtitle(BuildContext context) => TextStyle(
    fontSize: getFontSize(context, 14),
    color: AppColors.textGray,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );

  // Screen Headers (e.g., "Account Recovery")
  static TextStyle screenHeader(BuildContext context) => TextStyle(
    fontSize: getFontSize(context, 28),
    fontWeight: FontWeight.w900,
    color: AppColors.tealText,
    letterSpacing: -1,
  );

  // Input Field Labels
  static TextStyle inputLabel(BuildContext context) => TextStyle(
    fontSize: getFontSize(context, 13),
    fontWeight: FontWeight.w800,
    color: AppColors.inputLabel,
    letterSpacing: 0.2,
  );

  // Input Field Text
  static TextStyle inputText(BuildContext context) => TextStyle(
    fontSize: getFontSize(context, 15),
    fontWeight: FontWeight.w600,
    color: AppColors.inputLabel,
  );

  // Body Text / Regular Info
  static TextStyle body(BuildContext context, {Color color = AppColors.textGray}) => TextStyle(
    fontSize: getFontSize(context, 13),
    fontWeight: FontWeight.w600,
    color: color,
  );

  // Hyperlinks / Bold Accents
  static TextStyle link(BuildContext context, {Color color = AppColors.tealLink}) => TextStyle(
    fontSize: getFontSize(context, 13),
    fontWeight: FontWeight.w900,
    color: color,
  );

  // Footer Text
  static TextStyle footer(BuildContext context, {bool bold = false, double size = 12}) => TextStyle(
    fontSize: getFontSize(context, size),
    fontWeight: bold ? FontWeight.bold : FontWeight.w500,
    color: const Color(0xFF00796B),
  );
}
