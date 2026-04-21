import 'package:flutter/material.dart';

import 'tokens.dart';

/// Builds the app's [ThemeData] from [AppTokens].
///
/// Typography: Inter (body) and JetBrains Mono (code/breadcrumb) are bundled
/// as asset fonts — see `pubspec.yaml` fonts block and `assets/fonts/*.otf/.ttf`.
/// Caveat (handwriting) is still system italic; revisit when the annotation
/// canvas ships margin-note polish (M1d).
class AppTheme {
  static ThemeData build(AppTokens t) {
    final base = t.brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light();

    return base.copyWith(
      brightness: t.brightness,
      scaffoldBackgroundColor: t.surfaceBackground,
      canvasColor: t.surfaceBackground,
      // Applies to the whole subtree unless a TextStyle supplies fontFamily
      // itself (e.g. appMono uses JetBrainsMono).
      textTheme: (t.brightness == Brightness.dark
              ? ThemeData.dark().textTheme
              : ThemeData.light().textTheme)
          .apply(
        fontFamily: 'Inter',
        bodyColor: t.textPrimary,
        displayColor: t.textPrimary,
      ),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'Inter'),
      colorScheme: ColorScheme(
        brightness: t.brightness,
        primary: t.accentPrimary,
        onPrimary: t.brightness == Brightness.dark ? t.textPrimary : Colors.white,
        secondary: t.accentPrimary,
        onSecondary: t.brightness == Brightness.dark ? t.textPrimary : Colors.white,
        error: t.statusDanger,
        onError: Colors.white,
        surface: t.surfaceElevated,
        onSurface: t.textPrimary,
      ),
      dividerColor: t.borderSubtle,
      appBarTheme: AppBarTheme(
        backgroundColor: t.surfaceElevated,
        foregroundColor: t.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: t.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: t.accentPrimary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: t.textPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

/// Monospace text style used for commit SHAs, file paths, log lines, and
/// the JobList header breadcrumb. Uses bundled JetBrains Mono — see
/// `pubspec.yaml` fonts section and `assets/fonts/JetBrainsMono-*.ttf`.
TextStyle appMono(BuildContext context, {double size = 12, FontWeight? weight, Color? color}) {
  return TextStyle(
    fontFamily: 'JetBrainsMono',
    fontSize: size,
    fontWeight: weight ?? FontWeight.w400,
    color: color ?? context.tokens.textPrimary,
  );
}

/// Handwriting style used for margin notes on the annotation canvas. Currently
/// italic system font as a stand-in for Caveat; swap once bundled.
TextStyle appHandwriting(BuildContext context, {double size = 20, Color? color}) {
  return TextStyle(
    fontSize: size,
    fontStyle: FontStyle.italic,
    fontWeight: FontWeight.w500,
    color: color ?? context.tokens.inkRed,
  );
}
