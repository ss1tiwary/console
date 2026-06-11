import 'package:flutter/material.dart';

/// Color constants for the console — mirrors PIBrief's AppPalette so shared
/// admin screens can be ported with minimal diff. Kept in sync by hand.
class AppPalette {
  AppPalette._();

  static const Color white = Color(0xFFFFFFFF);
  static const Color grey50 = Color(0xFFF8F9FA);
  static const Color grey100 = Color(0xFFF1F3F5);
  static const Color grey200 = Color(0xFFE9ECEF);
  static const Color grey300 = Color(0xFFDEE2E6);
  static const Color grey400 = Color(0xFFADB5BD);
  static const Color grey600 = Color(0xFF6C757D);
  static const Color grey700 = Color(0xFF495057);
  static const Color grey800 = Color(0xFF343A40);
  static const Color grey900 = Color(0xFF212529);

  static const Color indigo = Color(0xFF4263EB);
  static const Color indigoLight = Color(0xFFEDF2FF);
  static const Color indigoDark = Color(0xFF3451C7);

  static const Color green = Color(0xFF2F9E44);
  static const Color greenLight = Color(0xFFEBFBEE);
  static const Color amber = Color(0xFFF08C00);
  static const Color amberLight = Color(0xFFFFF3BF);
  static const Color red = Color(0xFFE03131);
  static const Color redLight = Color(0xFFFFF5F5);
}
