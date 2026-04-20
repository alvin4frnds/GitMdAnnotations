import 'package:flutter/material.dart';

/// Design tokens from PRD §5.11.1.
///
/// Ink colors are stored as canonical light-mode hex in SVG; the dark palette
/// is applied only at render time via [InkColorAdapter]. Do not leak dark-mode
/// hex into persistence layers.
@immutable
class AppTokens {
  final Color surfaceBackground;
  final Color surfaceElevated;
  final Color surfaceSunken;
  final Color borderSubtle;
  final Color textPrimary;
  final Color textMuted;
  final Color accentPrimary;
  final Color accentSoftBg;
  final Color statusSuccess;
  final Color statusWarning;
  final Color statusDanger;
  final Color inkRed;
  final Color inkBlue;
  final Color inkGreen;
  final Color inkYellowHighlight;
  final Brightness brightness;

  const AppTokens({
    required this.surfaceBackground,
    required this.surfaceElevated,
    required this.surfaceSunken,
    required this.borderSubtle,
    required this.textPrimary,
    required this.textMuted,
    required this.accentPrimary,
    required this.accentSoftBg,
    required this.statusSuccess,
    required this.statusWarning,
    required this.statusDanger,
    required this.inkRed,
    required this.inkBlue,
    required this.inkGreen,
    required this.inkYellowHighlight,
    required this.brightness,
  });

  static const light = AppTokens(
    surfaceBackground: Color(0xFFFAFAF9),
    surfaceElevated: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFF3F4F6),
    borderSubtle: Color(0xFFE5E7EB),
    textPrimary: Color(0xFF111827),
    textMuted: Color(0xFF6B7280),
    accentPrimary: Color(0xFF4F46E5),
    accentSoftBg: Color(0xFFEEF2FF),
    statusSuccess: Color(0xFF059669),
    statusWarning: Color(0xFFB45309),
    statusDanger: Color(0xFFDC2626),
    inkRed: Color(0xFFDC2626),
    inkBlue: Color(0xFF2563EB),
    inkGreen: Color(0xFF059669),
    inkYellowHighlight: Color(0xFFFEF9C3),
    brightness: Brightness.light,
  );

  static const dark = AppTokens(
    surfaceBackground: Color(0xFF0A0A0B),
    surfaceElevated: Color(0xFF18181B),
    surfaceSunken: Color(0xFF0F0F10),
    borderSubtle: Color(0xFF27272A),
    textPrimary: Color(0xFFF3F4F6),
    textMuted: Color(0xFFA1A1AA),
    accentPrimary: Color(0xFF6366F1),
    accentSoftBg: Color(0x266366F1),
    statusSuccess: Color(0xFF6EE7B7),
    statusWarning: Color(0xFFFCD34D),
    statusDanger: Color(0xFFF87171),
    inkRed: Color(0xFFF87171),
    inkBlue: Color(0xFF60A5FA),
    inkGreen: Color(0xFF34D399),
    inkYellowHighlight: Color(0x40FACC15),
    brightness: Brightness.dark,
  );
}

extension AppTokensX on BuildContext {
  AppTokens get tokens =>
      Theme.of(this).brightness == Brightness.dark ? AppTokens.dark : AppTokens.light;
}
